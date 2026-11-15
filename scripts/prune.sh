#!/usr/bin/env bash
# Release 清理。
#   --drafts            删除超过 DRAFT_KEEP_DAYS 天的草稿
#   --gfs               按 7 日 + 4 周 + 6 月 保留，其余删除
#   --dry-run           只打印
#   --draft-days N      草稿保留天数（默认 3）
#
# 环境变量：GITHUB_REPOSITORY / SKIP_TAG / KEEP_DAILY / KEEP_WEEKLY / KEEP_MONTHLY
# 测试：RELEASES_TSV 指向本地 fixture 时只选择、不删除。
set -Eeuo pipefail
export LC_ALL=C

REPO=${GITHUB_REPOSITORY:-}
DRY_RUN=0
MODE_DRAFTS=0
MODE_GFS=0
DRAFT_KEEP_DAYS=${DRAFT_KEEP_DAYS:-3}
KEEP_DAILY=${KEEP_DAILY:-7}
KEEP_WEEKLY=${KEEP_WEEKLY:-4}
KEEP_MONTHLY=${KEEP_MONTHLY:-6}
SKIP_TAG=${SKIP_TAG:-}
RELEASES_TSV=${RELEASES_TSV:-}

while (( $# )); do
  case $1 in
    --drafts) MODE_DRAFTS=1 ;;
    --gfs) MODE_GFS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --draft-days) DRAFT_KEEP_DAYS=$2; shift ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

if (( ! MODE_DRAFTS && ! MODE_GFS )); then
  echo "用法: $0 [--drafts|--gfs] [--dry-run] [--draft-days N]" >&2
  exit 2
fi
[[ $DRAFT_KEEP_DAYS =~ ^[0-9]+$ ]] || DRAFT_KEEP_DAYS=3
[[ $KEEP_DAILY =~ ^[0-9]+$ ]] || KEEP_DAILY=7
[[ $KEEP_WEEKLY =~ ^[0-9]+$ ]] || KEEP_WEEKLY=4
[[ $KEEP_MONTHLY =~ ^[0-9]+$ ]] || KEEP_MONTHLY=6

fetch_releases() {
  if [[ -n $RELEASES_TSV ]]; then
    cat "$RELEASES_TSV"
    return 0
  fi
  if [[ -z $REPO ]]; then
    echo "GITHUB_REPOSITORY 未设置" >&2
    return 1
  fi
  gh release list -R "$REPO" -L 1000 --json tagName,createdAt,isDraft \
    --jq '.[] | [.tagName, .createdAt, (.isDraft|tostring)] | @tsv'
}

# 从 tag 名解析时间（backup-YYYYmmddHHMMSS / archive/repo-archive-YYYYmmdd-*），
# 解析不出来时退回 Release 的 createdAt。
release_epoch() {
  local tag=$1 created=$2 d
  if [[ $tag =~ ^backup-([0-9]{14})$ ]]; then
    d=${BASH_REMATCH[1]}
    d=$(printf '%s' "$d" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$/\1-\2-\3T\4:\5:\6Z/')
    date -u -d "$d" +%s
    return 0
  fi
  if [[ $tag =~ ^archive/repo-archive-([0-9]{8})- ]]; then
    d=${BASH_REMATCH[1]}
    d=$(printf '%s' "$d" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})$/\1-\2-\3/')
    date -u -d "$d" +%s
    return 0
  fi
  date -u -d "$created" +%s
}

delete_release() {
  local tag=$1 why=$2
  if (( DRY_RUN == 1 )) || [[ -n $RELEASES_TSV ]]; then
    echo "  [dry-run] 删除 $tag（$why）"
    return 0
  fi
  echo "  🗑️  删除 $tag（$why）"
  gh release delete "$tag" -R "$REPO" --yes --cleanup-tag || echo "::warning::删除 $tag 失败"
}

prune_drafts() {
  local now tag created draft age
  now=$(date -u +%s)
  echo "扫描草稿（保留最近 $DRAFT_KEEP_DAYS 天）…"
  while IFS=$'\t' read -r tag created draft; do
    [[ $draft == true ]] || continue
    [[ -n $SKIP_TAG && $tag == "$SKIP_TAG" ]] && continue
    age=$(( (now - $(release_epoch "$tag" "$created")) / 86400 ))
    if (( age >= DRAFT_KEEP_DAYS )); then
      delete_release "$tag" "草稿 $age 天"
    fi
  done < <(fetch_releases)
}

