# 备份目标说明

> 2026-11-15 重建。旧清单 192 个仓库以 OpenWrt 上游镜像为主（openwrt/immortalwrt 全家桶、固件作者的 fork、已归档仓库），
> 价值低、体积大：13.4TB 历史 Release 里绝大部分是每天重下的同一批上游代码。新目标只有一句话：
> **只备份「可能消失」的东西，并为已经消失的东西找到别的存档。**

## 1. 入选与排除标准

入选（满足其一）：

1. **已发生过删除 / 封禁**：作者删库、平台 DMCA/TOS 封禁（HTTP 451）、改名后旧链接失效；
2. **结构性单点**：单人维护、无组织治理、大陆作者、协议对抗类（QQ/微信）、影视/书源/直播源、高曝光代理工具；
3. **历史不可重建**：仓库一旦删除就再也找不回来（产物能由上游重建的规则库不算）。

排除：

- 上游稳定、有组织治理、几乎不可能被删的仓库（openwrt/immortalwrt 主仓、普通固件 fork）；
- 已经归档（archived）且无替代价值的死项目；
- 纯下载导航页、SEO 站、只有单个安装包的「备份仓」；
- 体积大到当前流水线放不下的仓库（见第 7 节 OpenClash）。

## 2. 当前清单

- 128 个 GitHub 仓库：124 个全量 mirror + 4 个浅克隆（约 130 MB）；不含 OpenClash；
- **实测（2026-11-21）**：一轮 128 仓产出 134 个资产 / 30.8 GB / 20 分钟（6 分片并行），对账零遗漏；
- 每日 04:00 UTC 跑一次；保留策略 7 日 + 4 周 + 6 月；
- 分片按**体积做 LPT 均衡**（scripts/shardmap.sh 预取 GitHub API size，prepare 上传 shardmap 工件），避免某个分片独自卡大仓库；
- 清单行尾标 `#shallow` 的仓库只做 `git clone --mirror --depth 1`（默认分支最新快照，无历史），资产名带 `-shallow` 后缀；它们按体积 0 计算，不占分片负载；
- 单仓实际 mirror 超过 8000MB 会跳过并记失败，防止 20GB 级仓库拖垮整片；
- 每个仓库做完 git fsck、zstd -t、sha256，产物命名 owner-repo-<epoch>.tar.zst，超过 1.8GB 自动分卷；
- manifest 记录 sha256 与源仓库 commit，report.md 写入 Release notes。

类别分布：

| 类别 | 数量 | 说明 |
|---|---|---|
| 代理内核 | 4 | Clash 删库潮的直接继承者 |
| 客户端 | 13 | 单一维护者 + 极高曝光 |
| OpenWrt 插件 | 5 | 作者迁移 / 删库高发区 |
| 订阅·面板·脚本 | 7 | 生态单点 |
| 规则·域名·IP | 16 | 分流生态地基 |
| QQ·微信·bot | 23 | 腾讯法务重点，2026-11 正在实时崩塌 |
| 音乐·音频 | 7 | 版权方直接发函，ncm 解密系列已封 7 仓 |
| 视频·漫画·小说·弹幕 | 31 | B 站律师函、Fakku DMCA、书源类侵权 |
| 网盘·直链·学术·激活 | 9 | 接口对抗 / 盗版打击 |
| 破解·侧载·模拟器 | 13 | Nintendo·Spotify·Google 按 fork 网络批量封禁 |

> 2026-11-21 扩充：84 → 128 仓，新增 44 仓的验证记录见本节末「扩充批次」。

## 3. 重点仓库与证据

