#!/bin/bash
# ======================================================================
# install-feishu.sh — 一键安装飞书 Linux 桌面版（官方 deb）
#
# 功能：
#   1) 调飞书官网包信息接口，取最新版签名直链（运行时获取，升级免改脚本）
#   2) 下载 deb 包到 ~/Downloads 并做 md5 完整性校验
#   3) dpkg 安装（自动注册 /usr/bin/bytedance-feishu 与桌面菜单项）
#   4) 校验安装结果（dpkg / 命令 / 菜单项）
#
# 适用：Ubuntu 24.04 x86_64（其他架构见 FEISHU_PLATFORM，docs/32）
# 对应文档：docs/32-工具-飞书.md
#
# ✅ 与腾讯会议方案的区别（docs/27）：飞书官网有稳定的包信息接口
#    /api/package_info，每次运行现取带签名的短时效直链（几小时过期），
#    版本升级后脚本零改动——不存在"版本耦合 hash 重抓"问题。
#
# 备注：
#   - 包名 bytedance-feishu-stable；主程序落 /opt/bytedance/feishu
#   - 卸载：sudo bash $0 remove
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-java-maven.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "安装 deb 包需要 root 权限。请用 sudo 运行："
        echo "    sudo bash $0"
        exit 1
    fi
}

# 下载用真实用户的家目录（脚本可能被 sudo 调用）
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
DOWNLOAD_DIR="${REAL_HOME}/Downloads"

# 包信息接口（2026-09-22 官网实测；直链由该接口动态签发，勿固化到脚本）
FEISHU_API="https://www.feishu.cn/api/package_info"
# platform 对照（接口返回 version_number 前缀可自查）：
#   10=Linux-x64-deb（默认） 11=Linux-x64-rpm 12/13=Linux-arm64-deb/rpm
#   14/15=Linux-mips64el(龙芯) 9=macOS-Apple 1=iOS
FEISHU_PLATFORM="${FEISHU_PLATFORM:-10}"
PKG_NAME="bytedance-feishu-stable"

# ---------- 取包信息：url / version / md5 ----------
# 输出一行 "url|version|md5"（管道分隔；URL 中不含 | ，安全）
# 注意：不能输出 KEY=VALUE 供 eval——直链含 & % 会被 shell 解释，
# 也不能在 shell 单引号包裹的 python 代码里再用单引号（截断字符串）
fetch_info() {
    local resp
    resp=$(curl -s --max-time 20 "${FEISHU_API}?platform=${FEISHU_PLATFORM}" \
        -H 'User-Agent: Mozilla/5.0' \
        -H "Referer: https://www.feishu.cn/download") || {
        err "包信息接口请求失败：${FEISHU_API}?platform=${FEISHU_PLATFORM}"
        exit 1
    }
    # 直链含 & 与转义，必须用 python3 解析 JSON，不能 grep/sed 切
    if ! command -v python3 >/dev/null; then
        err "需要 python3 解析接口 JSON（Ubuntu 24.04 自带）"; exit 1
    fi
    python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
    code = d.get("code")
    assert code == 0, "接口返回非0: code=%s msg=%s" % (code, d.get("message"))
    data = d["data"]
    link = data["download_link"]
    ver = data["version_number"]
    md5 = data.get("hash", "")
    assert link.startswith("http"), "download_link 异常"
    print("|".join([link, ver, md5]))
except Exception as e:
    print("__PARSE_FAIL__|%s" % e, end="")
' "$resp"
}

