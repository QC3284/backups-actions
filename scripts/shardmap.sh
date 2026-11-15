#!/usr/bin/env bash
# 按仓库体积做分片映射（LPT 贪心），让并行分片的负载尽量均衡。
#
# 用法：SHARD_TOTAL=6 bash scripts/shardmap.sh [清单文件]
# 输出：shardmap.tsv，每行 "owner\trepo\t分片号"
#
# 体积来自 GitHub API 的 .size（KB，即仓库对象库大小）。
set -Eeuo pipefail

LIST_FILE=${1:-back_ck_url.txt}
SHARD_TOTAL=${SHARD_TOTAL:-6}
OUT=${SHARD_MAP_OUT:-shardmap.tsv}

[[ $SHARD_TOTAL =~ ^[1-9][0-9]*$ ]] || { echo "SHARD_TOTAL 非法：$SHARD_TOTAL" >&2; exit 2; }
[[ -f $LIST_FILE ]] || { echo "清单不存在：$LIST_FILE" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. 解析 URL → owner/repo（去重，忽略大小写）
while IFS= read -r url; do
  url=${url%%#*}
  url=${url//[[:space:]]/}
  [[ -z $url ]] && continue
  if [[ $url =~ ^(https?://|git@)github\.com[:/]([^/]+)/(.+)$ ]]; then
    owner=${BASH_REMATCH[2]}
    repo=${BASH_REMATCH[3]%.git}
    repo=${repo%/}
    printf '%s\t%s\n' "$owner" "$repo"
  fi
done < "$LIST_FILE" | awk -F'\t' '!seen[tolower($1"/"$2)]++' > "$tmp/repos.tsv"

# 2. 并发查询体积（KB），失败的记 0
tr '\t' ' ' < "$tmp/repos.tsv" | xargs -r -P 8 -n 2 bash -c '
  size=$(gh api "repos/$0/$1" --jq .size 2>/dev/null || echo 0)
  printf "%s\t%s\t%s\n" "$0" "$1" "$size"
' > "$tmp/sizes.tsv"

# 3. LPT 贪心分配：体积大的先放，放到当前累计最小的分片
awk -F'\t' -v n="$SHARD_TOTAL" '
  { size = ($3 == "" ? 0 : $3); print size "\t" $1 "\t" $2 }
' "$tmp/sizes.tsv" | sort -t$'\t' -k1,1nr |
awk -F'\t' -v n="$SHARD_TOTAL" '
  BEGIN { for (i = 0; i < n; i++) load[i] = 0 }
  {
    best = 0
    for (i = 1; i < n; i++) if (load[i] < load[best]) best = i
    load[best] += $1
    printf "%s\t%s\t%d\n", $2, $3, best
  }
  END {
    printf "分片负载（KB）：" > "/dev/stderr"
    for (i = 0; i < n; i++) printf "%s%d", (i ? " " : ""), load[i] > "/dev/stderr"
    printf "\n" > "/dev/stderr"
  }
' > "$OUT"

echo "shardmap: $(wc -l < "$OUT") 个仓库 → $(cut -f3 "$OUT" | sort -u | wc -l) 个分片 ($OUT)"