| 仓库 | 风险 | 证据 |
|---|---|---|
| **MetaCubeX/mihomo** | 默认分支已被替换 | gh api 显示 description = "A simple Python Pydantic model for Honkai: Star Rail"，language=Python，topics 全是 honkai-star-rail；真正的内核在 Alpha 分支（v1.19.34 仍在发版）。**必须 --mirror 全 refs，只备默认分支会拿到无关项目** |
| **MetaCubeX/ClashMetaForAndroid** | 曾被整库删除 | 2023-11-03 16:16 在删库潮中被删并踢群，之后重建 |
| **MetaCubeX/ClashX.Meta** | 前身已删 | 原 yichengchen/clashX 于 2023-11-03 删除，此仓为继任 |
| **libnyanpasu/clash-nyanpasu** | 前身 404 | 原 cxfksword/clash-nyanpasu 已消失，社区 2023-11-10 另建，历史未完整继承 |
| **chen08209/FlClash** | 前身 404 | 原 Fclash/Fclash 于 2023-11-03 删除，现仓为另址重生 |
| **Z-Siqi/Clash-for-Windows_Chinese** | CFW 唯一活跃分支 | 原 Fndroid/clash_for_windows_pkg 已删；此仓换 mihomo 内核继续维护 |
| **hiddify/hiddify-app** | 改名重定向 | 原名 hiddify-next，旧链接全靠 301 |
| **mihomo-party-org/clash-party** | 改名重定向 | 原名 mihomo-party |
| **Openwrt-Passwall/openwrt-passwall** | 迁组织 | 2026 年从 xiaorouji/ 迁出，旧地址 404 且不跳转；passwall2 同批迁移 |
| **XingYunStar/NapCatQQ** | 本体已被清空 | NapNeko/NapCatQQ 于 2026-11-12 只剩 48 字节 README（"Ending"），本清单备份保留完整历史与 4 个 release 的 fork |
| **DandanLLab/SnowCatQQ** | 上游 404 | SnowLuma 组织仓库 2026-11 消失，此为社区接力端 |
| **LuckyLilliaDev/LuckyLilliaBot** | 改名避风 | 原 LLOneBot/LLOneBot 改名并转移到此账号 |
| **Mrs4s/go-cqhttp** | 作者明示停止 | README："已无力继续维护"；末版 v1.2.0 停在 2023-10 |
| **mamoe/mirai** | README 自述可能删除 | "开发团队可能在任何时间停止更新或删除项目" |
| **keiyoushi/extensions** | DMCA 名单 | 列入 FAKKU 2026-03-23 DMCA 通知；同名单的 Hitomi-Downloader、Hentoid 已被 451 封禁 |
| **mihonapp/mihon** | 前身被封杀 | Tachiyomi 因 Kakao 停终函删库；mihon 续写且保留 2015 起完整历史 |
| **gedoor/legado** | 书源生态 | 阅读 3.0，书源类在大陆法律风险最高；作者已停更数月 |
| **blackmatrix7/ios_rule_script** | 单人维护 + 全格式规则 | 28.6k★，无治理结构，单点断供则下游全挂 |
| **yt-dlp/yt-dlp** | 上游有 DMCA 前科 | youtube-dl 2020-10 被 RIAA 下架（后反转），yt-dlp 为其继任 |
| **MorpheApp/morphe-patches** | 生态唯一活跃上游 | ReVanced/revanced-patches 自 2026-03-12 起 451（Morphe 反诉，GitHub 按 **702 仓网络**整片处理）；Morphe 仓每日更新，本身也在 2026-05 的反诉名单里 |
| **inotia00/revanced-patches** | DMCA 潮前主动归档 | 2026-03-10（Morphe 通知前两天）archived，ReVanced Extended 全系停更，历史只剩这一份 |
| **lyswhut/lx-music-desktop** | 版权方重点 | 55k★，自带多平台音源；同生态 7 个 ncm 解密仓已被腾讯/网易 DMCA 451 |
| **UnblockNeteaseMusic/server** | 绕过版权下架 | 灰歌解锁，直接对抗网易云版权判定，属 dmca 目录常客品类 |
| **manga-download/hakuneko** | DMCA 名单内仍在运行 | 被 2026-03-23 Fakku 通知点名；同批 Hitomi-Downloader、Pupil、EhViewer 已全部 451 |
| **topjohnwu/Magisk** | 单人 + 平台政策 | 64k★ 单人维护，Google Play 政策长期针对，历史不可重建 |
| **massgravel/Microsoft-Activation-Scripts** | 200k★ 单维护者 | 微软 TOS 打击的典型目标；未检索到 DMCA 记录，但体量与性质决定它随时会消失 |
| **LSPosed/LSPosed** | 反检测底座 | 对抗 Play Integrity，Xposed 生态核心；上游一断整个模块生态失效 |

### 3.1 2026-11-21 扩充批次（84 → 128）

新增 44 仓全部在当日用 `gh api repos/<owner>/<repo>` 复核存在、未封禁（scripts/check-list.sh 可重跑）。
选取依据是「已经发生过同类封禁」而不是「热门」：

