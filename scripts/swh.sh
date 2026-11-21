#!/usr/bin/env bash
# Software Heritage 兜底核查：检查每个目标仓库在 SWH 里是否有可用快照。
#
# GitHub 侧的删库/封禁无法从 GitHub 恢复，SWH 保存的 git 对象是最后的退路。
# 本脚本只读，不改任何远端状态；输出 docs/swh-snapshots.tsv 与 swh-report.md。
#
# 环境变量：
#   WORKSPACE   工作目录（默认当前目录）
#   TARGETS     目标清单（默认 $WORKSPACE/swh_targets.txt）
#   OUT         快照表（默认 $WORKSPACE/docs/swh-snapshots.tsv）
#   REPORT      报告（默认 $WORKSPACE/swh-report.md）
#   LIMIT       >0 时只处理前 N 个（本地调试用）
#   GH_STATUS   0 = 不查 GitHub 存在性（默认 1）
#
# SWH API 对 User-Agent 有要求（默认 curl UA 会被 403），且限流 120 次/小时，
# 所以每个仓库只打 1 次 visits 接口，并在请求间留间隔。
set -Eeuo pipefail
export LC_ALL=C

WORKSPACE=${WORKSPACE:-$(pwd)}
TARGETS=${TARGETS:-$WORKSPACE/swh_targets.txt}
OUT=${OUT:-$WORKSPACE/docs/swh-snapshots.tsv}
REPORT=${REPORT:-$WORKSPACE/swh-report.md}
LIMIT=${LIMIT:-0}
GH_STATUS=${GH_STATUS:-1}
UA='repo-backup/1.0 (+https://github.com/QC3284/repo-backup)'
API='https://archive.softwareheritage.org/api/1'

[[ -f $TARGETS ]] || { echo "目标清单不存在: $TARGETS" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq 未安装" >&2; exit 2; }
command -v curl >/dev/null || { echo "curl 未安装" >&2; exit 2; }

mkdir -p "$(dirname "$OUT")"

url_encode() { jq -rn --arg v "$1" '$v|@uri'; }

# 返回 "snapshot<TAB>date<TAB>status"，没有快照时输出空。
swh_lookup() {
  local url=$1 enc body code attempt
  enc=$(url_encode "$url")
  for attempt in 1 2 3; do
    code=$(curl -sS -A "$UA" -m 30 -o /tmp/swh_visits.json -w '%{http_code}' \
      "$API/origin/$enc/visits/?limit=100" 2>/dev/null || echo 000)
    case $code in
      200)
        jq -r '[.[] | select(.snapshot != null)] | first
               | if . then [.snapshot, .date, .status] | @tsv else empty end' \
          /tmp/swh_visits.json 2>/dev/null || true
        return 0
        ;;
      403) printf 'HTTP403\t\t\n'; return 0 ;; # 反爬/封 IP，不能当成"未收录"
      404) return 0 ;;                       # SWH 未收录该 origin
      429|5??|000) sleep $((attempt * 15)) ;; # 限流/网络抖动
      *) sleep $((attempt * 5)) ;;
    esac
  done
  printf 'ERROR\t-\t-\n'
}

# GitHub 侧状态：ok / 404 / 451 / ?（补充上下文，不影响 SWH 结论）
gh_state() {
  local owner repo err
  owner=${1%%/*}; repo=${1#*/}
  if (( GH_STATUS == 0 )); then printf '?'; return 0; fi
  if err=$(gh api "repos/$owner/$repo" --jq '.id' 2>&1 >/dev/null); then
    printf 'ok'
  elif grep -qi 'blocked' <<< "$err"; then
    printf '451'
  else
    printf '404'
  fi
}

printf 'url\tgithub\tswh\tsnapshot\tvisited_at\n' > "$OUT"
printf '# Software Heritage 快照核查（自动生成，勿手改）\n\n' > "$REPORT"
printf '生成时间：%s\n\n' "$(date -u +%FT%TZ)" >> "$REPORT"

total=0 ok=0 missing=0 errors=0 blocked=0 deleted_with_snapshot=0
deleted_rows=()
while IFS= read -r line; do
  url=${line%%#*}
  url=${url//[[:space:]]/}
  [[ -z $url ]] && continue
  [[ $url == https://github.com/* ]] || continue
  (( LIMIT > 0 && total >= LIMIT )) && break
  total=$((total + 1))

  slug=${url#https://github.com/}
  slug=${slug%.git}
  slug=${slug%/}
  gh=$(gh_state "$slug")

  snapshot='' date='' status=''
  IFS=$'\t' read -r snapshot date status <<< "$(swh_lookup "$url")" || true

  case $snapshot in
    HTTP403) swh='blocked'; blocked=$((blocked + 1)); snapshot=''; errors=$((errors + 1)) ;;
    ERROR) swh='error'; errors=$((errors + 1)); snapshot='' ;;
    '')    swh='absent'; missing=$((missing + 1)) ;;
    *)     swh='ok'; ok=$((ok + 1)) ;;
  esac

  if [[ $gh == 404 || $gh == 451 ]] && [[ $swh == ok ]]; then
    deleted_with_snapshot=$((deleted_with_snapshot + 1))
    deleted_rows+=("| \`$slug\` | $gh | \`${snapshot:0:12}\` | ${date%%T*} |")
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$url" "$gh" "$swh" "${snapshot:--}" "${date:--}" >> "$OUT"
  sleep 0.4
done < "$TARGETS"

{
  printf '## Software Heritage 兜底核查\n\n'
  printf '| 指标 | 数量 |\n| --- | --- |\n'
  printf '| 目标仓库 | %s |\n| 有快照 | %s |\n| SWH 未收录 | %s |\n| 查询失败 | %s |\n' \
    "$total" "$ok" "$missing" "$errors"
  printf '| GitHub 已消失但 SWH 有快照 | %s |\n\n' "$deleted_with_snapshot"
  if (( deleted_with_snapshot > 0 )); then
    printf '### 已从 GitHub 消失、仍可从 SWH 恢复\n\n'
    printf '| 仓库 | GitHub | 快照 | 快照日期 |\n| --- | --- | --- | --- |\n'
    printf '%s\n' "${deleted_rows[@]}"
    printf '\n恢复方式见 docs/backup-targets.md#恢复手册。\n\n'
  fi
  printf '完整数据：%s\n' "${OUT#"$WORKSPACE"/}"
} >> "$REPORT"
cp "$REPORT" /tmp/swh-step-summary.md

echo "SWH 核查完成：$total 个目标，$ok 个有快照，$missing 个未收录，$errors 个查询失败（其中 $blocked 个被 403 拦截）"
if (( blocked > 0 )); then
  echo "::error::$blocked 个请求被 SWH 以 403 拒绝；若全部被拦，说明 runner IP 被反爬策略封禁，快照表不可信"
elif (( errors > 0 )); then
  echo "::warning::$errors 个仓库查询 SWH 失败（限流或网络）"
fi
exit 0
