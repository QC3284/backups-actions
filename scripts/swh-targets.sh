#!/usr/bin/env bash
# 重新生成 swh_targets.txt = 当前备份清单（back_ck_url.txt）+ 已删除/已清空/已被封禁的项目。
#
# 现存仓库从 back_ck_url.txt 读取（去掉注释、#shallow 标记、重复项）；
# 已消失的项目写在下面的 GONE 数组里，它们只用于 SWH 快照核查与档案记录，不会进每日备份。
set -Eeuo pipefail
export LC_ALL=C

WORKSPACE=${WORKSPACE:-$(pwd)}
TARGETS=${TARGETS:-$WORKSPACE/swh_targets.txt}
LIST=${LIST:-$WORKSPACE/back_ck_url.txt}

# 已经从 GitHub 消失（404 / 451 / 被清空 / 账号级删除）的项目。
# 加新条目时请同步 docs/backup-targets.md 的「已经消失的项目与现存存档」表。
GONE=(
  # Clash 删库潮
  https://github.com/Dreamacro/clash
  https://github.com/Fndroid/clash_for_windows_pkg
  https://github.com/Kr328/ClashForAndroid
  https://github.com/yichengchen/clashX
  https://github.com/cxfksword/clash-nyanpasu
  https://github.com/Fclash/Fclash
  # 漫画 / 阅读器
  https://github.com/tachiyomiorg/tachiyomi
  https://github.com/tachiyomiorg/tachiyomi-extensions
  https://github.com/TachiyomiSY/TachiyomiSY
  https://github.com/Ehviewer-Overhauled/Ehviewer
  https://github.com/FooIbar/EhViewer
  https://github.com/KurtBestor/Hitomi-Downloader
  https://github.com/tom5079/Pupil
  # 视频 / 影视
  https://github.com/CatVodTVOfficial/TVBoxOSC
  https://github.com/nilaoda/BBDown
  https://github.com/SocialSisterYi/bilibili-API-collect
  https://github.com/leiurayer/downkyi
  # 音乐（版权 DMCA）
  https://github.com/Binaryify/NeteaseCloudMusicApi
  https://github.com/ix64/unlock-music
  https://github.com/unlock-music/unlock-music
  https://github.com/unlock-music/cli
  https://github.com/nondanee/ncmdump
  https://github.com/anonymous5l/ncmdump
  https://github.com/yezihaohao/NeteaseCloudMusic
  https://github.com/wuto/music
  https://github.com/LuRenJiasWorld/NcmDump-Online
  https://github.com/orange1423/ncmDumpGUI
  https://github.com/unlock-music/joox-crypto
  # QQ / 微信
  https://github.com/whitechi73/OpenShamrock
  https://github.com/ichuanyu/icqq
  https://github.com/fuqiuluo/unidbg-fetch-qsign
  https://github.com/SnowLuma/SnowLuma
  https://github.com/Le-niao/Yunzai-Bot
  https://github.com/NapNeko/NapCatQQ
  https://github.com/LC044/WeChatMsg
  https://github.com/xaoyaoo/PyWxDump
  https://github.com/sjzar/chatlog
  https://github.com/ycccccccy/wx_key
  # 网盘 / 规则 / 杂项
  https://github.com/iikira/BaiduPCS-Go
  https://github.com/NAStool/nas-tools
  https://github.com/ConnersHua/Profiles
  https://github.com/lhie1/Rules
  https://github.com/fscarmen/warp
  https://github.com/ReVanced/revanced-patches
  https://github.com/xiaorouji/openwrt-passwall
  https://github.com/xiaorouji/openwrt-passwall2
  # 模拟器（Nintendo 和解 / 逐 fork 清理）
  https://github.com/yuzu-emu/yuzu
  https://github.com/citra-emu/citra
  https://github.com/Ryujinx/Ryujinx
  https://github.com/ryujinx-mirror/ryujinx
  https://github.com/suyu-emu/suyu
  https://github.com/sudachi-emu/sudachi
  https://github.com/Ryubing/Ryujinx
  https://github.com/eden-emulator/Releases
  https://github.com/MeloNX-Emu/MeloNX
  https://github.com/Kenji-NX/Kenji-NX
  https://github.com/ceckbox/Torzu
  https://github.com/citron-neo/CI
  https://github.com/skyline-emu/skyline
  https://github.com/Pomelo-Emu/pomelo-emu.github.io
  # 破解 / 反规避（Spotify、Google PairIP）
  https://github.com/whoeevee/EeveeSpotify
  https://github.com/es3n1n/re-unplayplay
  https://github.com/gamelsz/spotify-premium-apk
  https://github.com/chsbuffer/ReVancedXposed_Spotify
  https://github.com/0x9b42/pairip-protection-remover
  https://github.com/Cyb3r9/RKPairip
  https://github.com/ykapf/youtube-search-fixer
  https://github.com/abbodi1406/KMS_VL_ALL_AIO
  # 弹幕工具（作者删号，继任 hihkm/DanmakuFactory 已入清单）
  https://github.com/hhc0001/DanmakuFactory
)

[[ -f $LIST ]] || { echo "清单不存在: $LIST" >&2; exit 2; }

{
  printf '# Software Heritage 兜底核查目标\n'
  printf '# 自动取 back_ck_url.txt 的全部仓库，外加已经删库/清空、只能靠存档找回的项目。\n'
  printf '# 由 scripts/swh-targets.sh 生成，勿手改；每行一个 URL，# 后为注释。\n\n'

  printf '# ---------- 现存清单 ----------\n'
  grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$LIST" | sort -u

  printf '\n# ---------- 已消失 / 已清空 / 已被封禁 ----------\n'
  printf '%s\n' "${GONE[@]}" | sort -u
} > "$TARGETS"

echo "已生成 $TARGETS：$(grep -c '^https://' "$TARGETS") 个目标（现存 $(grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$LIST" | sort -u | wc -l) + 已消失 ${#GONE[@]}）"
