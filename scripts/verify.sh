#!/usr/bin/env bash
# 从最新的 Release 里随机抽几个资产做恢复演练：
# 下载 → sha256 → zstd -t → 解压 → git fsck → HEAD 与 manifest 比对。
#
# 环境变量：GITHUB_REPOSITORY / TAG / VERIFY_COUNT（默认 3）/ VERIFY_MAX_MB（默认 400）
set -Eeuo pipefail
export LC_ALL=C

REPO=${GITHUB_REPOSITORY:-}
TAG=${TAG:-}
COUNT=${VERIFY_COUNT:-3}
MAX_MB=${VERIFY_MAX_MB:-400}
WORK="${WORKSPACE:-$(pwd)}/verify_tmp"

if [[ -z $REPO ]]; then
  echo "GITHUB_REPOSITORY 未设置" >&2
  exit 2
fi
[[ $COUNT =~ ^[0-9]+$ ]] || COUNT=3
[[ $MAX_MB =~ ^[0-9]+$ ]] || MAX_MB=400

if [[ -z $TAG ]]; then
  TAG=$(gh release list -R "$REPO" -L 1 --json tagName --jq '.[0].tagName')
fi
if [[ -z $TAG || $TAG == null ]]; then
  echo "找不到可用的 Release" >&2
  exit 2
fi
echo "校验 Release: $TAG"

rm -rf "$WORK"
mkdir -p "$WORK/dl"
gh release download "$TAG" -R "$REPO" --pattern "manifest-$TAG.tsv" --dir "$WORK" >/dev/null || true
MANIFEST="$WORK/manifest-$TAG.tsv"
if [[ ! -f $MANIFEST ]]; then
  echo "该 Release 没有 manifest-$TAG.tsv，跳过（旧格式备份）"
  exit 0
fi

# 只挑未分卷、体积在 MAX_MB 以内的资产
awk -F'\t' -v max="$MAX_MB" '
  NR > 1 && $3 !~ /\.part[0-9]+$/ && $4 + 0 <= max * 1048576 {
    print $1 "\t" $3 "\t" $4 "\t" $5 "\t" $6
  }' "$MANIFEST" | sort -t$'\t' -k3,3n > "$WORK/candidates.tsv"

total=$(awk 'END {print NR}' "$WORK/candidates.tsv")
if (( total == 0 )); then
  echo "没有满足条件的资产可校验（可能都被分卷或超过 ${MAX_MB}MB）"
  exit 0
fi

picks=()
if (( total <= COUNT )); then
  mapfile -t picks < <(seq 1 "$total")
else
  for ((i = 0; i < COUNT; i++)); do
    if (( COUNT == 1 )); then
      idx=1
    else
      idx=$(( 1 + i * (total - 1) / (COUNT - 1) ))
    fi
    picks+=("$idx")
  done
fi

fail=0
for pick in "${picks[@]}"; do
  IFS=$'\t' read -r repo asset bytes sha commit < <(sed -n "${pick}p" "$WORK/candidates.tsv")
  echo ""
  echo "📦 校验 $repo"
  echo "   资产: $asset（$((bytes / 1048576))MB）"

  if ! gh release download "$TAG" -R "$REPO" --pattern "$asset" --dir "$WORK/dl" >/dev/null; then
    echo "   ❌ 下载失败"
    fail=$((fail + 1))
    continue
  fi
  file="$WORK/dl/$asset"

  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ $actual != "$sha" ]]; then
    echo "   ❌ sha256 不匹配：期望 $sha，实际 $actual"
    fail=$((fail + 1))
    rm -f "$file"
    continue
  fi
  echo "   ✅ sha256 匹配"

  if ! zstd -t "$file" >/dev/null 2>&1; then
    echo "   ❌ zstd 完整性校验失败"
    fail=$((fail + 1))
    rm -f "$file"
    continue
  fi
  echo "   ✅ zstd 完整性通过"

  dest="$WORK/extract"
  rm -rf "$dest"
  mkdir -p "$dest"
  if ! zstd -dc "$file" | tar xf - -C "$dest" 2>/dev/null; then
    echo "   ❌ 解压失败"
    fail=$((fail + 1))
    rm -f "$file"
    continue
  fi

  if ! git --git-dir="$dest" fsck --no-progress --no-dangling >"$WORK/fsck.log" 2>&1; then
    echo "   ❌ git fsck 失败"
    tail -n 5 "$WORK/fsck.log"
    fail=$((fail + 1))
    rm -f "$file"
    continue
  fi
  echo "   ✅ git fsck 通过"

  if [[ $commit != "-" && -n $commit ]]; then
    head=$(git --git-dir="$dest" rev-parse HEAD 2>/dev/null || true)
    if [[ $head != "$commit" ]]; then
      echo "   ❌ HEAD 不匹配：期望 $commit，实际 $head"
      fail=$((fail + 1))
      rm -f "$file"
      continue
    fi
    echo "   ✅ HEAD 与 manifest 一致（${commit:0:12}）"
  fi

  rm -f "$file"
  rm -rf "$dest"
done

echo ""
echo "=============================================="
if (( fail > 0 )); then
  echo "❌ 校验失败 $fail 项"
  exit 1
fi
echo "✅ 全部 ($COUNT) 个抽样资产校验通过"
exit 0
