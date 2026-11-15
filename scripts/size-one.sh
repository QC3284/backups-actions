#!/usr/bin/env bash
# 单个仓库体积查询：第 1 个参数是 "owner\trepo\tshallow"
set -Eeuo pipefail
IFS=$'\t' read -r owner repo shallow <<< "$1"
if [[ "$shallow" == 1 ]]; then
  printf '%s\t%s\t0\n' "$owner" "$repo"
  exit 0
fi
size=$(gh api "repos/$owner/$repo" --jq .size 2>/dev/null || echo 0)
printf '%s\t%s\t%s\n' "$owner" "$repo" "$size"
