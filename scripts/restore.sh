#!/usr/bin/env bash
# 从本仓库的 Release 里恢复一个仓库的完整镜像。
#
# 自动完成：定位 Release → 下载 manifest → 找到该仓库的资产（含分卷）→
#           逐个校验 sha256 → 合并分卷 → zstd -t → 解压 → git fsck → HEAD 比对 → 可选 clone。
#
# 用法：
#   scripts/restore.sh <owner/repo> [选项]
#
# 选项：
#   -R, --source REPO     备份所在仓库（默认 QC3284/repo-backup）
#   -t, --tag TAG         指定 Release（默认最新非草稿）
#   -d, --dir DIR         下载/工作目录（默认 ./restore-<owner>-<repo>）
#   -o, --out DIR         裸仓库输出目录（默认 <dir>/repo.git）
#       --clone DIR       恢复后克隆一份工作副本到 DIR
#   -b, --branch NAME     clone 时检出的分支/标签（默认 HEAD）
#       --from-dir DIR    离线模式：从本地目录读取 manifest-*.tsv 与资产
#       --download-only   只下载并校验，不解压
#       --keep            保留压缩包（默认解压后删除）
#       --list            只列出该 Release 里该仓库的资产
#   -h, --help
#
# 依赖：gh、git、zstd、sha256sum（macOS 用 shasum -a 256）
set -Eeuo pipefail
export LC_ALL=C

SOURCE=QC3284/repo-backup
TAG=''
REPO=''
WORK=''
OUT=''
CLONE=''
BRANCH=''
FROM_DIR=''
DOWNLOAD_ONLY=0
KEEP=0
LIST_ONLY=0

RED=$'\x1b[31m'; GREEN=$'\x1b[32m'; CYAN=$'\x1b[36m'; YELLOW=$'\x1b[33m'; RESET=$'\x1b[0m'
die() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
info() { printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET"; }
ok() { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s! %s%s\n' "$YELLOW" "$*" "$RESET"; }

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (( $# )); do
  case $1 in
    -R|--source) SOURCE=$2; shift 2 ;;
    -t|--tag) TAG=$2; shift 2 ;;
    -d|--dir) WORK=$2; shift 2 ;;
    -o|--out) OUT=$2; shift 2 ;;
    --clone) CLONE=$2; shift 2 ;;
    -b|--branch) BRANCH=$2; shift 2 ;;
    --from-dir) FROM_DIR=$2; shift 2 ;;
    --download-only) DOWNLOAD_ONLY=1; shift ;;
    --keep) KEEP=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) usage ;;
    -*) die "未知选项：$1（-h 查看用法）" ;;
    *) REPO=$1; shift ;;
  esac
done

