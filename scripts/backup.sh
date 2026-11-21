#!/usr/bin/env bash
# 把 back_ck_url.txt 里的每个仓库克隆成裸镜像、压缩（zstd）、校验后上传到指定 Release。
#
# 环境变量：
#   TAG            必填，目标 Release tag
#   WORKSPACE      工作目录（默认当前目录）
#   LIST_FILE      仓库清单（默认 $WORKSPACE/back_ck_url.txt）
#   DRY_RUN        1 = 只克隆/压缩/校验，不上传
#   LIMIT          >0 时只处理前 N 个仓库
#   REPO_FILTER    只处理 URL 含该子串的仓库
#   MAX_PART_MB    单文件上限，超过则分卷（默认 1800）
#   CLONE_TIMEOUT  单次克隆超时秒数（默认 900）
#   MIN_FREE_MB    磁盘低水位（默认 2000）
#   SHARD_INDEX    当前分片编号（默认 0）
#   SHARD_TOTAL    分片总数（默认 1 = 不分片；>1 时按清单顺序取模分组，用于 matrix 并行）
#   FULL_MIRROR    1 = 忽略清单里的 #shallow 标记，全部做完整 mirror（每周全量任务用）
#   ONLY_SHALLOW   1 = 只处理清单里标了 #shallow 的仓库（每周全量任务用）
#   MANIFEST_FILE  清单输出路径（默认 $WORKSPACE/manifest.tsv）
#   FAILED_FILE    失败清单输出路径（默认 $WORKSPACE/failed.tsv）
#
# 输出：
#   manifest.tsv   每个资产：repo url asset bytes sha256 commit backed_up_at
#   failed.tsv     失败仓库：repo reason
set -Eeuo pipefail
export LC_ALL=C

WORKSPACE=${WORKSPACE:-$(pwd)}
LIST_FILE=${LIST_FILE:-$WORKSPACE/back_ck_url.txt}
TAG=${TAG:-}
DRY_RUN=${DRY_RUN:-0}
LIMIT=${LIMIT:-0}
REPO_FILTER=${REPO_FILTER:-}
MAX_PART_MB=${MAX_PART_MB:-1800}
CLONE_TIMEOUT=${CLONE_TIMEOUT:-900}
CLONE_MAX_TIMEOUT=${CLONE_MAX_TIMEOUT:-3600}
CLONE_SEC_PER_MB=${CLONE_SEC_PER_MB:-2}
MAX_CLONE_MB=${MAX_CLONE_MB:-8000}
FSCK_TIMEOUT=${FSCK_TIMEOUT:-900}
FSCK_MAX_TIMEOUT=${FSCK_MAX_TIMEOUT:-1800}
SHARD_MAP=${SHARD_MAP:-$WORKSPACE/shardmap.tsv}
MIN_FREE_MB=${MIN_FREE_MB:-2000}
SHARD_INDEX=${SHARD_INDEX:-0}
SHARD_TOTAL=${SHARD_TOTAL:-1}
FULL_MIRROR=${FULL_MIRROR:-0}
ONLY_SHALLOW=${ONLY_SHALLOW:-0}
MANIFEST=${MANIFEST_FILE:-$WORKSPACE/manifest.tsv}
FAILED=${FAILED_FILE:-$WORKSPACE/failed.tsv}

TMP_DIR="$WORKSPACE/backup_temp"
OUT_DIR="$WORKSPACE/compressed_backups"

[[ -n $TAG ]] || { echo "TAG 未设置" >&2; exit 2; }
[[ -f $LIST_FILE ]] || { echo "清单不存在: $LIST_FILE" >&2; exit 2; }
[[ $LIMIT =~ ^[0-9]+$ ]] || LIMIT=0
[[ $SHARD_TOTAL =~ ^[1-9][0-9]*$ ]] || SHARD_TOTAL=1
[[ $SHARD_INDEX =~ ^[0-9]+$ ]] || SHARD_INDEX=0
(( SHARD_INDEX < SHARD_TOTAL )) || SHARD_INDEX=0
if [[ $DRY_RUN == 0 ]]; then
  command -v gh >/dev/null || { echo "gh 未安装" >&2; exit 2; }
fi
command -v zstd >/dev/null || { echo "zstd 未安装" >&2; exit 2; }

