#!/usr/bin/env bash
# 生成 GitHub Actions Job Summary（简版仪表盘），不写 Release 正文。
# 输入：manifest.tsv / failed.tsv（由 backup.sh 产生）
# 输出：$WORKSPACE/summary.md，由 workflow cat 进 $GITHUB_STEP_SUMMARY
set -Eeuo pipefail
export LC_ALL=C

WORKSPACE=${WORKSPACE:-$(pwd)}
MANIFEST="$WORKSPACE/manifest.tsv"
FAILED="$WORKSPACE/failed.tsv"
TAG=${TAG:-}
REPO=${GITHUB_REPOSITORY:-}
SERVER=${GITHUB_SERVER_URL:-https://github.com}
RUN_URL=""
if [[ -n ${GITHUB_RUN_ID:-} && -n $REPO ]]; then
  RUN_URL="$SERVER/$REPO/actions/runs/$GITHUB_RUN_ID"
fi
OUT=${SUMMARY_OUT:-$WORKSPACE/summary.md}

[[ -f $MANIFEST ]] || printf 'repo\turl\tasset\tbytes\tsha256\tcommit\tbacked_up_at\n' > "$MANIFEST"
[[ -f $FAILED ]] || : > "$FAILED"

ok=$(awk -F'\t' 'NR>1 {print tolower($1)}' "$MANIFEST" | sort -u | wc -l | tr -d ' ')
failed=$(awk 'END {print NR}' "$FAILED")
assets=$(awk 'END {print (NR > 0 ? NR - 1 : 0)}' "$MANIFEST")
total_bytes=$(awk -F'\t' 'NR>1 {s += $4} END {printf "%.0f", s + 0}' "$MANIFEST")

hbytes() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB", b / 1073741824;
    else if (b >= 1048576) printf "%.1f MB", b / 1048576;
    else printf "%.0f KB", b / 1024;
  }'
}

duration() {
  local s
  s=$(( $(date -u +%s) - ${START_EPOCH:-0} ))
  if (( ${START_EPOCH:-0} == 0 || s < 0 )); then
    printf -- '-'
    return
  fi
  if (( s >= 3600 )); then
    printf '%d 小时 %d 分' $((s / 3600)) $((s % 3600 / 60))
  elif (( s >= 60 )); then
    printf '%d 分 %d 秒' $((s / 60)) $((s % 60))
  else
    printf '%d 秒' "$s"
  fi
}

if (( failed > 0 )); then
  title='## ⚠️ 备份完成，有 '"$failed"' 个失败'
elif (( ok > 0 )); then
  title='## ✅ 备份完成'
else
  title='## ⚠️ 本次没有备份任何仓库'
fi

{
  printf '%s\n\n' "$title"
  printf '> **%s** 成功 · **%s** 失败 · **%s** 个资产 · **%s** · 耗时 **%s**\n' \
    "$ok" "$failed" "$assets" "$(hbytes "$total_bytes")" "$(duration)"
  printf '>\n'
  if [[ -n $TAG && -n $REPO ]]; then
    printf '> [🏷️ %s](%s/%s/releases/tag/%s)\n' "$TAG" "$SERVER" "$REPO" "$TAG"
  elif [[ -n $TAG ]]; then
    printf '> 🏷️ %s\n' "$TAG"
  fi
  printf '\n'
} > "$OUT"

if (( failed > 0 )); then
  {
    printf '### ❌ 失败（%s）\n\n' "$failed"
    printf '| 仓库 | 原因 |\n|---|---|\n'
    awk -F'\t' '{ gsub(/\|/, "\\|", $2); printf "| %s | %s |\n", $1, $2 }' "$FAILED"
    printf '\n'
  } >> "$OUT"
fi

if (( assets > 0 )); then
  {
    printf '<details>\n<summary>📋 本次备份的仓库（%s）</summary>\n\n' "$ok"
    printf '| 仓库 | 大小 | HEAD | 资产 |\n|---|---|---|---|\n'
    awk -F'\t' '
      function hs(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b / 1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b / 1048576);
        return sprintf("%.0f KB", b / 1024);
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
    printf '\n</details>\n\n'
  } >> "$OUT"
fi

{
  printf '<sub>清单 manifest-%s.tsv · 生成于 %s UTC' "${TAG:-unknown}" "$(date -u +'%Y-%m-%d %H:%M:%S')"
  if [[ -n $RUN_URL ]]; then
    printf ' · [运行日志](%s)' "$RUN_URL"
  fi
  printf '</sub>\n'
} >> "$OUT"

echo "摘要已生成: $OUT（成功 $ok / 失败 $failed / 资产 $assets）"