| 批次 | 仓库 | 依据 |
|---|---|---|
| 音乐 | lx-music-desktop / lx-music-mobile、MusicFree(+Plugins)、YesPlayMusic、listen1_desktop、UnblockNeteaseMusic/server | ncm 解密已封 7 仓（腾讯 2022-11、网易 2021-10）；listen1 在 2017 被 QQ 音乐 DMCA 过一次 |
| 视频 | Bilibili-Evolved、Bili23-Downloader、yutto、Douyin_TikTok_Download_API、NewPipe、SmartTube、you-get、lux、invidious | B 站 2026 对 bilibili-API-collect、downkyi 发律师函；YouTube 侧有 youtube-dl 先例；抖音接口逆向 |
| 漫画 | hakuneko、Suwayomi-Server、Kotatsu | Fakku 2026-03-23 一次性封 4 仓；Kotatsu 已因 Kakao 压力归档 |
| 小说 | so-novel、Tomato-Novel-Downloader、work_crawler | 爬正版网文站，书源类侵权投诉高发 |
| 弹幕 | hihkm/DanmakuFactory、danmaku2ass | 前身 hhc0001/DanmakuFactory 已 404（作者删号） |
| 网盘·学术 | LinkSwift、pansou、zlib、zotero-scihub、bookget | 直链解析 / 影子图书馆，DMCA 高发品类 |
| 微信 | WeChatRobot、wxhelper | 微信 hook 与协议逆向，腾讯法务重点（WeChatMsg 42k★ 已清空、PyWxDump 2025-10 收律师函自删） |
| 破解·模拟器 | morphe-patches/manager、inotia00/revanced-patches、revanced-manager、ArchiveTune、GmsCore、strato、Magisk、KernelSU、LSPosed、Shizuku、TrollStore、MAS | Nintendo 2024 起清理模拟器（yuzu 240 万美元和解）、Spotify 2025-08 起清理破解客户端、Google 2025-06 起以**反规避**清扫 PairIP 脱壳 |

## 4. 已经消失的项目与现存存档

> 删库之后，GitHub 不会提供任何恢复入口；能指望的只有外部快照。
> SWH = Software Heritage，存的是完整 git 对象但不是 Release 资产；archive.org 的 github.com-* 条目是整仓 bundle，通常滞后 1-2 年。
>
> 自动化：`scripts/swh.sh` 每天检查 swh_targets.txt 里的仓库在 SWH 的最新快照，结果写入 [swh-snapshots.tsv](swh-snapshots.tsv)（含 snapshot id 与抓取日期）。下表是人工整理的背景资料，两者的 snapshot id 应一致。

