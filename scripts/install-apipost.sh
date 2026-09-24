#!/bin/bash
# ======================================================================
# install-apipost.sh — 一键安装 ApiPost（接口调试 / 文档 / Mock / 压测）
#
# 功能：
#   1) 从官网下载 Linux AMD(x64) deb 包到 ~/Downloads
#   2) dpkg 安装（自动注册桌面菜单项 /usr/share/applications/apipost.desktop）
#   3) 校验安装结果（dpkg -l / which apipost）
#
# 适用：Ubuntu 24.04 x86_64
# 对应文档：docs/17-工具-ApiPost接口调试.md
#
# 备注：
#   - deb 包由官方注册了 GNOME 菜单项，应用列表直接可见，无需另建 .desktop
#   - 卸载：sudo apt remove --purge apipost
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-java-maven.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
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

# ApiPost 版本与下载地址（AMD/x64）
# 官网下载页：https://www.apipost.cn/download.html
APIPOST_VERSION="${APIPOST_VERSION:-8.2.7}"
APIPOST_URL="https://www.apipost.cn/dl.php?client=Linux&arch=x64&version=${APIPOST_VERSION}"
DEB_FILE="${DOWNLOAD_DIR}/apipost-${APIPOST_VERSION}.deb"

# ---------- 步骤 1：下载 deb 包 ----------
do_download() {
    title "步骤 1/3 · 下载 ApiPost ${APIPOST_VERSION} (Linux x64)"
    mkdir -p "$DOWNLOAD_DIR"

    if [ -f "$DEB_FILE" ]; then
        warn "已存在 $DEB_FILE，跳过下载（如需重下请先删除）"
        return 0
    fi

    info "下载中（约 80M，请稍候）..."
    info "URL: $APIPOST_URL"
    # -f: HTTP 错误返回非零；-L: 跟随重定向；-A: 模拟浏览器绕过简单 UA 校验
    curl -fL -o "$DEB_FILE" "$APIPOST_URL" \
        --connect-timeout 30 --max-time 300 \
        -A "Mozilla/5.0" || {
        err "下载失败，请检查网络或手动到 https://www.apipost.cn/download.html 下载"
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
    installed_ver=$(dpkg -l apipost 2>/dev/null | awk '/^ii/{print $3}')
    if [ -n "$installed_ver" ]; then
        ok "dpkg 已登记：apipost = $installed_ver"
    else
        err "dpkg 未找到 apipost，安装可能失败"
        exit 1
    fi

    if command -v apipost >/dev/null 2>&1; then
        ok "命令可用：$(which apipost) → $(readlink -f "$(which apipost)")"
    else
        err "/usr/bin/apipost 未生成，请检查安装日志"
        exit 1
    fi

    if [ -f /usr/share/applications/apipost.desktop ]; then
        ok "桌面菜单项已注册：/usr/share/applications/apipost.desktop"
        ok "按 Super 键搜索 \"Apipost\" 即可启动"
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载 ApiPost"
    apt remove --purge -y apipost || true
    rm -f "$DEB_FILE"
    info "已清理 deb 包：$DEB_FILE"
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→校验）：
  download  仅下载 deb 包到 ~/Downloads（不需 sudo）
  install   仅 dpkg 安装（需 sudo）
  verify    仅校验安装结果
  remove    卸载 apipost 并清理 deb 包（需 sudo）
  all       依次执行 download → install → verify（推荐）
  help      显示本帮助

环境变量：
  APIPOST_VERSION  指定版本号，默认 8.2.7

示例：
  sudo bash $0                    # 一键安装
  bash $0 download                # 仅下载
  sudo APIPOST_VERSION=8.2.7 bash $0 all
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