[[ -n $REPO ]] || die "缺少仓库参数，例如：scripts/restore.sh MetaCubeX/mihomo"
[[ $REPO == */* ]] || die "仓库要写成 owner/repo，例如 MetaCubeX/mihomo"
[[ $REPO != */*/* ]] || die "仓库格式不对：$REPO"

OWNER=${REPO%%/*}
NAME=${REPO#*/}
WORK=${WORK:-./restore-${OWNER}-${NAME}}
OUT=${OUT:-$WORK/repo.git}

for bin in git zstd; do
  command -v "$bin" >/dev/null || die "缺少 $bin，请先安装（见 恢复教程.md 的「准备工具」）"
done
SHA_BIN=$(command -v sha256sum || command -v shasum || true)
[[ -n $SHA_BIN ]] || die "缺少 sha256sum / shasum"

sha256_of() {
  if [[ $SHA_BIN == *sha256sum ]]; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 历史遗留的畸形 submodule URL 会让 fsck 报错但对象完整（同 backup.sh / verify.sh）
fsck_benign_only() {
  local log=$1
  [[ -s $log ]] || return 1
  ! grep -qvE '^[[:space:]]*$|gitmodulesUrl: disallowed submodule url' "$log"
}

mkdir -p "$WORK"
MANIFEST=''

if [[ -n $FROM_DIR ]]; then
  [[ -d $FROM_DIR ]] || die "离线目录不存在：$FROM_DIR"
  MANIFEST=$(find "$FROM_DIR" -maxdepth 1 -name 'manifest-*.tsv' | sort | tail -n 1)
  [[ -n $MANIFEST ]] || die "离线目录里没有 manifest-*.tsv"
  info "离线模式：$MANIFEST"
else
  command -v gh >/dev/null || die "缺少 gh（GitHub CLI），或改用 --from-dir 离线恢复"
  if [[ -z $TAG ]]; then
    TAG=$(gh release list -R "$SOURCE" -L 50 --json tagName,isDraft \
      --jq '[.[] | select(.isDraft | not)][0].tagName' 2>/dev/null || true)
    [[ -n $TAG && $TAG != null ]] || die "读不到 $SOURCE 的 Release 列表（检查 gh auth status）"
  fi
  info "Release：$TAG（$SOURCE）"
  gh release download "$TAG" -R "$SOURCE" --pattern "manifest-$TAG.tsv" --dir "$WORK" --clobber >/dev/null \
    || die "下载 manifest-$TAG.tsv 失败"
  MANIFEST="$WORK/manifest-$TAG.tsv"
fi

[[ -f $MANIFEST ]] || die "找不到 manifest：$MANIFEST"

ROWS=$(awk -F'\t' -v r="$REPO" 'NR > 1 && $1 == r { print }' "$MANIFEST")
[[ -n $ROWS ]] || die "该 Release 里没有 $REPO 的备份。
  可能原因：这个仓库是新增的（更早的 Release 里没有）、或者名字写错了。
  可以用 -t 指定其它 Release，例如：$0 $REPO -t backup-20261115034116；或先 $0 $REPO --list -t <TAG> 看看有什么。"

if (( LIST_ONLY )); then
  printf '%s\n' "$ROWS" | awk -F'\t' '{
    printf "  %-58s %8.1f MB  sha256=%s\n", $3, $4/1048576, substr($5,1,16)
  }'
  exit 0
fi

COMMIT=$(printf '%s\n' "$ROWS" | awk -F'\t' 'NR==1{print $6}')
TOTAL_BYTES=$(printf '%s\n' "$ROWS" | awk -F'\t' '{s+=$4} END{print s+0}')
PARTS=$(printf '%s\n' "$ROWS" | awk -F'\t' '$3 ~ /\.part[0-9]+$/ {print $3}' | sort)
COUNT=$(printf '%s\n' "$ROWS" | awk 'END{print NR}')

info "仓库：$REPO  资产：$COUNT 个  合计 $((TOTAL_BYTES / 1048576)) MB  源 HEAD：${COMMIT:0:12}"

need_mb=$(( TOTAL_BYTES / 1048576 * 2 + 200 ))
avail_mb=$(df -Pm "$WORK" | awk 'NR==2{print $4}')
if (( avail_mb < need_mb )); then
  die "磁盘空间不足：需要约 ${need_mb}MB，$WORK 所在分区只剩 ${avail_mb}MB"
fi

download_one() {
  local asset=$1 dest="$WORK/$1"
  if [[ -n $FROM_DIR ]]; then
    [[ -f "$FROM_DIR/$asset" ]] || return 1
    cp -f "$FROM_DIR/$asset" "$dest"; return 0
  fi
  [[ -f $dest ]] && return 0
  gh release download "$TAG" -R "$SOURCE" --pattern "$asset" --dir "$WORK" >/dev/null 2>&1
}

verify_one() {
  local asset=$1 want actual
  want=$(printf '%s\n' "$ROWS" | awk -F'\t' -v a="$asset" '$3 == a {print $5; exit}')
  actual=$(sha256_of "$WORK/$asset")
  [[ $actual == "$want" ]] || die "sha256 不匹配：$asset
  期望 $want
  实际 $actual
  → 重新下载这个文件；若反复不一致，可能是上传损坏，换一个更早的 Release。"
  ok "sha256 匹配：$asset"
}

ARCHIVE=''
if [[ -n $PARTS ]]; then
  ARCHIVE=$(printf '%s\n' "$PARTS" | head -n 1)
  ARCHIVE=${ARCHIVE%.part[0-9][0-9][0-9]}
  info "分卷资产 $COUNT 个，合并为：$(basename "$ARCHIVE")"
  for p in $PARTS; do
    download_one "$p" || die "下载失败：$p"
    verify_one "$p"
  done
  rm -f "$WORK/$ARCHIVE"
  mapfile -t _parts < <(printf '%s\n' "$PARTS" | sed "s#^#$WORK/#")
  cat "${_parts[@]}" > "$WORK/$ARCHIVE"
  ok "分卷合并完成：$(basename "$ARCHIVE")"
  ARCHIVE="$WORK/$(basename "$ARCHIVE")"
else
  ARCHIVE=$(printf '%s\n' "$ROWS" | awk -F'\t' 'NR==1{print $3}')
  ARCHIVE="$WORK/$ARCHIVE"
  download_one "$(basename "$ARCHIVE")" || die "下载失败：$(basename "$ARCHIVE")"
  verify_one "$(basename "$ARCHIVE")"
  ARCHIVE="$WORK/$(basename "$ARCHIVE")"
fi

[[ -s $ARCHIVE ]] || die "压缩包为空：$ARCHIVE"

info "zstd 完整性校验…"
zstd -t "$ARCHIVE" >/dev/null 2>&1 || die "zstd -t 失败：压缩包损坏（分卷顺序错了或下载不完整）"
ok "zstd 完整性通过"

if (( DOWNLOAD_ONLY )); then
  ok "已下载并通过校验：$ARCHIVE"
  exit 0
fi

if [[ -e $OUT && -n "$(ls -A "$OUT" 2>/dev/null || true)" ]]; then
  die "输出目录非空：$OUT（换个 -o，或先手动清空）"
fi
mkdir -p "$OUT"
info "解压到 $OUT …"
zstd -dc "$ARCHIVE" | tar -xf - -C "$OUT" || die "解压失败"
(( KEEP )) || rm -f "$ARCHIVE"
ok "解压完成"

[[ -f "$OUT/HEAD" || -d "$OUT/objects" ]] || die "$OUT 不像裸仓库（缺 HEAD/objects），压缩包可能不是本流水线的产物"

info "git fsck …"
fsck_rc=0
git --git-dir="$OUT" fsck --no-progress --no-dangling >"$WORK/fsck.log" 2>&1 || fsck_rc=$?
if (( fsck_rc != 0 )); then
  if fsck_benign_only "$WORK/fsck.log"; then
    warn "fsck 只报了历史遗留的畸形 submodule URL（对象完整性正常，可忽略）"
  else
    tail -n 10 "$WORK/fsck.log" >&2
    die "git fsck 失败：仓库对象损坏。重新下载/解压；仍失败就换一个更早的 Release。"
  fi
fi
ok "git fsck 通过"

if [[ -n $COMMIT && $COMMIT != '-' ]]; then
  head=$(git --git-dir="$OUT" rev-parse HEAD 2>/dev/null || true)
  if [[ -n $head ]]; then
    [[ $head == "$COMMIT" ]] || die "HEAD 不匹配：manifest 记录 $COMMIT，实际 $head
  → 可能恢复到了错误的分卷组合，或 manifest 与资产不是同一次运行。"
    ok "HEAD 与 manifest 一致（${COMMIT:0:12}）"
  else
    warn "该仓库没有默认 HEAD（可能是空仓库或只有标签），跳过 HEAD 比对"
  fi
fi

refs=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')
branches=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' 'refs/heads/*' | wc -l | tr -d ' ')
tags=$(git --git-dir="$OUT" for-each-ref --format='%(refname)' 'refs/tags/*' | wc -l | tr -d ' ')
ok "裸仓库就绪：$OUT（$refs 个引用：$branches 分支 / $tags 标签）"

if [[ $(basename "$ARCHIVE") == *-shallow.tar.zst ]]; then
  warn "这是一个浅克隆备份：只有默认分支 tip，没有历史。
  需要完整历史时，去 Weekly Full Mirror 的 full-* Release 找同名但无 -shallow 的资产。"
fi

if [[ -n $CLONE ]]; then
  if [[ -e $CLONE && -n "$(ls -A "$CLONE" 2>/dev/null || true)" ]]; then die "clone 目标非空：$CLONE"; fi
  info "克隆工作副本到 $CLONE …"
  git -c safe.directory='*' clone --quiet "$OUT" "$CLONE" || die "git clone 失败"
  if [[ -n $BRANCH ]]; then
    git -C "$CLONE" checkout --quiet "$BRANCH" || die "检出 $BRANCH 失败（分支/标签不存在？）"
  fi
  ok "工作副本：$CLONE（$(git -C "$CLONE" rev-parse --short HEAD)）"
fi

echo ""
ok "恢复完成：$OUT"
echo "下一步："
echo "  git --git-dir=$OUT log --oneline -5          # 看历史"
echo "  git clone $OUT my-workdir                    # 取工作副本"
echo "  git -C my-workdir remote add origin <URL>    # 推到新仓库"
echo "  git -C my-workdir push origin --all && git -C my-workdir push origin --tags"
