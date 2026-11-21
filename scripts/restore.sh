#!/usr/bin/env bash
# 备份恢复工具：从 QC3284/repo-backup 的 Release 恢复 GitHub 仓库。
#
# 子命令（默认 get）：
#   get <repo>        恢复一个仓库：下载 → sha256 → 合并分卷 → zstd -t → 解压 → fsck → HEAD
#   assets <repo>     列出该仓库在某次备份里的资产（不下载）
#   list              列出某次备份包含哪些仓库（--filter 过滤）
#   history <repo>    查该仓库历次备份（扫描最近 --limit 份 manifest）
#   batch <file>      批量恢复（文件一行一个仓库，--jobs 并发，失败不中断）
#   swh <repo>        从 Software Heritage 拉取（上游已删库时用）
#   verify <archive>  校验本地压缩包（sha256 / zstd -t / --deep 解压 fsck）
#
# 公共选项：
#   -R, --source REPO   备份所在仓库（默认 QC3284/repo-backup）
#   -t, --tag TAG       指定 Release
#       --latest KIND   最新版本：any（默认）| daily | full
#       --before DATE   取 DATE（YYYY-MM-DD[THH:MM]）之前最新的版本
#       --manifest FILE 用本地 manifest，不联网
#       --json          JSON 输出（list/assets/history）
#       --dry-run       只打印计划，不下载
#       --jobs N        并发数（batch 默认 1；分卷下载也用它）
#       --filter PAT    list 的仓库过滤（大小写不敏感子串）
#       --limit N       history 扫描的 Release 数（默认 10）
#   -h, --help
#
# get/batch 选项：
#   -d, --dir DIR       工作目录（默认 ./restore-<owner>-<repo>）
#   -o, --out DIR       裸仓库输出（默认 <dir>/repo.git）
#       --clone DIR     恢复后 clone 工作副本
#   -b, --branch NAME   clone 时检出分支/标签
#       --from-dir DIR  离线：从本地目录读 manifest 与资产
#       --download-only 只下载+校验，不解压
#       --keep          保留压缩包
#
# swh 选项：--snapshot ID、--timeout SEC（cooking 最长等待，默认 1800）
# verify 选项：--deep（解压后 fsck）、--manifest FILE（按资产名核对 sha256）
#
# 依赖：git、zstd、sha256sum/shasum；联网子命令需要 gh；swh 需要 curl + jq（或 python3）。
set -Eeuo pipefail
export LC_ALL=C

VERSION=2.0.0
SOURCE=QC3284/repo-backup
TAG=''
LATEST=any
BEFORE=''
REPO=''
WORK=''
OUT=''
CLONE=''
BRANCH=''
FROM_DIR=''
MANIFEST_FILE=''
DOWNLOAD_ONLY=0
KEEP=0
JSON=0
DRY_RUN=0
JOBS=1
LIMIT=10
FILTER=''
SNAPSHOT=''
TIMEOUT=1800
DEEP=0
CMD=''
POSITIONAL=()
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

RED=$'\x1b[31m'; GREEN=$'\x1b[32m'; CYAN=$'\x1b[36m'; YELLOW=$'\x1b[33m'; DIM=$'\x1b[2m'; RESET=$'\x1b[0m'
DIE_CODE=1
die() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit "${DIE_CODE:-1}"; }
die_verify() { DIE_CODE=2; die "$@"; }
info() { if (( JSON )); then printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET" >&2; else printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET"; fi; }
ok() { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s! %s%s\n' "$YELLOW" "$*" "$RESET"; }
dim() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }

usage() {
  cat <<'USAGE'
备份恢复工具：从 QC3284/repo-backup 的 Release 恢复 GitHub 仓库。

用法：
  scripts/restore.sh <owner/repo> [get 选项]        # 默认子命令 get
  scripts/restore.sh list [--filter PAT] [--json]
  scripts/restore.sh assets <owner/repo> [--json]
  scripts/restore.sh history <owner/repo> [--limit N] [--json]
  scripts/restore.sh batch repos.txt [--jobs 3]
  scripts/restore.sh swh <owner/repo> [--snapshot ID] [--timeout 1800]
  scripts/restore.sh verify file.tar.zst [--deep] [--manifest FILE]

通用：-R/--source、-t/--tag、--latest any|daily|full、--before DATE、
      --manifest FILE、--json、--dry-run、--jobs N、--filter PAT、--limit N
get ：-d/--dir、-o/--out、--clone DIR、-b/--branch、--from-dir、--download-only、--keep
swh ：--snapshot、--timeout
详细说明见 恢复教程.md。
USAGE
  exit 0
}

