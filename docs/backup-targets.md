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

- 84 个 GitHub 仓库：82 个全量 mirror（约 **18.6 GB / 次**）+ 2 个浅克隆（约 100 MB）；不含 OpenClash；
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
| QQ·微信·bot | 21 | 腾讯法务重点，2026-11 正在实时崩塌 |
| 下载·影视·漫画·书 | 14 | 侵权投诉高发 |
| 网盘·激活 | 4 | 接口对抗 / 盗版打击 |

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

## 4. 已经消失的项目与现存存档

> 删库之后，GitHub 不会提供任何恢复入口；能指望的只有外部快照。
> SWH = Software Heritage，存的是完整 git 对象但不是 Release 资产；archive.org 的 github.com-* 条目是整仓 bundle，通常滞后 1-2 年。

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
| ReVanced patches | ReVanced/revanced-patches | 2026-03 DMCA，整网 702 仓一并 451 | MorpheApp/morphe-patches（硬分叉）；SWH ff662c98… | SWH 至 2026-03-19 |

## 5. 恢复手册

Software Heritage（有完整 git 历史，优先）：

    curl -s "https://archive.softwareheritage.org/api/1/origin/https://github.com/Dreamacro/clash/get/" | head -c 500
    # 得到 snapshot id 后，用 SWH 网页或 swh 命令行导出为 git bundle：
    # https://archive.softwareheritage.org/browse/snapshot/<snapshot_id>/
    git clone <导出的 .bundle> clash

archive.org（整仓 git bundle，通常滞后 1-2 年）：

    curl -L -o item.zip "https://archive.org/download/github.com-Dreamacro-clash_-_2023-08-06_20-51-37/..."
    git clone ./repo.bundle clash

本仓库的 Release（本流水线自己备的）：

    gh release download <tag> -R QC3284/repo-backup -p 'owner-repo-*.tar.zst*'
    cat owner-repo-*.part* > owner-repo.tar.zst     # 分卷时先合并
    sha256sum owner-repo.tar.zst                    # 与 manifest 比对
    zstd -t owner-repo.tar.zst && mkdir repo && tar -xf owner-repo.tar.zst -C repo
    git --git-dir=repo fsck

GitHub 上的 release 资产（SWH 救不了二进制）：

    gh release download --repo <owner>/<repo> --all-pattern '*'

## 6. 判断仓库是否「已经出事」

- **HTTP 404**：仓库被删或改名。用 gh api repos/owner/repo 区分；
- **HTTP 451 / Repository access blocked**：DMCA 或 TOS 封禁，仓库对象还在、内容被拦截，git clone 会失败。本流水线已把 451 记为失败并写进 report；
- **清空型（更隐蔽）**：仓库页还在，但代码只剩 README/LICENSE（BBDown、bilibili-API-collect、NapCat）。信号是默认分支突然变成 DELETED、size 骤降、releases 被清空；
- **改名型**：旧 URL 靠 301 跳转，某天 301 消失就彻底断线。抓取时记录最终 full_name。

## 7. 暂不纳入

| 仓库 | 原因 |
|---|---|
| vernesong/OpenClash | 单仓 **47.8 GB**，一次 mirror + 压缩需要约 90GB 磁盘，超出 runner 上限；可以按 `#shallow` 方式只存默认分支快照，暂未纳入 |
| Guovin/iptv-api | **全量** mirror 实测约 20.3GB、压缩后仍有 19.5GB（内容为每日生成的 IPTV 播放列表，历史巨大）；已改为 `#shallow` 浅克隆（约 28MB），不再做全量 |
| AlistGo/alist | 2025-06 已被出售给第三方，上游代码可信度存疑；社区继任 OpenListTeam/OpenList 已在清单 |
| v2board/v2board | 2023 年后停更、作者失联，商业机场计费面板，法律风险最高 |
| 各类节点/订阅分发仓 | 纯内容分发，无代码价值，法律风险最高 |
| iptv-org/iptv | 纯文本频道索引，持续维护、无整仓下架先例，重建成本低于备份成本 |
| clashbk/*、clashdownload/* | 下载导航页 / SEO 站，无源码 |
| 已归档死项目 | messense/aliyundrive-webdav、P3TERX/Actions-OpenWrt、takagen99/Box 等 |

## 8. 维护

- **每月复核**：对清单跑一次 gh api repos/owner/repo，任何 404/451 立即处理；451 说明该条目已变成「已删库」；
- **新增条目**：先确认 gh api 返回 200 且 archived=false，估算体积（gh api .size），单仓超过 2GB 需评估；
- **不要只备默认分支**：mihomo 就是反例，必须 --mirror；
- **GitHub fork 不可依赖**：ReVanced 一次通知封了 702 个仓，整片 fork 网络会被端掉。真要长期保存，应定期把 Release 导出到本地 / 对象存储（后续工作）；
- **后续工作**：大仓库分层（每日 / 每周）、非 GitHub 镜像（gitee/gitcode/SWH）纳入流水线、451 自动开 issue 告警。