prune_gfs() {
  local -a sorted=()
  mapfile -t sorted < <(
    fetch_releases | while IFS=$'\t' read -r tag created draft; do
      [[ -z $tag ]] && continue
      epoch=$(release_epoch "$tag" "$created")
      printf '%s\t%s\t%s\t%s\n' "$epoch" "$tag" "$created" "$draft"
    done | sort -t$'\t' -k1,1nr
  )
  if (( ${#sorted[@]} == 0 )); then
    echo "没有 Release 需要处理"
    return 0
  fi

  local now line tag created draft epoch age day week month
  local daily_n=0 weekly_n=0 monthly_n=0
  declare -A keep=() seen_day=() seen_week=() seen_month=() kept_week=() kept_month=()
  now=$(date -u +%s)

  # 1) 日：最近 KEEP_DAILY 个不同日期，各留最新一份；24 小时内的不动
  for line in "${sorted[@]}"; do
    IFS=$'\t' read -r epoch tag created draft <<< "$line"
    [[ $draft == true ]] && continue
    if [[ -n $SKIP_TAG && $tag == "$SKIP_TAG" ]]; then keep[$tag]=1; continue; fi
    age=$(( (now - epoch) / 3600 ))
    if (( age < 24 )); then keep[$tag]=1; continue; fi
    day=$(date -u -d "@$epoch" +%F)
    if (( daily_n < KEEP_DAILY )) && [[ -z ${seen_day[$day]:-} ]]; then
      seen_day[$day]=1
      keep[$tag]=1
      daily_n=$((daily_n + 1))
      kept_week[$(date -u -d "@$epoch" +%G-%V)]=1
      kept_month[$(date -u -d "@$epoch" +%Y-%m)]=1
    fi
  done

  # 2) 周：未被日保留覆盖的最近 KEEP_WEEKLY 个自然周，各留最新一份
  for line in "${sorted[@]}"; do
    IFS=$'\t' read -r epoch tag created draft <<< "$line"
    [[ $draft == true ]] && continue
    [[ -n ${keep[$tag]:-} ]] && continue
    week=$(date -u -d "@$epoch" +%G-%V)
    if (( weekly_n < KEEP_WEEKLY )) && [[ -z ${seen_week[$week]:-} && -z ${kept_week[$week]:-} ]]; then
      seen_week[$week]=1
      keep[$tag]=1
      weekly_n=$((weekly_n + 1))
      kept_month[$(date -u -d "@$epoch" +%Y-%m)]=1
    fi
  done

  # 3) 月：未被日/周覆盖的最近 KEEP_MONTHLY 个自然月，各留最新一份
  for line in "${sorted[@]}"; do
    IFS=$'\t' read -r epoch tag created draft <<< "$line"
    [[ $draft == true ]] && continue
    [[ -n ${keep[$tag]:-} ]] && continue
    month=$(date -u -d "@$epoch" +%Y-%m)
    if (( monthly_n < KEEP_MONTHLY )) && [[ -z ${seen_month[$month]:-} && -z ${kept_month[$month]:-} ]]; then
      seen_month[$month]=1
      keep[$tag]=1
      monthly_n=$((monthly_n + 1))
    fi
  done

  # 4) 永远保留最新一份
  local newest=""
  for line in "${sorted[@]}"; do
    IFS=$'\t' read -r epoch tag created draft <<< "$line"
    [[ $draft == true ]] && continue
    newest=$tag
    break
  done
  [[ -n $newest ]] && keep[$newest]=1

  local kept=0 deleted=0
  for line in "${sorted[@]}"; do
    IFS=$'\t' read -r epoch tag created draft <<< "$line"
    [[ $draft == true ]] && continue
    if [[ -n ${keep[$tag]:-} ]]; then
      kept=$((kept + 1))
      echo "  ✅ 保留 $tag（$created）"
    else
      delete_release "$tag" "超出保留策略"
      deleted=$((deleted + 1))
    fi
  done
  echo "保留 $kept 个，删除 $deleted 个"
}

if (( MODE_DRAFTS )); then prune_drafts; fi
if (( MODE_GFS )); then prune_gfs; fi