while (( $# )); do
  case $1 in
    get|list|assets|history|batch|swh|verify)
      if [[ -z $CMD ]]; then CMD=$1; shift; continue; fi ;;
  esac
  case $1 in
    -R|--source) SOURCE=$2; shift 2 ;;
    -t|--tag) TAG=$2; shift 2 ;;
    --latest) LATEST=$2; shift 2 ;;
    --before) BEFORE=$2; shift 2 ;;
    --manifest) MANIFEST_FILE=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --jobs|-j) JOBS=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --filter) FILTER=$2; shift 2 ;;
    -d|--dir) WORK=$2; shift 2 ;;
    -o|--out) OUT=$2; shift 2 ;;
    --clone) CLONE=$2; shift 2 ;;
    -b|--branch) BRANCH=$2; shift 2 ;;
    --from-dir) FROM_DIR=$2; shift 2 ;;
    --download-only) DOWNLOAD_ONLY=1; shift ;;
    --keep) KEEP=1; shift ;;
    --snapshot) SNAPSHOT=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --deep) DEEP=1; shift ;;
    -h|--help) usage ;;
    -V|--version) printf 'restore.sh %s\n' "$VERSION"; exit 0 ;;
    --) shift; POSITIONAL+=("$@"); break ;;
    -*) die "未知选项：$1（-h 查看用法）" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
CMD=${CMD:-get}

case $LATEST in any|daily|backup|full) ;; *) die "--latest 只能是 any、daily 或 full" ;; esac
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || die "--jobs 必须是正整数"
[[ $LIMIT =~ ^[1-9][0-9]*$ ]] || die "--limit 必须是正整数"

for bin in git zstd; do
  command -v "$bin" >/dev/null || die "缺少 $bin，请先安装（见 恢复教程.md 的「准备工具」）"
done
SHA_BIN=$(command -v sha256sum || command -v shasum || true)
[[ -n $SHA_BIN ]] || die "缺少 sha256sum / shasum"

