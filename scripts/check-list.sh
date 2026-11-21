#!/usr/bin/env bash
# 清单体检：逐个用 gh api 检查 back_ck_url.txt 里的仓库是否还存在、是否归档、体积多大。
# 只读，不改任何东西；用于日常维护清单（改名/404/451 早发现）。
#
# 用法：check-list.sh [--list FILE] [--limit N] [--strict]
#   --strict  有 404/451 时以非 0 退出（适合 CI）
#
# 输出 TSV：repo  status  size_kb  archived  pushed_at  stars
set -Eeuo pipefail
export LC_ALL=C

LIST=back_ck_url.txt
LIMIT=0
STRICT=0
while (( $# )); do
  case $1 in
    --list) LIST=$2; shift ;;
    --limit) LIMIT=$2; shift ;;
    --strict) STRICT=1 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f $LIST ]] || { echo "清单不存在: $LIST" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh 未安装" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq 未安装" >&2; exit 2; }

urls=$(grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "$LIST" | sed 's#https://github.com/##' | sort -u || true)
[[ -n $urls ]] || { echo "清单里没有 GitHub URL" >&2; exit 2; }
if (( LIMIT > 0 )); then
  urls=$(printf '%s\n' "$urls" | head -n "$LIMIT")
fi

check_one() {
  local slug=$1 out
  if out=$(gh api "repos/$slug" --jq '[(.size|tostring), (.archived|tostring), (.pushed_at|split("T")[0]), (.stargazers_count|tostring)] | @tsv' 2>/tmp/check-list.$$.err); then
    printf '%s\tok\t%s\n' "$slug" "$out"
  elif grep -qi 'blocked' /tmp/check-list.$$.err 2>/dev/null; then
    printf '%s\t451\t-\t-\t-\t-\n' "$slug"
  else
    printf '%s\t404\t-\t-\t-\t-\n' "$slug"
  fi
  rm -f /tmp/check-list.$$.err
}
export -f check_one

printf 'repo\tstatus\tsize_kb\tarchived\tpushed_at\tstars\n'
results=$(printf '%s\n' "$urls" | xargs -r -P8 -n1 bash -c 'check_one "$1"' _ | sort)
printf '%s\n' "$results"

missing=$(printf '%s\n' "$results" | awk -F'\t' '$1=="404"||$1=="451"' | wc -l | tr -d ' ')
archived=$(printf '%s\n' "$results" | awk -F'\t' '$3=="true"' | wc -l | tr -d ' ')
total=$(printf '%s\n' "$urls" | wc -l | tr -d ' ')
echo "---" >&2
echo "共 $total 个仓库：缺失/封禁 $missing，已归档 $archived" >&2
if (( STRICT && missing > 0 )); then
  exit 1
fi
