#!/bin/bash
# ======================================================================
# install-tencent-meeting.sh — 一键安装腾讯会议（Linux 官方 deb）
#
# 功能：
#   1) 从腾讯官方 CDN 下载 deb 包到 ~/Downloads
#   2) dpkg 安装（自动注册桌面菜单项 /usr/share/applications/wemeetapp.desktop）
#   3) 校验安装结果（dpkg -l / 主程序 / 菜单项）
#
# 适用：Ubuntu 24.04 x86_64（官方另有 arm64 / loongarch64 包，见 docs/27）
# 对应文档：docs/27-工具-腾讯会议.md
#
# ⚠️ 升级注意：下载 URL 的 /cos/<hash>/ 段与版本号耦合且无法从版本号推导，
#    升级时必须同时改 WEMEET_VERSION 和 WEMEET_COS_HASH（重新抓直链的方法见 docs/27 Q2）。
#
# 备注：
#   - 官方 deb 不注册 /usr/bin 命令，命令行启动用 /opt/wemeet/wemeetapp.sh
#   - 卸载：sudo apt remove --purge wemeet
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

# 腾讯会议版本与下载地址（x86_64，2026-09-10 官网实测）
# 官网下载页（直链由页面 JS 动态生成，抓取方法见 docs/27）：
#   https://meeting.tencent.com/download/
WEMEET_VERSION="${WEMEET_VERSION:-3.26.10.401}"
WEMEET_COS_HASH="${WEMEET_COS_HASH:-72e0e0023e1d1e6d4123fba28821aea1}"
WEMEET_URL="https://updatecdn.meeting.qq.com/cos/${WEMEET_COS_HASH}/TencentMeeting_0300000000_${WEMEET_VERSION}_x86_64_default.publish.officialwebsite.deb"
DEB_FILE="${DOWNLOAD_DIR}/wemeet-${WEMEET_VERSION}-x86_64.deb"

# ---------- 步骤 1：下载 deb 包 ----------
do_download() {
    title "步骤 1/3 · 下载腾讯会议 ${WEMEET_VERSION} (Linux x86_64)"
    mkdir -p "$DOWNLOAD_DIR"

    if [ -f "$DEB_FILE" ]; then
        warn "已存在 $DEB_FILE，跳过下载（如需重下请先删除）"
        return 0
    fi

    info "下载中（约 190M，请稍候）..."
    info "URL: $WEMEET_URL"
    # -f: HTTP 错误返回非零；-L: 跟随重定向；-A: 模拟浏览器绕过简单 UA 校验
    curl -fL -o "$DEB_FILE" "$WEMEET_URL" \
        --connect-timeout 30 --max-time 570 \
        -A "Mozilla/5.0" || {
        err "下载失败，请检查网络，或按 docs/27 Q2 重新抓取官网直链（版本升级后旧 hash 会失效）"
        rm -f "$DEB_FILE"
        exit 1
    }
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$DEB_FILE" 2>/dev/null || true
    ok "已下载 $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
}

# ---------- 步骤 2：dpkg 安装 ----------
do_install() {
    need_root
    title "步骤 2/3 · dpkg 安装"
    [ -f "$DEB_FILE" ] || { err "找不到 $DEB_FILE，请先执行 download"; exit 1; }

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
    installed_ver=$(dpkg -l wemeet 2>/dev/null | awk '/^ii/{print $3}')
    if [ -n "$installed_ver" ]; then
        ok "dpkg 已登记：wemeet = $installed_ver"
    else
        err "dpkg 未找到 wemeet，安装可能失败"
        exit 1
    fi

    if [ -x /opt/wemeet/bin/wemeetapp ]; then
        ok "主程序存在：/opt/wemeet/bin/wemeetapp"
    else
        err "/opt/wemeet/bin/wemeetapp 未生成，请检查安装日志"
        exit 1
    fi

    if [ -f /usr/share/applications/wemeetapp.desktop ]; then
        ok "桌面菜单项已注册：/usr/share/applications/wemeetapp.desktop"
        ok "按 Super 键搜索 \"腾讯会议 / WemeetApp\" 即可启动"
    fi

    warn "官方 deb 不注册 /usr/bin 命令，命令行启动用：/opt/wemeet/wemeetapp.sh"
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载腾讯会议"
    apt remove --purge -y wemeet || true
    rm -f "$DEB_FILE"
    info "已清理 deb 包：$DEB_FILE"
    ok "卸载完成（用户数据 ~/.local/share/wemeetapp 如需彻底清理请手动删除，见 docs/27 Q3）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→校验）：
  download  仅下载 deb 包到 ~/Downloads（不需 sudo）
  install   仅 dpkg 安装（需 sudo）
  verify    仅校验安装结果
  remove    卸载 wemeet 并清理 deb 包（需 sudo）
  all       依次执行 download → install → verify（推荐）
  help      显示本帮助

环境变量：
  WEMEET_VERSION   指定版本号，默认 3.26.10.401
  WEMEET_COS_HASH  指定 CDN hash 段（与版本耦合，升级时必改，抓法见 docs/27 Q2）

示例：
  sudo bash $0                    # 一键安装
  bash $0 download                # 仅下载
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