sha256_of() {
  if [[ $SHA_BIN == *sha256sum ]]; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fsck_benign_only() {
  local log=$1
  [[ -s $log ]] || return 1
  ! grep -qvE '^[[:space:]]*$|gitmodulesUrl: disallowed submodule url' "$log"
}

normalize_repo() {
  local s=$1
  s=${s%.git}
  s=${s#https://github.com/}
  s=${s#http://github.com/}
  s=${s#git@github.com:}
  s=${s#ssh://git@github.com/}
  s=${s%/}
  [[ $s =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || die "仓库格式无法识别：$1（支持 owner/repo、https://github.com/owner/repo、git@github.com:owner/repo.git）"
  printf '%s' "$s"
}

# tag -> 14 位可排序键：backup-20261121115821 -> 20261121115821；full-20261121 -> 20261121030000
tag_key() {
  local t=$1 d=''
  case $t in
    backup-*) d=${t#backup-} ;;
    full-*) d=${t#full-} ;;
  esac
  if [[ ! $d =~ ^[0-9]{14}$ ]]; then
    if [[ $d =~ ^[0-9]{8}$ ]]; then d=${d}030000; else d=0; fi
  fi
  printf '%s' "$d"
}

date_key() {
  local s=$1
  s=${s//-/}; s=${s//:/}; s=${s//T/}; s=${s// /}
  case ${#s} in
    8) s=${s}000000 ;;
    10) s=${s}0000 ;;
    12) s=${s}00 ;;
    14) ;;
    *) die "时间格式要 YYYY-MM-DD 或 YYYY-MM-DDTHH:MM：$1" ;;
  esac
  [[ $s =~ ^[0-9]{14}$ ]] || die "时间格式无法解析：$1"
  printf '%s' "$s"
}

fmt_tag_time() {
  local k=$1
  printf '%s-%s-%s %s:%s' "${k:0:4}" "${k:4:2}" "${k:6:2}" "${k:8:2}" "${k:10:2}"
}

ensure_gh() {
  command -v gh >/dev/null || die "缺少 gh（GitHub CLI）。离线恢复请用 --from-dir / --manifest。"
}

list_release_tags() {
  ensure_gh
  gh release list -R "$SOURCE" -L 100 --json tagName,isDraft \
    --jq '.[] | select(.isDraft | not) | .tagName'
}

pick_tag() {
  if [[ -n $TAG ]]; then printf '%s' "$TAG"; return; fi
  local t k best='' bestk=0 beforek=''
  local -a tags=()
  mapfile -t tags < <(list_release_tags)
  (( ${#tags[@]} )) || die "读不到 $SOURCE 的 Release 列表（检查 gh auth status）"
  if [[ -n $BEFORE ]]; then beforek=$(date_key "$BEFORE"); fi
  for t in "${tags[@]}"; do
    case $LATEST in
      daily|backup) [[ $t == backup-* ]] || continue ;;
      full) [[ $t == full-* ]] || continue ;;
    esac
    k=$(tag_key "$t")
    [[ $k != 0 ]] || continue
    if [[ -n $beforek ]] && [[ $k > $beforek ]]; then continue; fi
    if (( k > bestk )); then bestk=$k; best=$t; fi
  done
  local cond="--latest $LATEST"
  [[ -n $BEFORE ]] && cond="$cond --before $BEFORE"
  [[ -n $best ]] || die "没有符合条件的 Release（$cond）；用 $SELF list -t <TAG> 看现有版本"
  printf '%s' "$best"
}

resolve_manifest() {
  mkdir -p "$WORK"
  if [[ -n $MANIFEST_FILE ]]; then
    [[ -f $MANIFEST_FILE ]] || die "manifest 不存在：$MANIFEST_FILE"
    MANIFEST=$MANIFEST_FILE
    info "使用本地 manifest：$MANIFEST"
    return
  fi
  if [[ -n $FROM_DIR ]]; then
    [[ -d $FROM_DIR ]] || die "离线目录不存在：$FROM_DIR"
    MANIFEST=$(find "$FROM_DIR" -maxdepth 1 -name 'manifest-*.tsv' | sort | tail -n 1)
    [[ -n $MANIFEST ]] || die "离线目录里没有 manifest-*.tsv：$FROM_DIR"
    info "离线模式：$MANIFEST"
    return
  fi
  ensure_gh
  if [[ -z $TAG ]]; then TAG=$(pick_tag); fi
  info "Release：$TAG（$SOURCE）"
  gh release download "$TAG" -R "$SOURCE" --pattern "manifest-$TAG.tsv" --dir "$WORK" --clobber >/dev/null \
    || die "下载 manifest-$TAG.tsv 失败"
  MANIFEST="$WORK/manifest-$TAG.tsv"
}

rows_for() {
  awk -F'\t' -v r="$1" 'NR > 1 && $1 == r { print }' "$MANIFEST"
}

# ---------- get ----------
cmd_get() {
  REPO=$(normalize_repo "${POSITIONAL[0]:-}")
  [[ -n $REPO ]] || die "缺少仓库参数，例如：scripts/restore.sh MetaCubeX/mihomo"
  OWNER=${REPO%%/*}; NAME=${REPO#*/}
  WORK=${WORK:-./restore-${OWNER}-${NAME}}
  OUT=${OUT:-$WORK/repo.git}
  mkdir -p "$WORK"
  resolve_manifest

  ROWS=$(rows_for "$REPO")
  if [[ -z $ROWS ]]; then
    die "该 Release 里没有 $REPO 的备份。
  可能原因：新增仓库、当天失败、或名字写错。
  → 查历史：$SELF history $REPO
  → 看这版有什么：$SELF list -t $TAG --filter $NAME"
  fi

  COMMIT=$(printf '%s\n' "$ROWS" | awk -F'\t' 'NR==1{print $6}')
  TOTAL_BYTES=$(printf '%s\n' "$ROWS" | awk -F'\t' '{s+=$4} END{print s+0}')
  PARTS=$(printf '%s\n' "$ROWS" | awk -F'\t' '$3 ~ /\.part[0-9]+$/ {print $3}' | sort)
  COUNT=$(printf '%s\n' "$ROWS" | awk 'END{print NR}')

  info "仓库：$REPO  资产：$COUNT 个  合计 $((TOTAL_BYTES / 1048576)) MB  源 HEAD：${COMMIT:0:12}"

  if (( DRY_RUN )); then
    printf '%s\n' "$ROWS" | awk -F'\t' '{printf "  %-58s %8.1f MB  sha256=%s\n", $3, $4/1048576, substr($5,1,16)}'
    dim "（--dry-run：未下载）"
    return
  fi

  local need_mb avail_mb
  need_mb=$(( TOTAL_BYTES / 1048576 * 2 + 200 ))
  avail_mb=$(df -Pm "$WORK" | awk 'NR==2{print $4}')
  if (( avail_mb < need_mb )); then
    die "磁盘空间不足：需要约 ${need_mb}MB，$WORK 所在分区只剩 ${avail_mb}MB"
  fi

  download_one() {
    local asset=$1
    if [[ -n $FROM_DIR ]]; then
      [[ -f "$FROM_DIR/$asset" ]] && cp -f "$FROM_DIR/$asset" "$WORK/$asset" && return 0
      return 1
    fi
    [[ -f "$WORK/$asset" ]] && return 0
    gh release download "$TAG" -R "$SOURCE" --pattern "$asset" --dir "$WORK" >/dev/null 2>&1
  }

  verify_one() {
    local asset=$1 want actual
    want=$(printf '%s\n' "$ROWS" | awk -F'\t' -v a="$asset" '$3 == a {print $5; exit}')
    actual=$(sha256_of "$WORK/$asset")
    [[ $actual == "$want" ]] || die_verify "sha256 不匹配：$asset
  期望 $want
  实际 $actual
  → 重新下载；若反复不一致，换一个更早的 Release。"
    ok "sha256 匹配：$asset"
  }

  local archive=''
  if [[ -n $PARTS ]]; then
    archive=$(printf '%s\n' "$PARTS" | head -n 1)
    archive=${archive%.part[0-9][0-9][0-9]}
    info "分卷资产 $COUNT 个，合并为：$(basename "$archive")"
    local -a plist=()
    mapfile -t plist < <(printf '%s\n' "$PARTS")
    if (( JOBS > 1 && ${#plist[@]} > 1 )); then
      printf '%s\n' "${plist[@]}" | xargs -P "$JOBS" -I{} bash -c '
        WORK=$1; FROM_DIR=$2; TAG=$3; SOURCE=$4; a=$5
        if [[ -n $FROM_DIR ]]; then cp -f "$FROM_DIR/$a" "$WORK/$a"
        elif [[ ! -f "$WORK/$a" ]]; then gh release download "$TAG" -R "$SOURCE" --pattern "$a" --dir "$WORK" >/dev/null 2>&1; fi
      ' _ "$WORK" "$FROM_DIR" "$TAG" "$SOURCE" {} || die "分卷并发下载失败"
    else
      for p in "${plist[@]}"; do
        download_one "$p" || die "下载失败：$p"
      done
    fi
    for p in "${plist[@]}"; do verify_one "$p"; done
    rm -f "$WORK/$archive"
    local -a paths=()
    for p in "${plist[@]}"; do paths+=("$WORK/$p"); done
    cat "${paths[@]}" > "$WORK/$archive"
    ok "分卷合并完成：$(basename "$archive")"
    archive="$WORK/$(basename "$archive")"
  else
    archive=$(printf '%s\n' "$ROWS" | awk -F'\t' 'NR==1{print $3}')
    download_one "$archive" || die "下载失败：$archive"
    verify_one "$archive"
    archive="$WORK/$archive"
  fi

  [[ -s $archive ]] || die_verify "压缩包为空：$archive"

  info "zstd 完整性校验…"
  zstd -t "$archive" >/dev/null 2>&1 || die_verify "zstd -t 失败：压缩包损坏（分卷顺序错了或下载不完整）"
  ok "zstd 完整性通过"

  if (( DOWNLOAD_ONLY )); then
    ok "已下载并通过校验：$archive"
    return
  fi

  if [[ -e $OUT && -n "$(ls -A "$OUT" 2>/dev/null || true)" ]]; then
    die "输出目录非空：$OUT（换个 -o，或先手动清空）"
  fi
  mkdir -p "$OUT"
  info "解压到 $OUT …"
  zstd -dc "$archive" | tar -xf - -C "$OUT" || die_verify "解压失败"
  if (( ! KEEP )); then rm -f "$archive"; fi
  ok "解压完成"

  [[ -f "$OUT/HEAD" || -d "$OUT/objects" ]] || die_verify "$OUT 不像裸仓库（缺 HEAD/objects）"

  info "git fsck …"
  local fsck_rc=0
  git --git-dir="$OUT" fsck --no-progress --no-dangling >"$WORK/fsck.log" 2>&1 || fsck_rc=$?
  if (( fsck_rc != 0 )); then
    if fsck_benign_only "$WORK/fsck.log"; then
      warn "fsck 只报了历史遗留的畸形 submodule URL（对象完整性正常）"
    else
      tail -n 10 "$WORK/fsck.log" >&2
      die_verify "git fsck 失败：仓库对象损坏。重下/重解压；仍失败就换更早的 Release。"
    fi
  fi
  ok "git fsck 通过"

  if [[ -n $COMMIT && $COMMIT != '-' ]]; then
    local head
    head=$(git --git-dir="$OUT" rev-parse HEAD 2>/dev/null || true)
    if [[ -n $head ]]; then
      [[ $head == "$COMMIT" ]] || die_verify "HEAD 不匹配：manifest 记录 $COMMIT，实际 $head"
      ok "HEAD 与 manifest 一致（${COMMIT:0:12}）"
    else
      warn "该仓库没有默认 HEAD（空仓库或只有标签），跳过比对"
    fi
  fi

  local refs branches tags
  refs=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')
  branches=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' 'refs/heads/*' | wc -l | tr -d ' ')
  tags=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' 'refs/tags/*' | wc -l | tr -d ' ')
  ok "裸仓库就绪：$OUT（$refs 个引用：$branches 分支 / $tags 标签）"

  if [[ $(basename "$archive") == *-shallow.tar.zst ]]; then
    warn "浅克隆备份：只有默认分支 tip，没有历史。
  要历史：$SELF get $REPO --latest full（full-* 里的同名资产）或 $SELF swh $REPO"
  fi

  if [[ -n $CLONE ]]; then
    if [[ -e $CLONE && -n "$(ls -A "$CLONE" 2>/dev/null || true)" ]]; then die "clone 目标非空：$CLONE"; fi
    info "克隆工作副本到 $CLONE …"
    git -c safe.directory='*' clone --quiet "$OUT" "$CLONE" || die "git clone 失败"
    if [[ -n $BRANCH ]]; then
      git -C "$CLONE" checkout --quiet "$BRANCH" || die "检出 $BRANCH 失败"
    fi
    ok "工作副本：$CLONE（$(git -C "$CLONE" rev-parse --short HEAD)）"
  fi

  echo ""
  ok "恢复完成：$OUT"
  echo "下一步："
  echo "  git --git-dir=$OUT log --oneline -5"
  echo "  git clone $OUT my-workdir"
  echo "  git -C my-workdir remote add origin <URL>"
  echo "  git -C my-workdir push origin --all && git -C my-workdir push origin --tags"
}

# ---------- assets ----------
cmd_assets() {
  REPO=$(normalize_repo "${POSITIONAL[0]:-}")
  WORK=${WORK:-./.restore-cache}
  resolve_manifest
  local rows; rows=$(rows_for "$REPO")
  [[ -n $rows ]] || die "该 Release 里没有 $REPO（试试：$SELF history $REPO）"
  if (( JSON )); then
    printf '%s\n' "$rows" | awk -F'\t' 'BEGIN{printf "["} {printf "%s{\"asset\":\"%s\",\"bytes\":%s,\"sha256\":\"%s\",\"commit\":\"%s\",\"backed_up_at\":\"%s\"}", (NR>1?",":""), $3,$4,$5,$6,$7} END{print "]"}'
    return
  fi
  printf '%s\n' "$rows" | awk -F'\t' '{printf "  %-58s %8.1f MB  sha256=%s\n", $3, $4/1048576, substr($5,1,16)}'
}

# ---------- list ----------
cmd_list() {
  WORK=${WORK:-./.restore-cache}
  resolve_manifest
  local n
  n=$(awk -F'\t' -v f="$FILTER" 'NR>1 { if (f=="" || index(tolower($1),tolower(f))>0) c++ } END{print c+0}' "$MANIFEST")
  if (( JSON )); then
    awk -F'\t' -v f="$FILTER" '
      NR>1 { r=$1; if (f != "" && index(tolower(r), tolower(f)) == 0) next; n[r]++; b[r]+=$4 }
      END { printf "["; sep=""
            for (r in n) { printf "%s{\"repo\":\"%s\",\"assets\":%d,\"bytes\":%d}", sep, r, n[r], b[r]; sep="," }
            print "]" }' "$MANIFEST"
    return
  fi
  info "Release $TAG：${n} 个仓库${FILTER:+（过滤：$FILTER）}"
  awk -F'\t' -v f="$FILTER" '
    NR>1 { r=$1; if (f != "" && index(tolower(r), tolower(f)) == 0) next; n[r]++; b[r]+=$4 }
    END { for (r in n) printf "  %-48s %4d 个资产  %8.1f MB\n", r, n[r], b[r]/1048576 }' "$MANIFEST" | sort
}

# ---------- history ----------
cmd_history() {
  REPO=$(normalize_repo "${POSITIONAL[0]:-}")
  WORK=${WORK:-./.restore-cache}
  mkdir -p "$WORK"
  local -a tags=()
  local t
  if [[ -n $TAG ]]; then tags=("$TAG"); else
    ensure_gh
    mapfile -t tags < <(list_release_tags)
    if [[ -n $BEFORE ]]; then
      local bk k; bk=$(date_key "$BEFORE")
      local -a keep=()
      for t in "${tags[@]}"; do
        k=$(tag_key "$t")
        if (( k != 0 && k <= bk )); then keep+=("$t"); fi
      done
      tags=()
      if (( ${#keep[@]} )); then tags=("${keep[@]}"); fi
    fi
    if (( ${#tags[@]} > LIMIT )); then tags=("${tags[@]:0:$LIMIT}"); fi
  fi
  (( ${#tags[@]} )) || die "没有可查的 Release"
  local first=1 found=0
  if (( JSON )); then printf '['; fi
  for t in "${tags[@]}"; do
    case $LATEST in
      daily|backup) [[ $t == backup-* ]] || continue ;;
      full) [[ $t == full-* ]] || continue ;;
    esac
    local mf="$WORK/manifest-$t.tsv"
    if [[ ! -f $mf ]]; then
      gh release download "$t" -R "$SOURCE" --pattern "manifest-$t.tsv" --dir "$WORK" --clobber >/dev/null 2>&1 || continue
    fi
    local cnt; cnt=$(awk -F'\t' -v r="$REPO" 'NR>1 && $1==r {c++} END{print c+0}' "$mf")
    [[ $cnt -gt 0 ]] || continue
    found=1
    local k ts asset bytes commit shallow=false
    k=$(tag_key "$t"); ts=$(fmt_tag_time "$k")
    asset=$(awk -F'\t' -v r="$REPO" 'NR>1 && $1==r {print $3; exit}' "$mf")
    bytes=$(awk -F'\t' -v r="$REPO" 'NR>1 && $1==r {s+=$4} END{print s+0}' "$mf")
    commit=$(awk -F'\t' -v r="$REPO" 'NR>1 && $1==r {print $6; exit}' "$mf")
    [[ $asset == *-shallow.tar.zst ]] && shallow=true
    if (( JSON )); then
      if (( first )); then first=0; else printf ','; fi
      printf '{"tag":"%s","time":"%s","assets":%d,"bytes":%d,"commit":"%s","shallow":%s}' "$t" "$ts" "$cnt" "$bytes" "$commit" "$shallow"
    else
      printf '  %-26s %s  %4s 个资产 %9.1f MB  %s%s\n' "$t" "$ts" "$cnt" \
        "$(awk -v b="$bytes" 'BEGIN{print b/1048576}')" "${commit:0:12}" "$([[ $shallow == true ]] && echo '  (shallow)')"
    fi
  done
  if (( JSON )); then printf ']\n'; fi
  (( found )) || die "$REPO 在最近 ${#tags[@]} 份 Release 里都没有记录"
}

# ---------- swh ----------
latest_snapshot() {
  if command -v jq >/dev/null; then
    jq -r '[.[] | select(.snapshot != null)][0].snapshot // empty'
  else
    python3 -c 'import json,sys
for v in json.load(sys.stdin):
    if v.get("snapshot"):
        print(v["snapshot"]); break'
  fi
}

json_get() {
  local expr=$1
  if command -v jq >/dev/null; then jq -r "$expr"
  else python3 -c 'import json,sys
d=json.load(sys.stdin)
for part in sys.argv[1].split("."):
    if not part: continue
    if part.endswith("]"):
        name, idx = part[:-1].split("[")
        if name: d = d[name]
        d = d[int(idx)]
    else:
        d = d[part]
print(d if d is not None else "")' "$expr"; fi
}

cmd_swh() {
  REPO=$(normalize_repo "${POSITIONAL[0]:-}")
  WORK=${WORK:-./restore-${REPO//\//-}}
  OUT=${OUT:-$WORK/repo.git}
  mkdir -p "$WORK"
  local UA='repo-backup/1.0 (+https://github.com/QC3284/repo-backup)'
  command -v curl >/dev/null || die "缺少 curl"

  if [[ -z $SNAPSHOT ]]; then
    local enc=${REPO//\//%2F} json
    info "查询 SWH origin：$REPO"
    json=$(curl -fsS -A "$UA" "https://archive.softwareheritage.org/api/1/origin/https%3A%2F%2Fgithub.com%2F${enc}/visits/?limit=100") \
      || die "查询失败（SWH 限流 120 次/小时，稍后再试）"
    SNAPSHOT=$(printf '%s' "$json" | latest_snapshot 2>/dev/null || true)
    [[ -n $SNAPSHOT ]] || die "SWH 没有 $REPO 的快照（从未抓取或已移除）。已知 snapshot id 时可用 --snapshot 直接指定。"
  fi
  info "SWH snapshot：$SNAPSHOT"

  local base="https://archive.softwareheritage.org/api/1/vault/git-bare/swh:1:snp:$SNAPSHOT" st
  st=$(curl -fsS -A "$UA" -X POST "$base/" | json_get '.status' 2>/dev/null || true)
  [[ -n $st ]] || st=$(curl -fsS -A "$UA" "$base/" | json_get '.status') || die "请求 SWH 打包失败"
  info "cooking 状态：$st"
  local waited=0
  while [[ $st != "done" ]]; do
    if (( waited >= TIMEOUT )); then die "等待超时（${TIMEOUT}s）：cooking 还在排队，稍后重跑本命令即可"; fi
    sleep 15; waited=$(( waited + 15 ))
    st=$(curl -fsS -A "$UA" "$base/" | json_get '.status') || die "查询 cooking 状态失败"
    dim "  … $st（已等 ${waited}s）"
  done

  local tar="$WORK/swh-$SNAPSHOT.tar"
  info "下载 SWH bundle…"
  curl -fsSL -A "$UA" -o "$tar" "$base/raw/" || die "下载 bundle 失败"
  ok "已下载：$tar（$(du -h "$tar" | cut -f1)）"
  if (( DRY_RUN )); then dim "（--dry-run：未解压）"; return; fi

  local tmp="$WORK/swh-extract" src
  rm -rf "$tmp"; mkdir -p "$tmp"
  tar -xf "$tar" -C "$tmp" || die "解包失败"
  src=$(find "$tmp" -maxdepth 1 -type d -name '*.git' | head -n 1)
  [[ -n $src ]] || die "bundle 里没有 *.git 目录"
  if [[ -e $OUT && -n "$(ls -A "$OUT" 2>/dev/null || true)" ]]; then die "输出目录非空：$OUT"; fi
  rm -rf "$OUT"; mv "$src" "$OUT"
  rm -rf "$tmp"; if (( ! KEEP )); then rm -f "$tar"; fi
  ok "裸仓库就绪：$OUT"

  local fsck_rc=0
  git --git-dir="$OUT" fsck --no-progress --no-dangling >"$WORK/fsck.log" 2>&1 || fsck_rc=$?
  if (( fsck_rc != 0 )); then
    fsck_benign_only "$WORK/fsck.log" || { tail -n 10 "$WORK/fsck.log" >&2; die_verify "SWH 镜像 git fsck 失败"; }
    warn "fsck 只有畸形 submodule URL 警告，可忽略"
  fi
  ok "git fsck 通过"
  local head; head=$(git --git-dir="$OUT" rev-parse HEAD 2>/dev/null || true)
  if [[ -n $head ]]; then ok "HEAD：$head（SWH 快照时间点，未必是上游最新）"; fi

  if [[ -n $CLONE ]]; then
    if [[ -e $CLONE && -n "$(ls -A "$CLONE" 2>/dev/null || true)" ]]; then die "clone 目标非空：$CLONE"; fi
    git clone --quiet "$OUT" "$CLONE" || die "git clone 失败"
    if [[ -n $BRANCH ]]; then git -C "$CLONE" checkout --quiet "$BRANCH"; fi
    ok "工作副本：$CLONE"
  fi
}

# ---------- verify ----------
cmd_verify() {
  local f=${POSITIONAL[0]:-}
  [[ -n $f ]] || die "用法：$SELF verify <archive.tar.zst> [--manifest FILE] [--deep]"
  [[ -f $f ]] || die "文件不存在：$f"
  local want=''
  if [[ -n $MANIFEST_FILE ]]; then
    want=$(awk -F'\t' -v a="$(basename "$f")" 'NR>1 && $3==a {print $5; exit}' "$MANIFEST_FILE")
    [[ -n $want ]] || die "manifest 里没有 $(basename "$f")"
  fi
  if [[ -n $want ]]; then
    local actual; actual=$(sha256_of "$f")
    [[ $actual == "$want" ]] || die_verify "sha256 不匹配：期望 $want，实际 $actual"
    ok "sha256 匹配"
  fi
  info "zstd -t …"
  zstd -t "$f" >/dev/null 2>&1 || die_verify "zstd -t 失败：文件损坏"
  ok "zstd 完整性通过"
  if (( DEEP )); then
    local tmp; tmp=$(mktemp -d)
    zstd -dc "$f" | tar -xf - -C "$tmp" || { rm -rf "$tmp"; die_verify "解压失败"; }
    [[ -f "$tmp/HEAD" ]] || { rm -rf "$tmp"; die_verify "解压结果不是裸仓库"; }
    local rc=0
    git --git-dir="$tmp" fsck --no-progress --no-dangling >"$tmp/fsck.log" 2>&1 || rc=$?
    if (( rc != 0 )); then
      fsck_benign_only "$tmp/fsck.log" || { tail -n 5 "$tmp/fsck.log" >&2; rm -rf "$tmp"; die_verify "fsck 失败"; }
    fi
    ok "深度校验通过（fsck）"
    rm -rf "$tmp"
  fi
}

# ---------- batch ----------
cmd_batch() {
  local file=${POSITIONAL[0]:-}
  local -a repos=()
  local line
  if [[ -n $file ]]; then
    [[ -f $file ]] || die "清单文件不存在：$file"
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%%#*}
      line=$(printf '%s' "$line" | xargs -r)
      [[ -n $line ]] && repos+=("$line")
    done < "$file"
  else
    repos=("${POSITIONAL[@]}")
  fi
  (( ${#repos[@]} )) || die "没有要恢复的仓库：给清单文件，或直接列 owner/repo"

  local base=${WORK:-./restore-batch}
  mkdir -p "$base"
  info "批量恢复 ${#repos[@]} 个仓库，并发 $JOBS，目录 $base"
  local -a chunk=()
  local r rn safe log p failed=0 i=0
  for r in "${repos[@]}"; do
    rn=$(normalize_repo "$r")
    safe=${rn//\//-}; log="$base/$safe.log"
    (
      local -a args=(get "$rn" -R "$SOURCE" -d "$base/$safe")
      if [[ -n $TAG ]]; then args+=(-t "$TAG"); fi
      if [[ -n $FROM_DIR ]]; then args+=(--from-dir "$FROM_DIR"); fi
      if [[ -n $CLONE ]]; then args+=(--clone "$base/$safe-work"); fi
      if [[ -n $BRANCH ]]; then args+=(-b "$BRANCH"); fi
      bash "$SELF" "${args[@]}" >"$log" 2>&1
    ) &
    chunk+=($!)
    i=$(( i + 1 ))
    dim "  [$i/${#repos[@]}] 已启动 $r"
    if (( ${#chunk[@]} >= JOBS )); then
      for p in "${chunk[@]}"; do wait "$p" || failed=$(( failed + 1 )); done
      chunk=()
    fi
  done
  for p in "${chunk[@]:-}"; do if [[ -n ${p:-} ]]; then wait "$p" || failed=$(( failed + 1 )); fi; done

  echo ""
  for r in "${repos[@]}"; do
    rn=$(normalize_repo "$r"); safe=${rn//\//-}
    if grep -q '恢复完成' "$base/$safe.log" 2>/dev/null; then ok "$rn"; else warn "$rn 失败（日志：$base/$safe.log）"; fi
  done
  (( failed == 0 )) || die "$failed 个仓库恢复失败"
  ok "批量恢复完成：${#repos[@]} 个仓库"
}

case $CMD in
  get) cmd_get ;;
  assets) cmd_assets ;;
  list) cmd_list ;;
  history) cmd_history ;;
  swh) cmd_swh ;;
  verify) cmd_verify ;;
  batch) cmd_batch ;;
  *) die "未知子命令：$CMD" ;;
esac