| 项目 | 原仓库 | 消失时间 / 原因 | 现存备份 | 完整性 |
|---|---|---|---|---|
| Clash 内核 | Dreamacro/clash | 2023-11-02 作者清空 | SWH snapshot c279118e65d67d3e6202079ba00fca824d456903（2023-10-16，41 次全量抓取）；archive.org item github.com-Dreamacro-clash_-_2023-08-06_20-51-37 | 至删除前完整 |
| Clash for Windows | Fndroid/clash_for_windows_pkg | 2023-11-02 作者停更删库 | SWH 296e3c4ab81d640fbea2c6082a118a3fa79b96d4；archive.org item clash_for_windows_pkg（0.20.39 全平台安装包）；GitHub 仅剩二进制备份仓 | 源码到 2023-10 |
| Clash for Android | Kr328/ClashForAndroid | 2023-11-03 | SWH f6fe23f035d6c1bd54a38674f5b911fde4b76770；BackupTime/ClashForAndroid | 完整 |
| ClashX (macOS) | yichengchen/clashX | 2023-11-03 | SWH（最后全量 2023-11-03）；继任 MetaCubeX/ClashX.Meta | 完整 |
| Clash Nyanpasu 原版 | cxfksword/clash-nyanpasu | 404，SWH 无快照 | 仅 libnyanpasu/clash-nyanpasu（新仓） | 历史丢失 |
| FlClash 原版 | Fclash/Fclash | 2023-11-03 | 无；现 chen08209/FlClash 另址重生 | 历史丢失 |
| Tachiyomi | tachiyomiorg/tachiyomi | 2024-01 Kakao 停终函 | mihonapp/mihon（含 2015 起全史）；SWH 2024-01-14 快照 | 完整（Release APK 除外） |
| TachiyomiSY | TachiyomiSY/TachiyomiSY | 随 Tachiyomi 消失 | jobobby04/TachiyomiSYPreview | 仅预览仓 |
| TVBoxOSC | CatVodTVOfficial/TVBoxOSC | 404，无说明 | j4Uq/TVBoxOSC（代码延续）；SWH 无全量快照 | 历史不全 |
| BBDown | nilaoda/BBDown | 2026-05 清空并改名 DELETED | aliveranme/BBDown（真 fork，全源码，仍活跃） | 完整 |
| bilibili-API-collect | SocialSisterYi/bilibili-API-collect | 2026-01 收 B 站律师函，清空代码 | pskdje/bilibili-API-collect（全量 fork，已归档）；BACNext/BACNext | fork 完整 |
| OpenShamrock | whitechi73/OpenShamrock | 账号级删除（2025-04 之后） | TimeRainStarSky/OpenShamrock；gitcode.com/gh_mirrors/op/OpenShamrock | 完整 |
| icqq | ichuanyu/icqq | 账号级删除 | wuliya336/icqq（源码级）；icqqjs/packages（半删库状态） | 完整 |
| unidbg-fetch-qsign | fuqiuluo/unidbg-fetch-qsign | 404（作者仅删此库） | CrackerCat/unidbg-fetch-qsign（含 txlib 签名库）；MarindaCloud、Linxiaoyaa 同名仓 | 完整 |
| NapCat 本体 | NapNeko/NapCatQQ | 2026-11-12 掏空 | XingYunStar/NapCatQQ（375MB，4 个 release）；Clannad47/NapCatQQ | 完整 |
| SnowLuma | SnowLuma/SnowLuma | 2026-11 组织仓库 404 | TomyJan/SnowLuma（65MB） | 截至 v2.4.2 |
| Yunzai-Bot（云崽） | Le-niao/Yunzai-Bot 等 | 2023-02 被 GitHub TOS 封禁（403，block.reason=tos） | gitee.com/Le-niao/Yunzai-Bot（封禁前最后状态）；gitee.com/TimeRainStarSky/Yunzai；yoimiya-kokomi/Miao-Yunzai | 完整（在 Gitee） |
| ConnersHua 规则 | ConnersHua/Profiles | 2020 前后删库 | xuanyuanyaoming/ConnersHua（98 commits 到 2020-10） | 接近删除时点 |
| lhie1 规则 | lhie1/Rules | 2022-01 被 TOS 封禁（403） | 120910266/lhie1（2021-07） | 缺最后半年 |
| BaiduPCS-Go | iikira/BaiduPCS-Go | 作者注销删库 | qjfoidnh/BaiduPCS-Go（本清单已收录） | 部分（SWH 停在 2018） |
| WARP 脚本 | fscarmen/warp | 2023-09 被 ToS 封禁 | gitlab.com/fscarmen/warp（完整迁移）；fscarmen/warp-sh | 完整 |
| ReVanced patches | ReVanced/revanced-patches | 2026-03-12 Morphe 反诉 DMCA，GitHub 按 702 仓网络整片 451 | MorpheApp/morphe-patches（本清单已收录）；SWH 5ebe03cbba15108bb06010756cd30e58aa797f96 | SWH 至 2026-03-19 |
| yuzu（Switch） | yuzu-emu/yuzu | 2024-03-04 与 Nintendo 达成 240 万美元和解后删库 | SWH 3b87cb218642dd4be47dc8c7b6aa8f5ffbf043c4；镜像 yuzu-mirror/yuzu-mod-archive | 至删除前完整 |
| Citra（3DS） | citra-emu/citra | 2024-03-04 同日关停 | SWH 0861123bfb4f7d3797a94506bd00bc6f72f94eb5 | 完整 |
| Ryujinx（Switch） | Ryujinx/Ryujinx | 2024-10-01 Nintendo 介入后停更删库 | SWH 7a99a06e4449d9f03e4d41f1b601ac08d6f40bd3；续作 Ryubing/Ryujinx 2025-03-13 亦 404（SWH d5bbdc0c2b82f6d1ce97625fcf0909d823c5c581） | 完整 |
| Suyu（Switch） | suyu-emu/suyu | 2026-08-17 451（单日 7 份通知、400+ 仓） | SWH 3075696c22babeb9af75bbb426ede61b8b8a9fec；suyu-emu/suyu-v0.0.4 镜像 | 完整 |
| Sudachi（Switch） | sudachi-emu/sudachi | 2026-02-12 Nintendo 名单，404 | SWH 3c2acef743628c308370d5e79ea31fb6d6c86dc6 | 完整 |
| EeveeSpotify | whoeevee/EeveeSpotify | 2025-08-14 Spotify DMCA，451 | SWH 03c01a038087067f543e0305aeb9eb51ae696509；续作 SideloadLabs/EeveeSpotifyReincarnated、whoeevee/EeveeSpotifyReborn | 完整 |
| re-unplayplay | es3n1n/re-unplayplay | 2025-03-20 Spotify DMCA，451 | fork cycyrild/another-unplayplay | 完整 |
| PairIP 脱壳 | 0x9b42/pairip-protection-remover | 2025-06-24 Google **反规避**主张（非版权）451，同批 18 fork | 无 SWH；后继 ahmedmani/pairipfix、Solaree/pairipcore | 历史丢失 |
| 微信聊天记录导出 | LC044/WeChatMsg | 42k★，清空 | 仅第三方 fork | 需从 fork 取 |
| 微信数据库解密 | xaoyaoo/PyWxDump、sjzar/chatlog | 2025-10-20 同日收律师函自删 | 各 fork | 部分 |
| 微信 key 提取 | ycccccccy/wx_key | 2026-06-30 DMCA 自清空 | 无稳定存档 | 丢失 |
| NAStool | NAStool/nas-tools | 2023-05 覆盖式删库 | 社区 fork（MoviePilot 等） | 历史丢失 |
| KMS 激活 | abbodi1406/KMS_VL_ALL_AIO | 2024 后 404 | SWH eba50a28a01a35c30ba9e2526d6487ac4b177149（2024-10-18） | 完整 |

