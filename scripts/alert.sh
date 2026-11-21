#!/usr/bin/env bash
# 备份失败告警：失败时开/更新 issue，恢复时关闭。
#
# 用法：
#   alert.sh open     读取 FAILED_FILE，有失败则开或更新 issue
#   alert.sh close    本次成功，关闭所有该前缀的未结 issue
#
# 环境变量：
#   TAG          本次 Release tag（写进标题与正文）
#   FAILED_FILE  失败清单（repo<TAB>reason）
#   RUN_URL      本次 Actions 运行链接
#   ALERT_LABEL  issue 标签（默认 backup-failure）
#   ALERT_PREFIX issue 标题前缀（默认 "[backup]"；每周全量用 "[full]"）
#   REPO         GitHub 仓库（默认 $GITHUB_REPOSITORY）
set -Eeuo pipefail
export LC_ALL=C

MODE=${1:-}
TAG=${TAG:-unknown}
FAILED_FILE=${FAILED_FILE:-failed.tsv}
RUN_URL=${RUN_URL:-}
ALERT_LABEL=${ALERT_LABEL:-backup-failure}
ALERT_PREFIX=${ALERT_PREFIX:-[backup]}
REPO=${REPO:-${GITHUB_REPOSITORY:-}}

[[ -n $REPO ]] || { echo "GITHUB_REPOSITORY 未设置" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh 未安装" >&2; exit 2; }

case $MODE in
  open|close) ;;
  *) echo "用法: $0 open|close" >&2; exit 2 ;;
esac

ensure_label() {
  gh label create "$ALERT_LABEL" --repo "$REPO" \
    --color B60205 --description "备份失败告警（自动）" >/dev/null 2>&1 || true
}

find_issue() {
  gh issue list --repo "$REPO" --label "$ALERT_LABEL" --state open \
    --limit 100 --json number,title \
    --jq ".[] | select(.title | startswith(\"$ALERT_PREFIX\")) | .number" 2>/dev/null | head -n 1
}

if [[ $MODE == open ]]; then
  if [[ ! -s $FAILED_FILE ]]; then
    echo "没有失败仓库，无需告警"
    exit 0
  fi
  count=$(awk 'NF>=1 && $1!=""' "$FAILED_FILE" | wc -l | tr -d ' ')
  body_file=$(mktemp)
  {
    printf '**%s** 本次备份有 %s 个仓库失败。\n\n' "$TAG" "$count"
    printf '| 仓库 | 原因 |\n| --- | --- |\n'
    awk -F'\t' 'NF>=1 && $1!="" {printf "| `%s` | %s |\n", $1, ($2==""?"未知原因":$2)}' "$FAILED_FILE"
    printf '\n'
    [[ -n $RUN_URL ]] && printf '运行日志：%s\n' "$RUN_URL"
    printf 'Release：https://github.com/%s/releases/tag/%s\n' "$REPO" "$TAG"
    printf '\n> 该 issue 由备份流水线自动维护；下一次同类型运行全部成功时会自动关闭。\n'
  } > "$body_file"

  ensure_label
  existing=$(find_issue || true)
  title="$ALERT_PREFIX 备份失败：$count 个仓库（$TAG）"
  if [[ -n $existing ]]; then
    gh issue comment "$existing" --repo "$REPO" --body-file "$body_file" >/dev/null
    gh issue edit "$existing" --repo "$REPO" --title "$title" >/dev/null
    echo "已更新 issue #$existing（$count 个失败）"
  else
    if ! gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" \
      --label "$ALERT_LABEL" >/dev/null 2>&1; then
      # 标签不可用时退回无标签创建，告警本身不能被标签问题挡住
      gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" >/dev/null
    fi
    echo "已创建告警 issue（$count 个失败）"
  fi
  rm -f "$body_file"
  exit 0
fi

# close
ensure_label
closed=0
while IFS= read -r num; do
  [[ -z $num ]] && continue
  gh issue comment "$num" --repo "$REPO" \
    --body "✅ $TAG 运行全部成功，自动关闭此告警。" >/dev/null || true
  gh issue close "$num" --repo "$REPO" >/dev/null || true
  closed=$((closed + 1))
done < <(gh issue list --repo "$REPO" --label "$ALERT_LABEL" --state open \
  --limit 100 --json number,title \
  --jq ".[] | select(.title | startswith(\"$ALERT_PREFIX\")) | .number" 2>/dev/null || true)
echo "已关闭 $closed 个告警 issue"
