# GitHub 仓库镜像备份

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

每天把 `back_ck_url.txt` 里列出的 GitHub 仓库克隆成**裸镜像（mirror）**，用 zstd 压缩后作为 GitHub Release 资产保存。整条链路可校验、可恢复。

## 它做什么

- **定时**：每天 04:00 UTC 运行（GitHub 调度可能延迟数小时）；也支持手动触发
- **全量镜像**：`git clone --mirror`，保留全部分支、标签和提交历史；克隆后执行 `git fsck`
- **压缩**：`tar | zstd -10`，压缩后执行 `zstd -t` 校验；超过 1800MB 自动分卷（GitHub 单资产上限 2GB）
- **清单**：每个 Release 附带 `manifest-<tag>.tsv`，记录 repo / url / asset / bytes / **sha256** / **源仓库 HEAD commit**
- **对账**：上传完成后逐项核对 Release 里的资产名和大小
- **报告**：Release 正文即备份报告（成功/失败/大小/HEAD/失败原因）
- **恢复演练**：每周日自动抽检 3 个资产，做「下载 → sha256 → 解压 → fsck → HEAD 比对」
- **保留策略**：7 日 + 4 周 + 6 月（约 17 份），过期 Release 自动清理

## 目录结构

```
.github/workflows/main.yml    定时备份 + 发布 + 清理
.github/workflows/verify.yml  每周恢复演练
scripts/backup.sh             克隆 / 压缩 / 上传 / 对账
scripts/report.sh             生成备份报告
scripts/prune.sh              草稿清理 + GFS 保留策略
scripts/verify.sh             抽检恢复
back_ck_url.txt               仓库清单（一行一个 URL）
```

## 使用

### 增删仓库

编辑 `back_ck_url.txt`，一行一个 URL，支持 `https://` 和 `git@` 两种写法，`#` 开头为注释：

```
https://github.com/openwrt/packages
git@github.com:torvalds/linux.git
# 这行会被忽略
```

重复的仓库会自动跳过（按 owner/repo 去重）。

### 手动触发

Actions → **Repository Backup and Release** → Run workflow，可选参数：

| 参数 | 说明 |
|---|---|
| `repo_filter` | 只备份 URL 中包含该子串的仓库（留空 = 全部） |
| `limit` | 最多处理前 N 个仓库（0 = 全部） |

### 本地干跑

不需要 token，只克隆和压缩，不上传：

```bash
TAG=local-test DRY_RUN=1 LIMIT=2 bash scripts/backup.sh
```

## 备份产物

- 命名：`{owner}-{repo}-{unix时间戳}.tar.zst`
- 分卷：`{同名}.part000`、`.part001` …（每个 1800MB）
- 清单：`manifest-backup-YYYYmmddHHMMSS.tsv`

恢复前先用清单里的 sha256 校验，再解压。

## 保留策略

`scripts/prune.sh --gfs` 按「最近 7 天各一份 + 最近 4 个自然周各一份 + 最近 6 个自然月各一份」保留，其余删除；24 小时内创建的 Release 一律不动，最新一份永远保留。时间以 **tag 名里的 UTC 时间戳** 为准（该仓库的 Release `created_at` 字段不可靠）。

失败的运行会留下草稿，`--drafts` 会在每次运行开始时清掉 3 天前的草稿。

## 校验与恢复

```bash
# 1. 下载（分卷要全部下载）
gh release download <tag> -p 'openwrt-packages-*.tar.zst*'

# 2. 合并分卷（如有）
cat openwrt-packages-*.part* > openwrt-packages.tar.zst

# 3. 校验（sha256 见 manifest）
sha256sum openwrt-packages.tar.zst

# 4. 解压 + 校验 + 克隆工作副本
mkdir -p restore
zstd -dc openwrt-packages.tar.zst | tar xf - -C restore
git --git-dir=restore fsck --no-progress
git clone restore openwrt-packages
```

完整的恢复流程（含推送到新仓库、强制覆盖原仓库）见 [恢复教程.md](恢复教程.md)。

## 许可协议

GNU General Public License v3.0，见 [LICENSE](LICENSE)。
