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
- **保留策略**：7 日 + 4 周 + 6 月（约 17 份），过期 Release 自动清理

## 目录结构

    .github/workflows/main.yml    定时备份 + 发布 + 清理
    .github/workflows/verify.yml  每周恢复演练
    scripts/backup.sh             预检 / 克隆 / 压缩 / 上传 / 对账
    scripts/report.sh             生成备份报告
    scripts/prune.sh              草稿清理 + GFS 保留策略
    scripts/verify.sh             抽检恢复
    back_ck_url.txt               仓库清单（一行一个 URL，# 开头为注释）
    docs/backup-targets.md        入选标准、风险证据、已删库存档、恢复手册
    恢复教程.md                    从备份恢复一个仓库的完整流程

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

失败的运行会留下草稿，--drafts 会在每次运行开始时清掉 3 天前的草稿。

## 已知限制 / 后续工作

- 单仓超过约 2GB 会拖慢整轮（vernesong/OpenClash 47.8GB，暂不纳入，需要本地镜像或 shallow 方案）；
- 每日全量 mirror：大仓库（blackmatrix7 4.4GB 等）后续可拆成每周一次；
- 非 GitHub 镜像（gitee / gitcode / Software Heritage）暂不进入流水线，手册见 docs/backup-targets.md；
- GitHub fork 网络可能被整片封禁（ReVanced 702 仓先例），重要数据应定期导出到本地 / 对象存储。

## 许可协议

GNU General Public License v3.0，见 [LICENSE](LICENSE)。