## 5. 恢复手册

本仓库自己备的（优先，产物可校验；一键：`bash scripts/restore.sh <owner/repo>`）：

    gh release download <tag> -R QC3284/repo-backup -p '<owner>-<repo>-*' -D ./dl
    # manifest-<tag>.tsv 里查该仓库的 asset / bytes / sha256（分卷时每个 part 一行）
    awk -F'\t' '$1=="owner/repo"' manifest-<tag>.tsv
    # 单卷：sha256sum 校验；分卷：逐卷校验后按名字排序合并（合并名 = 去掉 .partNNN）
    cat dl/owner-repo-<epoch>.tar.zst.part* > dl/owner-repo-<epoch>.tar.zst
    zstd -t dl/owner-repo-<epoch>.tar.zst
    mkdir repo && zstd -dc dl/owner-repo-<epoch>.tar.zst | tar -xf - -C repo
    git --git-dir=repo fsck

SWH（完整 git 历史，删库后首选；细节见 [恢复教程.md](../恢复教程.md) 第 8.1 节）：

    # 1) 找 snapshot（UA 必须自定义，默认 curl UA 会 403；限流 120 次/小时）
    curl -s -A 'repo-backup/1.0' \
      "https://archive.softwareheritage.org/api/1/origin/https%3A%2F%2Fgithub.com%2FDreamacro%2Fclash/visits/?limit=100" \
      | jq -r '[.[] | select(.snapshot != null)][0].snapshot'
    # 2) 触发打包（POST 路径带 swhid），再轮询到 status=done
    curl -s -A 'repo-backup/1.0' -X POST "https://archive.softwareheritage.org/api/1/vault/git-bare/swh:1:snp:$SNAP/"
    curl -s -A 'repo-backup/1.0' "https://archive.softwareheritage.org/api/1/vault/git-bare/swh:1:snp:$SNAP/"
    # 3) 下载裸仓库 tar，解出的目录名带冒号（Windows 上先改名）
    curl -L -A 'repo-backup/1.0' -o swh.tar "https://archive.softwareheritage.org/api/1/vault/git-bare/swh:1:snp:$SNAP/raw/"
    tar -xf swh.tar && mv "swh:1:snp:$SNAP.git" repo.git && git --git-dir=repo.git fsck