log()  { printf '%s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*"; }

mkdir -p "$TMP_DIR" "$OUT_DIR"
printf 'repo\turl\tasset\tbytes\tsha256\tcommit\tbacked_up_at\n' > "$MANIFEST"
: > "$FAILED"

ok_count=0
fail_count=0

record_fail() {
  local name=$1 reason=$2
  printf '%s\t%s\n' "$name" "$reason" >> "$FAILED"
  log "   ❌ $name — $reason"
  fail_count=$((fail_count + 1))
}

record_manifest() {
  local repo=$1 url=$2 asset=$3 bytes=$4 sha=$5 commit=$6
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$repo" "$url" "$asset" "$bytes" "$sha" "${commit:--}" "$(date -u +%FT%TZ)" >> "$MANIFEST"
}

free_mb() { df -Pm "$WORKSPACE" | awk 'NR==2 {print $4}'; }

upload_asset() {
  local file=$1 name attempt
  name=$(basename "$file")
  if [[ $DRY_RUN == 1 ]]; then
    log "   [DRY_RUN] 跳过上传 $name"
    return 0
  fi
  for attempt in 1 2 3; do
    if gh release upload "$TAG" "$file" --clobber >/dev/null 2>upload.err; then
      return 0
    fi
    log "   ⚠️ 上传失败（第 $attempt/3 次）：$(tail -n 1 upload.err)"
    sleep $((attempt * 10))
  done
  return 1
}

delete_asset() {
  local name=$1
  if [[ $DRY_RUN == 0 ]]; then
    gh release delete-asset "$TAG" "$name" --yes >/dev/null 2>&1 || true
  fi
}

flush_staging() {
  local f
  shopt -s nullglob
  for f in "$OUT_DIR"/*; do
    if [[ -f $f ]]; then
      upload_asset "$f" || return 1
      rm -f "$f"
    fi
  done
  shopt -u nullglob
}

ensure_space() {
  local need=$1 free
  free=$(free_mb)
  if (( free >= need )); then
    return 0
  fi
  log "   ⚠️ 磁盘剩余 ${free}MB < ${need}MB，先上传暂存文件"
  flush_staging || return 1
  free=$(free_mb)
  (( free >= need ))
}

clone_repo() {
  local url=$1 dir=$2 to=$3 shallow=${4:-0} attempt t0 elapsed args=()
  args=(--mirror --quiet)
  (( shallow )) && args+=(--depth 1)
  for attempt in 1 2 3; do
    rm -rf "$dir"
    t0=$(date -u +%s)
    if timeout "$to" git clone "${args[@]}" "$url" "$dir" >clone.log 2>&1; then
      elapsed=$(( $(date -u +%s) - t0 ))
      log "   ⏱️ 克隆耗时 ${elapsed}s（超时上限 ${to}s，第 $attempt 次）"
      return 0
    fi
    elapsed=$(( $(date -u +%s) - t0 ))
    log "   ⚠️ 克隆失败（第 $attempt/3 次，耗时 ${elapsed}s，上限 ${to}s）：$(tail -n 1 clone.log)"
    sleep $((attempt * 10))
  done
  return 1
}

# 历史遗留的畸形 submodule URL（如 Magisk 的 https://github.com:topjohnwu/resetprop.git）
# 会让 git fsck 以 rc=1 报 "gitmodulesUrl: disallowed submodule url"，但对象完整性没问题。
# 只有当日志里除这类错误外没有别的内容时才放行。
fsck_benign_only() {
  local log=$1
  [[ -s $log ]] || return 1
  ! grep -qvE '^[[:space:]]*$|gitmodulesUrl: disallowed submodule url' "$log"
}

verify_mirror() {
  local dir=$1 to=$2 t0 elapsed rc=0
  t0=$(date -u +%s)
  timeout "$to" git -C "$dir" fsck --no-progress --no-dangling >fsck.log 2>&1 || rc=$?
  elapsed=$(( $(date -u +%s) - t0 ))
  if (( rc == 0 )); then
    log "   🔎 fsck 通过（${elapsed}s）"
    return 0
  fi
  if (( rc == 124 )); then
    log "   ⚠️ fsck 超时（耗时 ${elapsed}s，上限 ${to}s）"
  elif fsck_benign_only fsck.log; then
    log "   🔎 fsck 通过（仅报历史遗留的畸形 submodule URL，对象完整性正常）"
    return 0
  else
    log "   ⚠️ fsck 失败（rc=$rc）：$(tail -n 1 fsck.log)"
  fi
  return 1
}

# 预检仓库状态：404=已删/改名，451=DMCA/TOS 封禁。
# 避免对死仓库白跑 3 次克隆重试。
probe_repo() {
  local owner=$1 repo=$2 out
  if out=$(gh api "repos/$owner/$repo" --jq '[.size, (.archived|tostring), (.disabled|tostring)] | @tsv' 2>probe.err); then
    printf 'ok\t%s' "$out"
    return 0
  fi
  if grep -qi 'blocked' probe.err; then
    printf 'blocked'
  else
    printf 'missing'
  fi
  return 1
}

compress_repo() {
  local dir=$1 out=$2 size_mb=$3
  ( cd "$dir" && tar -cf - . | pv -f -s $((size_mb * 1024 * 1024)) | zstd -q -10 -T0 > "$out" )
}

parse_github_url() {
  local url=$1 owner repo
  if [[ $url =~ ^(https?://|git@)github\.com[:/]([^/]+)/(.+)$ ]]; then
    owner=${BASH_REMATCH[2]}
    repo=${BASH_REMATCH[3]}
    repo=${repo%.git}
    repo=${repo%/}
    if [[ $owner =~ ^[A-Za-z0-9._-]+$ && $repo =~ ^[A-Za-z0-9._-]+$ ]]; then
      printf '%s\t%s\n' "$owner" "$repo"
      return 0
    fi
  fi
  return 1
}

# ---------- 构建待备份清单（去重 + 过滤） ----------
items=()
declare -A seen=()
while IFS= read -r line; do
  shallow=0
  [[ $line == *'#shallow'* ]] && shallow=1
  url=${line%%#*}
  url=${url//[[:space:]]/}
  [[ -z $url ]] && continue
  if (( ONLY_SHALLOW && shallow == 0 )); then
    continue
  fi
  (( FULL_MIRROR )) && shallow=0
  if [[ -n $REPO_FILTER && $url != *"$REPO_FILTER"* ]]; then
    continue
  fi
  if ! parsed=$(parse_github_url "$url"); then
    printf '%s\t%s\n' "$url" "无效的 GitHub URL" >> "$FAILED"
    fail_count=$((fail_count + 1))
    continue
  fi
  owner=${parsed%%$'\t'*}
  repo=${parsed##*$'\t'}
  key=$(printf '%s/%s' "$owner" "$repo" | tr '[:upper:]' '[:lower:]')
  if [[ -n ${seen[$key]:-} ]]; then
    log "⏭️  跳过重复仓库：$owner/$repo"
    continue
  fi
  seen[$key]=1
  items+=("$owner"$'\t'"$repo"$'\t'"$url"$'\t'"$shallow")
  if (( LIMIT > 0 && ${#items[@]} >= LIMIT )); then
    break
  fi
done < "$LIST_FILE"

# 分片：优先用 shardmap.tsv（按体积做 LPT 均衡），没有则回退按清单顺序取模
if (( SHARD_TOTAL > 1 && ${#items[@]} > 0 )); then
  sharded=()
  if [[ -f $SHARD_MAP ]]; then
    declare -A mine=()
    while IFS=$'\t' read -r m_owner m_repo m_shard; do
      [[ -z ${m_shard:-} ]] && continue
      (( m_shard == SHARD_INDEX )) || continue
      mine["$(printf '%s/%s' "$m_owner" "$m_repo" | tr '[:upper:]' '[:lower:]')"]=1
    done < "$SHARD_MAP"
    for item in "${items[@]}"; do
      IFS=$'\t' read -r o r _u <<< "$item"
      key="$(printf '%s/%s' "$o" "$r" | tr '[:upper:]' '[:lower:]')"
      if [[ -n ${mine[$key]:-} ]]; then
        sharded+=("$item")
      fi
    done
    log "🧩 分片 ${SHARD_INDEX}/${SHARD_TOTAL}（shardmap 均衡）：本片 ${#sharded[@]} 个仓库"
  else
    for i in "${!items[@]}"; do
      (( i % SHARD_TOTAL == SHARD_INDEX )) && sharded+=("${items[$i]}")
    done
    log "🧩 分片 ${SHARD_INDEX}/${SHARD_TOTAL}（顺序取模）：本片 ${#sharded[@]} 个仓库"
  fi
  items=("${sharded[@]}")
fi

if (( ${#items[@]} == 0 )); then
  if (( SHARD_TOTAL > 1 )); then
    log "本分片没有需要处理的仓库（filter=$REPO_FILTER limit=$LIMIT）"
    exit 0
  fi
  log "❌ 没有匹配到任何仓库（filter=$REPO_FILTER limit=$LIMIT）"
  exit 2
fi

log "=============================================="
log "开始备份：${#items[@]} 个仓库 → Release $TAG"
log "=============================================="

idx=0
for item in "${items[@]}"; do
  IFS=$'\t' read -r owner repo url shallow <<< "$item"
  shallow=${shallow:-0}
  name="$owner/$repo"
  idx=$((idx + 1))
  log ""
  log "📦 [$idx/${#items[@]}] $name"
  (( shallow )) && log "   🪶 浅克隆（仅默认分支 tip，不含历史）"

  if ! ensure_space "$MIN_FREE_MB"; then
    record_fail "$name" "磁盘空间不足（<$MIN_FREE_MB MB）"
    continue
  fi

  probe=$(probe_repo "$owner" "$repo" || true)
  p_status=${probe%%$'\t'*}
  case $p_status in
    ok) ;;
    blocked)
      log "   🚫 平台封禁（HTTP 451，DMCA/TOS）"
      record_fail "$name" "平台封禁（HTTP 451）"
      continue
      ;;
    *)
      log "   ❓ 仓库不存在（HTTP 404，可能已删/改名）"
      record_fail "$name" "仓库不存在或已改名（HTTP 404）"
      continue
      ;;
  esac

  # 按预估体积放宽克隆/fsck 超时：大仓库在慢链路上 900s 明显不够
  api_kb=0
  if [[ $p_status == ok ]]; then
    IFS=$'\t' read -r _ api_kb _arch _dis <<< "$probe"
  fi
  [[ $api_kb =~ ^[0-9]+$ ]] || api_kb=0
  clone_to=$(( api_kb / 1024 * CLONE_SEC_PER_MB ))
  (( clone_to < CLONE_TIMEOUT )) && clone_to=$CLONE_TIMEOUT
  (( clone_to > CLONE_MAX_TIMEOUT )) && clone_to=$CLONE_MAX_TIMEOUT
  fsck_to=$(( api_kb / 1024 ))
  (( fsck_to < FSCK_TIMEOUT )) && fsck_to=$FSCK_TIMEOUT
  (( fsck_to > FSCK_MAX_TIMEOUT )) && fsck_to=$FSCK_MAX_TIMEOUT
  log "   ⚖️ 预估 $((api_kb / 1024))MB → 克隆超时 ${clone_to}s / fsck 超时 ${fsck_to}s"

  dir="$TMP_DIR/$owner-$repo"
  if ! clone_repo "$url" "$dir" "$clone_to" "$shallow"; then
    record_fail "$name" "克隆失败（重试 3 次）"
    rm -rf "$dir"
    continue
  fi

  if ! verify_mirror "$dir" "$fsck_to"; then
    record_fail "$name" "git fsck 失败"
    rm -rf "$dir"
    continue
  fi

  commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
  refs=$(git -C "$dir" for-each-ref | wc -l | tr -d ' ')
  size_mb=$(du -sm "$dir" | cut -f1)
  log "   ✅ 克隆完成：${size_mb}MB / refs=${refs} / HEAD=${commit:0:12}"

  # 防护：个别仓库实际 mirror 体积远超 API 预估（例如 20GB），压缩+上传会拖垮整片
  if (( size_mb > MAX_CLONE_MB )); then
    log "   ✋ 实际体积 ${size_mb}MB 超过单仓上限 ${MAX_CLONE_MB}MB，跳过"
    record_fail "$name" "mirror 体积 ${size_mb}MB 超过上限 ${MAX_CLONE_MB}MB"
    rm -rf "$dir"
    continue
  fi

  if ! ensure_space $((size_mb + 500)); then
    record_fail "$name" "压缩所需磁盘空间不足"
    rm -rf "$dir"
    continue
  fi

  base="$owner-$repo-$(date -u +%s)"
  (( shallow )) && base="$base-shallow"
  archive="$OUT_DIR/$base.tar.zst"
  if ! compress_repo "$dir" "$archive" "$size_mb"; then
    record_fail "$name" "压缩失败"
    rm -rf "$dir" "$archive"
    continue
  fi
  rm -rf "$dir"

  if ! zstd -t "$archive" >/dev/null 2>&1; then
    record_fail "$name" "压缩包完整性校验失败（zstd -t）"
    rm -f "$archive"
    continue
  fi

  bytes=$(stat -c %s "$archive")
  if (( bytes > MAX_PART_MB * 1024 * 1024 )); then
    log "   ✂️ 压缩后 $((bytes / 1048576))MB，分卷上传"
    if ! ensure_space $((bytes / 1048576 + 500)); then
      record_fail "$name" "分卷所需磁盘空间不足"
      rm -f "$archive"
      continue
    fi
    split -b "${MAX_PART_MB}M" -d -a 3 "$archive" "$archive.part"
    rm -f "$archive"
    shopt -s nullglob
    parts=("$archive.part"*)
    shopt -u nullglob
    uploaded=()
    upload_ok=1
    for p in "${parts[@]}"; do
      if upload_asset "$p"; then
        uploaded+=("$(basename "$p")")
      else
        upload_ok=0
        break
      fi
    done
    if (( upload_ok == 0 )); then
      for up in "${uploaded[@]}"; do
        delete_asset "$up"
      done
      record_fail "$name" "分卷上传失败"
      rm -f "${parts[@]}"
      continue
    fi
    for p in "${parts[@]}"; do
      pbytes=$(stat -c %s "$p")
      psha=$(sha256sum "$p" | cut -d' ' -f1)
      record_manifest "$name" "$url" "$(basename "$p")" "$pbytes" "$psha" "$commit"
      rm -f "$p"
    done
  else
    if ! upload_asset "$archive"; then
      record_fail "$name" "上传失败"
      rm -f "$archive"
      continue
    fi
    sha=$(sha256sum "$archive" | cut -d' ' -f1)
    record_manifest "$name" "$url" "$(basename "$archive")" "$bytes" "$sha" "$commit"
    rm -f "$archive"
  fi
  ok_count=$((ok_count + 1))
  log "   ✅ 完成"
done

# ---------- 上传结果核对 ----------
verify_failed=0
if [[ $DRY_RUN == 0 && -n ${GITHUB_REPOSITORY:-} ]]; then
  log ""
  log "🔍 核对 Release 资产…"
  # 草稿态的 Release 不会出现在 /releases/tags/{tag}（404），只能从列表里筛；
  # 列表本身失败时只告警，不把整次备份判失败。
  gh api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate \
    --jq ".[] | select(.tag_name == \"$TAG\") | .assets[] | [.name, (.size|tostring)] | @tsv" \
    > "$WORKSPACE/.remote_assets.tsv" 2>reconcile.err || true
  sort -o "$WORKSPACE/.remote_assets.tsv" "$WORKSPACE/.remote_assets.tsv" 2>/dev/null || true
  awk -F'\t' 'NR>1 {print $3 "\t" $4}' "$MANIFEST" | sort > "$WORKSPACE/.want_assets.tsv"
  missing=""
  if [[ -s $WORKSPACE/.remote_assets.tsv ]]; then
    missing=$(comm -23 "$WORKSPACE/.want_assets.tsv" "$WORKSPACE/.remote_assets.tsv" || true)
  else
    log "   ⚠️ 读不到 Release 资产列表，跳过核对：$(head -n 1 reconcile.err 2>/dev/null || true)"
  fi
  if [[ -n $missing ]]; then
    printf '::error::以下资产未出现在 Release 中（或大小不符）：\n%s\n' "$missing"
    verify_failed=1
  else
    log "   ✅ 全部资产已在 Release 中"
  fi
  rm -f "$WORKSPACE/.remote_assets.tsv" "$WORKSPACE/.want_assets.tsv"
fi

log ""
log "=============================================="
log "备份结束：成功 $ok_count，失败 $fail_count"
if [[ -s $FAILED ]]; then
  while IFS=$'\t' read -r fname freason; do
    log "   ❌ $fname — $freason"
  done < "$FAILED"
fi
log "=============================================="

exit "$verify_failed"
