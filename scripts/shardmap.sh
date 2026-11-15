#!/usr/bin/env bash
# 按仓库体积做分片映射（LPT 贪心），让并行分片的负载尽量均衡。
#
# 用法：SHARD_TOTAL=6 bash scripts/shardmap.sh [清单文件]
# 输出：shardmap.tsv，每行 "owner\trepo\t分片号"
#
# 体积来自 GitHub API 的 .size（KB）。注意：规则类大仓库的 .size 可能严重低估
# （例如 blackmatrix7 实测 mirror 17.7GB，API 只报 4.5GB），所以清单里标了
# #shallow 的仓库按体积 0 计算，它们只做浅克隆，几乎不占分片负载。
set -Eeuo pipefail

LIST_FILE=${1:-back_ck_url.txt}
SHARD_TOTAL=${SHARD_TOTAL:-6}
OUT=${SHARD_MAP_OUT:-shardmap.tsv}

[[ $SHARD_TOTAL =~ ^[1-9][0-9]*$ ]] || { echo "SHARD_TOTAL 非法：$SHARD_TOTAL" >&2; exit 2; }
[[ -f $LIST_FILE ]] || { echo "清单不存在：$LIST_FILE" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. 解析 URL → owner/repo/是否浅克隆（去重，忽略大小写）
while IFS= read -r line; do
  shallow=0
  [[ $line == *'#shallow'* ]] && shallow=1
  url=${line%%#*}
  url=${url//[[:space:]]/}
  [[ -z $url ]] && continue
  if [[ $url =~ ^(https?://|git@)github\.com[:/]([^/]+)/(.+)$ ]]; then
    owner=${BASH_REMATCH[2]}
    repo=${BASH_REMATCH[3]%.git}
    repo=${repo%/}
    printf '%s\t%s\t%s\n' "$owner" "$repo" "$shallow"
  fi
done < "$LIST_FILE" | awk -F'\t' '!seen[tolower($1"/"$2)]++' > "$tmp/repos.tsv"

# 2. 逐个查询体积（串行，84 个仓库约 1 分钟；浅克隆仓库按 0 计）
while IFS=$'\t' read -r owner repo shallow; do
  if [[ $shallow == 1 ]]; then
    size=0
  else
    size=$(gh api "repos/$owner/$repo" --jq .size 2>/dev/null || echo 0)
  fi
  printf '%s\t%s\t%s\n' "$owner" "$repo" "$size"
done < "$tmp/repos.tsv" > "$tmp/sizes.tsv"

# 3. LPT 贪心分配：体积大的先放，放到当前累计最小的分片
awk -F'\t' '{ size = ($3 == "" ? 0 : $3); print size "\t" $1 "\t" $2 }' "$tmp/sizes.tsv" |
sort -t$'\t' -k1,1nr |
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