或直接 `bash scripts/restore.sh swh Dreamacro/clash`（自动查快照、cooking、下载、fsck）。

archive.org（整仓 bundle，通常滞后 1-2 年）：

    curl -L -o item.zip "https://archive.org/download/<identifier>/<filename>"
    git clone ./repo.bundle clash

GitHub 上游自己的 release 资产（SWH 救不了二进制）：

    gh release download --repo <owner>/<repo> --pattern '*'

## 6. 判断仓库是否「已经出事」

- **HTTP 404**：仓库被删或改名。用 gh api repos/owner/repo 区分；
- **HTTP 451 / Repository access blocked**：DMCA 或 TOS 封禁，仓库对象还在、内容被拦截，git clone 会失败。本流水线已把 451 记为失败并写进 report；
- **清空型（更隐蔽）**：仓库页还在，但代码只剩 README/LICENSE（BBDown、bilibili-API-collect、NapCat）。信号是默认分支突然变成 DELETED、size 骤降、releases 被清空；
- **改名型**：旧 URL 靠 301 跳转，某天 301 消失就彻底断线。抓取时记录最终 full_name。

## 7. 暂不纳入

| 仓库 | 原因 |
|---|---|
| vernesong/OpenClash | 单仓 **47.8 GB**，一次 mirror + 压缩需要约 90GB 磁盘，超出 runner 上限；可以按 `#shallow` 方式只存默认分支快照，暂未纳入 |
| Guovin/iptv-api（全量） | **全量** mirror 实测约 20.3GB、压缩后仍有 19.5GB（内容为每日生成的 IPTV 播放列表，历史巨大）；已改为 `#shallow` 浅克隆（约 28MB），不再做全量 |
| AlistGo/alist | 2025-06 已被出售给第三方，上游代码可信度存疑；社区继任 OpenListTeam/OpenList 已在清单 |
| v2board/v2board | 2023 年后停更、作者失联，商业机场计费面板，法律风险最高 |
| 各类节点/订阅分发仓 | 纯内容分发，无代码价值，法律风险最高 |
| iptv-org/iptv | 纯文本频道索引，持续维护、无整仓下架先例，重建成本低于备份成本 |
| clashbk/*、clashdownload/* | 下载导航页 / SEO 站，无源码 |
| 已归档死项目 | messense/aliyundrive-webdav、P3TERX/Actions-OpenWrt、takagen99/Box 等（本清单里收录的 5 个归档仓属于「历史只剩这一份」，如 inotia00/revanced-patches、Kotatsu） |
| 大型成熟模拟器 | Dolphin（564MB）、PCSX2（345MB）、RPCS3（162MB）等：组织治理稳定、无 DMCA 先例，只备份 Nintendo/Sony 名单上确实被打过的项目 |
| Sideloadly | 闭源、无 GitHub 仓库（仅 sideloadly.io），不在可备份范围 |
| 纯下载器 | Motrix、AriaNg、youtube-dl-gui 等：功能通用、无直接被点名记录，重建成本低于备份成本 |

## 8. 维护

- **每月复核**：`bash scripts/check-list.sh` 一次跑完 128 仓（gh api 并发 8，输出 repo/status/size/archived/pushed_at/stars），任何 404/451 立即处理；451 说明该条目已变成「已删库」；
- **新增条目**：先确认 gh api 返回 200，估算体积（gh api .size），单仓超过 2GB 需评估；清单改完跑 `bash scripts/swh-targets.sh` 重新生成 swh_targets.txt（现存清单 + 已删库合并去重），否则 SWH 核查会漏掉新条目；
- **不要只备默认分支**：mihomo 就是反例，必须 --mirror；
- **GitHub fork 不可依赖**：ReVanced 一次通知封了 702 个仓，整片 fork 网络会被端掉。真要长期保存，应定期把 Release 导出到本地 / 对象存储（后续工作）；
- **SWH 核查分片**：swh_targets.txt 现有 197 个目标（128 现存 + 69 已消失），SWH 限流 120 次/小时，swh.yml 用 `SWH_SHARDS=3` 按「一年中的第几天」轮转，每次只查 1/3；脚本会把本次结果与旧表合并，不会丢失其它分片的数据；
- **后续工作**：Release 资产异地导出（SWH 不存二进制）、非 GitHub 镜像（gitee/gitcode）纳入流水线。
