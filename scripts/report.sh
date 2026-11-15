#!/usr/bin/env bash
# 用 manifest.tsv / failed.tsv 生成 report.md（Release 正文 + Job Summary）。
set -Eeuo pipefail
export LC_ALL=C

WORKSPACE=${WORKSPACE:-$(pwd)}
MANIFEST="$WORKSPACE/manifest.tsv"
FAILED="$WORKSPACE/failed.tsv"
TAG=${TAG:-unknown}
START_EPOCH=${START_EPOCH:-0}
REPORT="$WORKSPACE/report.md"

[[ -f $MANIFEST ]] || printf 'repo\turl\tasset\tbytes\tsha256\tcommit\tbacked_up_at\n' > "$MANIFEST"
[[ -f $FAILED ]] || : > "$FAILED"

ok=$(awk -F'\t' 'NR>1 {print tolower($1)}' "$MANIFEST" | sort -u | wc -l | tr -d ' ')
failed=$(awk 'END {print NR}' "$FAILED")
assets=$(awk 'END {print (NR>0 ? NR-1 : 0)}' "$MANIFEST")
total_bytes=$(awk -F'\t' 'NR>1 {s+=$4} END {printf "%.0f", s+0}' "$MANIFEST")

hbytes() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB", b/1073741824;
    else if (b >= 1048576) printf "%.1f MB", b/1048576;
    else printf "%.0f KB", b/1024
  }'
}

if (( START_EPOCH > 0 )); then
  mins=$(( ($(date -u +%s) - START_EPOCH) / 60 ))
  start_iso=$(date -u -d "@$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
  end_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
else
  mins=0
  start_iso="?"
  end_iso="?"
fi

{
  printf '# 📊 备份报告 · %s\n\n' "$TAG"
  printf '| 项目 | 数值 |\n|---|---|\n'
  printf '| 备份窗口 | %s → %s（%s 分钟） |\n' "$start_iso" "$end_iso" "$mins"
  printf '| 仓库 | %s 个（✅ %s / ❌ %s） |\n' "$((ok + failed))" "$ok" "$failed"
  printf '| 资产 | %s 个文件，%s |\n' "$assets" "$(hbytes "$total_bytes")"
  printf '| 清单 | manifest-%s.tsv（含每个资产的 sha256 与源仓库 commit） |\n' "$TAG"
  printf '\n'
} > "$REPORT"

{
  printf '## ✅ 成功（%s）\n\n' "$ok"
  if (( assets > 0 )); then
    printf '| 仓库 | 大小 | HEAD | 资产 |\n|---|---|---|---|\n'
    awk -F'\t' '
      function hs(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824)
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576)
        return sprintf("%.0f KB", b/1024)
      }
      NR > 1 {
        k = $1
        b[k] += $4
        n[k]++
        if (c[k] == "") c[k] = ($6 == "" ? "-" : $6)
        if ($3 ~ /\.part[0-9]+$/) s[k] = 1
      }
      END {
        for (k in b) printf "%s\t%s\t%s\t%d\t%d\n", k, hs(b[k]), c[k], n[k], (s[k] ? 1 : 0)
      }
    ' "$MANIFEST" | sort | awk -F'\t' '
      { printf "| %s | %s | %s | %d%s |\n", $1, $2, ($3 == "-" ? "-" : substr($3, 1, 12)), $4, ($5 ? " 个分卷" : " 个文件") }
    '
  else
    printf '> 本次没有成功备份的仓库。\n'
  fi
  printf '\n'
} >> "$REPORT"

{
  printf '## ❌ 失败（%s）\n\n' "$failed"
  if (( failed > 0 )); then
    printf '| 仓库 | 原因 |\n|---|---|\n'
    awk -F'\t' '{ gsub(/\|/, "\\|", $2); printf "| %s | %s |\n", $1, $2 }' "$FAILED"
  else
    printf '> 全部成功。\n'
  fi
  printf '\n'
} >> "$REPORT"

cat >> "$REPORT" <<'REPORT_EOF'
## 🔐 完整性

- 克隆完成后执行 `git fsck`，压缩完成后执行 `zstd -t`；
- 每个资产都计算 sha256 并写入 manifest；
- 每周由 **Verify Backups** workflow 随机抽检资产，做「下载 → sha256 → 解压 → fsck」恢复演练。

## ♻️ 恢复

```bash
# 1. 下载（分卷备份要把 part 全部下载）
gh release download <TAG> -R <owner/repo> -p 'owner-repo-*.tar.zst*'

# 2. 如果是分卷，先合并
cat owner-repo-*.part* > owner-repo.tar.zst

# 3. 校验（sha256 见 manifest）
sha256sum owner-repo.tar.zst

# 4. 解压、校验、克隆工作副本
mkdir -p restore
zstd -dc owner-repo.tar.zst | tar xf - -C restore
git --git-dir=restore fsck --no-progress
git clone restore workdir
```
REPORT_EOF

{
  printf '\n---\n'
  printf '⏱️ 生成于 %s · 压缩格式 zstd · 分卷阈值 1800MB\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
} >> "$REPORT"

echo "报告已生成: $REPORT（成功 $ok / 失败 $failed / 资产 $assets）"
