# GitHub 仓库镜像备份

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

把**可能消失**的 GitHub 仓库克隆成裸镜像（mirror），用 zstd 压缩后作为 GitHub Release 资产保存。整条链路可校验、可恢复。

> 2026-11-15 重建：旧清单是 openwrt/immortalwrt 全家桶式的「大而全」镜像（13.4TB 历史），价值低。现在只备份高删库/封禁风险的东西，并为已经消失的项目整理外部存档，见 [docs/backup-targets.md](docs/backup-targets.md)。

## 它做什么

- **定时**：每天 04:00 UTC 运行（GitHub 调度可能延迟数小时）；也支持手动触发
- **并行**：prepare 建 Release → 6 个 matrix 分片同时备份（各自独立 runner/磁盘）→ finalize 合并清单、出报告、发布、清理
- **全量镜像**：git clone --mirror，保留全部分支、标签和提交历史；克隆后执行 git fsck
- **预检**：先用 gh api 探测仓库状态，404（已删/改名）与 451（DMCA/TOS 封禁）直接记为失败，不做无谓重试
- **压缩**：tar | zstd -10，压缩后执行 zstd -t 校验；超过 1800MB 自动分卷（GitHub 单资产上限 2GB）
- **清单**：每个 Release 附带 manifest-<tag>.tsv，记录 repo / url / asset / bytes / sha256 / 源仓库 HEAD commit
- **对账**：上传完成后逐项核对 Release 里的资产名和大小（草稿态 Release 也能核对）
- **报告**：Release 正文即备份报告（成功/失败/大小/HEAD/失败原因）
- **恢复演练**：每周日自动抽检 3 个资产，做「下载 → sha256 → 解压 → fsck → HEAD 比对」
- **分层备份**：日常对超大仓库只做浅克隆（默认分支 tip，资产名带 `-shallow`）；每周日单独跑一次完整 mirror（`full-YYYYMMDD` Release，保留最近 4 份）
- **失败告警**：有仓库失败时自动开 issue 并持续更新，下一次全部成功时自动关闭
- **SWH 兜底**：每天核查目标仓库在 Software Heritage 是否有可用快照，结果写入 docs/swh-snapshots.tsv（GitHub 上已经消失的仓库，这是最后的退路）；197 个目标按天分成 3 片轮转，避开 SWH 120 次/小时的限流
- **保留策略**：7 日 + 4 周 + 6 月（约 17 份），过期 Release 自动清理

## 目录结构

    .github/workflows/main.yml        每日增量备份 + 发布 + 清理 + 告警
    .github/workflows/weekly-full.yml 每周大仓库全量 mirror（独立 Release）
    .github/workflows/verify.yml      每周恢复演练
    .github/workflows/swh.yml         每日 Software Heritage 快照核查
    scripts/backup.sh                 预检 / 克隆 / 压缩 / 上传 / 对账
    scripts/shardmap.sh               按体积做 LPT 分片均衡
    scripts/report.sh                 生成备份报告
    scripts/summary.sh                生成 Actions Summary
    scripts/prune.sh                  草稿清理 + GFS / keep-last 保留策略
    scripts/verify.sh                 抽检恢复
    scripts/alert.sh                  失败开 issue / 恢复关闭
    scripts/swh.sh                    SWH 快照核查
    scripts/swh-targets.sh            生成 swh_targets.txt（清单 + 已删库）
    scripts/check-list.sh             清单体检（gh api 查 404/451/归档/体积）
    back_ck_url.txt                   仓库清单（一行一个 URL，# 开头为注释）
    swh_targets.txt                   SWH 核查目标（生成物，勿手改）
    docs/backup-targets.md            入选标准、风险证据、已删库存档、恢复手册
    docs/swh-snapshots.tsv            SWH 快照表（自动更新）
    恢复教程.md                        从备份恢复一个仓库的完整流程

## 清单怎么维护

只收「可能消失」的仓库，标准见 [docs/backup-targets.md](docs/backup-targets.md)：

1. 已发生过删除/封禁（作者删库、平台 451、改名后旧链失效）；
2. 结构性单点（单人维护、无组织治理、大陆作者、QQ/微信协议对抗、影视/书源/直播源）；
3. 历史不可重建。

编辑 back_ck_url.txt，一行一个 URL，支持 https:// 和 git@ 两种写法，# 开头为注释：

    https://github.com/MetaCubeX/mihomo
    git@github.com:Dreamacro/clash.git
    # 这行会被忽略

重复的仓库会自动跳过（按 owner/repo 去重）。**注意不要只备默认分支**：mihomo 的 main 已被无关项目占用，内核在 Alpha 分支，只有 --mirror 才能拿全。

## 使用

### 手动触发

Actions → **Repository Backup and Release** → Run workflow，可选参数：

| 参数 | 说明 |
|---|---|
| repo_filter | 只备份 URL 中包含该子串的仓库（留空 = 全部） |
| limit | 最多处理前 N 个仓库（0 = 全部） |

### 本地干跑

不需要 token，只克隆和压缩，不上传：

    TAG=local-test DRY_RUN=1 LIMIT=2 bash scripts/backup.sh

## 备份产物

- 命名：{owner}-{repo}-{unix时间戳}.tar.zst
- 分卷：{同名}.part000、.part001 …（每个 1800MB）
- 清单：manifest-backup-YYYYmmddHHMMSS.tsv

恢复前先用清单里的 sha256 校验，再解压。完整步骤见 [恢复教程.md](恢复教程.md)。

## 保留策略

scripts/prune.sh --gfs 按「最近 7 天各一份 + 最近 4 个自然周各一份 + 最近 6 个自然月各一份」保留，其余删除；24 小时内创建的 Release 一律不动，最新一份永远保留。时间以 tag 名里的 UTC 时间戳为准（该仓库的 Release created_at 字段不可靠）。

失败的运行会留下草稿，--drafts 会在每次运行开始时清掉 3 天前的草稿；被手动取消的运行会直接删除本次草稿 Release，不会发布只有部分资产的半成品。

## 已知限制 / 后续工作

- 实测一轮 128 仓：134 个资产、30.8 GB、20 分钟（6 分片并行，2026-11-21）；日常任务里单仓实际 mirror 超过 8 GB 会被跳过并记失败，防止拖垮分片；
- 巨型但内容可再生的仓库走 `#shallow` 浅克隆（只存默认分支快照，资产名带 `-shallow`）：blackmatrix7/ios_rule_script（全量 17.7GB → 浅克隆 74MB）、Guovin/iptv-api（20.3GB → 28MB）、the1812/Bilibili-Evolved（API 340MB）、manga-download/hakuneko（API 200MB）。完整历史交给每周日 `Weekly Full Mirror`（上限 30GB/仓，3 分片并行）；
- vernesong/OpenClash（47.8GB）暂不纳入，可照 `#shallow` 方式单独处理；
- SWH 只保存 git 对象，不保存 Release 资产；且其 API 对 UA 有要求（默认 curl UA 会 403）、限流 120 次/小时，脚本已按单次请求 + 间隔实现，并按天分片（scripts/swh.sh 的 SWH_SHARD/SWH_SHARDS）；
- GitHub fork 网络可能被整片封禁（ReVanced 702 仓先例），重要数据应定期导出到本地 / 对象存储。

## 许可协议

GNU General Public License v3.0，见 [LICENSE](LICENSE)。