# ---------- 步骤 1：下载 deb 包 ----------
do_download() {
    title "步骤 1/3 · 取链接并下载飞书 Linux 版（platform=${FEISHU_PLATFORM}）"
    mkdir -p "$DOWNLOAD_DIR"

    info "调包信息接口取签名直链（短时效，即取即用）..."
    local line
    line=$(fetch_info)
    case "$line" in
        "")                err "接口返回为空，请稍后重试或检查网络"; exit 1 ;;
        __PARSE_FAIL__\|*) err "接口返回解析失败：$line"; exit 1 ;;
    esac
    DOWNLOAD_URL="${line%%|*}"
    local rest="${line#*|}"
    VERSION="${rest%%|*}"
    MD5="${rest##*|}"
    ok "最新版本：$VERSION"

    DEB_FILE="${DOWNLOAD_DIR}/$(basename "${DOWNLOAD_URL%%\?*}")"   # 去掉 ?签名 段取文件名
    if [ -f "$DEB_FILE" ]; then
        warn "已存在 $DEB_FILE，跳过下载（如需重下请先删除）"
    else
        info "下载中（约 340M，请稍候）..."
        curl -fL -o "$DEB_FILE" "$DOWNLOAD_URL" \
            --connect-timeout 30 --max-time 570 \
            -A "Mozilla/5.0" || {
            err "下载失败，请检查网络后重试（直链签名几小时过期，重跑本命令会自动取新链）"
            rm -f "$DEB_FILE"
            exit 1
        }
        chown "$REAL_USER":"$(id -g "$REAL_USER")" "$DEB_FILE" 2>/dev/null || true
    fi
    ok "已下载 $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"

    # md5 完整性校验（接口 hash 字段即文件 md5，2026-09-22 实测吻合）
    if [ -n "${MD5:-}" ]; then
        local actual
        actual=$(md5sum "$DEB_FILE" | awk '{print $1}')
        if [ "$(echo "$actual" | tr 'A-F' 'a-f')" = "$(echo "$MD5" | tr 'A-F' 'a-f')" ]; then
            ok "md5 校验通过：$actual"
        else
            err "md5 不匹配！期望 $MD5，实际 $actual"
            err "文件可能损坏，已删除，请重跑下载"
            rm -f "$DEB_FILE"
            exit 1
        fi
    fi
}

# ---------- 步骤 2：dpkg 安装 ----------
do_install() {
    need_root
    title "步骤 2/3 · dpkg 安装"
    [ -f "${DEB_FILE:-}" ] || { err "找不到 deb 文件，请先执行 download"; exit 1; }

    info "dpkg -i $DEB_FILE"
    if ! dpkg -i "$DEB_FILE"; then
        warn "dpkg 报告依赖问题，尝试 apt -f 修复..."
        apt-get install -f -y || { err "依赖修复失败，请查看上方输出"; exit 1; }
    fi
    ok "安装完成"
}

# ---------- 步骤 3：校验 ----------
do_verify() {
    title "步骤 3/3 · 安装校验"
    local installed_ver
    installed_ver=$(dpkg -l "$PKG_NAME" 2>/dev/null | awk '/^ii/{print $3}')
    if [ -n "$installed_ver" ]; then
        ok "dpkg 已登记：$PKG_NAME = $installed_ver"
    else
        err "dpkg 未找到 $PKG_NAME，安装可能失败"
        exit 1
    fi

    if [ -x /usr/bin/bytedance-feishu-stable ]; then
        ok "命令已注册：/usr/bin/bytedance-feishu-stable（另有 alternatives 别名 bytedance-feishu）"
    else
        err "/usr/bin/bytedance-feishu-stable 未生成，请检查安装日志"
        exit 1
    fi

    if [ -f /usr/share/applications/bytedance-feishu.desktop ]; then
        ok "桌面菜单项已注册：/usr/share/applications/bytedance-feishu.desktop"
        ok "按 Super 键搜索 \"飞书 / Feishu\" 即可启动"
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载飞书"
    apt remove --purge -y "$PKG_NAME" || true
    rm -f "${DEB_FILE:-$DOWNLOAD_DIR"/Feishu-linux"*.deb}"
    info "已清理 deb 包"
    ok "卸载完成（用户数据 ~/.config/LarkShell 如需彻底清理请手动删除，见 docs/32）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→校验）：
  download  仅取链+下载+md5 校验到 ~/Downloads（不需 sudo）
  install   仅 dpkg 安装（需 sudo）
  verify    仅校验安装结果
  remove    卸载 $PKG_NAME 并清理 deb 包（需 sudo）
  all       依次执行 download → install → verify（推荐）
  help      显示本帮助

环境变量：
  FEISHU_PLATFORM  接口平台参数，默认 10（Linux-x64-deb）
                   11=x64-rpm  12=arm64-deb  13=arm64-rpm  14/15=龙芯 mips64el

示例：
  sudo bash $0                          # 一键安装最新版
  FEISHU_PLATFORM=12 bash $0 download   # 仅下载 arm64 deb
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        download) do_download ;;
        install)  do_download; do_install ;;
        verify)   do_verify ;;
        remove)   do_remove ;;
        all)      do_download; do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
