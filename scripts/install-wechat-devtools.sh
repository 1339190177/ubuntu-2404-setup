#!/bin/bash
# ======================================================================
# install-wechat-devtools.sh — 一键安装微信开发者工具 Linux 移植版
#
# 功能：
#   1) 经 gh-proxy.com 镜像下载社区预构建 deb 到 ~/Downloads
#      （直连 github.com 本机不通，见 docs/30 Q1）
#   2) dpkg 安装（自包含包，无外部依赖；自动注册桌面菜单项）
#   3) 创建 wechat-devtools / wechat-devtools-cli 命令软链
#   4) 校验安装结果（dpkg -l / 安装路径 / 菜单项 / 软链）
#
# 适用：Ubuntu 24.04 x86_64
# 对应文档：docs/30-工具-微信开发者工具.md
#
# ⚠️ 非官方包：微信开发者工具官方仅提供 Windows/macOS 版，
#    本脚本安装的是社区移植版 msojocs/wechat-web-devtools-linux。
#
# 备注：
#   - 升级：sudo WXDT_VERSION=<新版本> bash $0 all（覆盖安装不清登录态）
#   - CLI 使用前置：GUI 设置→安全设置→开启服务端口
#   - 卸载：sudo bash $0 remove
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-tencent-meeting.sh 一致） ----------
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

# 版本与下载地址（2026-09-15 GitHub Releases 实测）
# 上游 Releases：https://github.com/msojocs/wechat-web-devtools-linux/releases
# tag 命名 v<版本>-1，资产名 io.github.msojocs.wechat-devtools-linux_<版本>_amd64.deb
PKG_NAME="io.github.msojocs.wechat-devtools-linux"
WXDT_VERSION="${WXDT_VERSION:-2.02.2608070-1}"
GH_PATH="msojocs/wechat-web-devtools-linux/releases/download/v${WXDT_VERSION}/${PKG_NAME}_${WXDT_VERSION}_amd64.deb"
# 直连 github.com 本机超时，默认走镜像；GH_PROXY= 置空可强制直连（需代理）
GH_PROXY="${GH_PROXY-https://gh-proxy.com/}"
DEB_FILE="${DOWNLOAD_DIR}/${PKG_NAME}_${WXDT_VERSION}_amd64.deb"

APP_DIR="/opt/apps/${PKG_NAME}"

# ---------- 步骤 1：下载 deb 包 ----------
do_download() {
    title "步骤 1/4 · 下载微信开发者工具 ${WXDT_VERSION} (Linux x86_64)"
    mkdir -p "$DOWNLOAD_DIR"

    if [ -f "$DEB_FILE" ]; then
        warn "已存在 $DEB_FILE，跳过下载（如需重下请先删除）"
        return 0
    fi

    local url="${GH_PROXY}https://github.com/${GH_PATH}"
    info "下载中（约 204M，镜像下载约 7 分钟，请稍候）..."
    info "URL: $url"
    curl -fL -o "$DEB_FILE" "$url" \
        --connect-timeout 20 --max-time 590 || {
        err "下载失败。可尝试："
        echo "  1) 换镜像重试：    sudo GH_PROXY=https://ghfast.top/ bash $0 download"
        echo "  2) 开代理后直连：  sudo GH_PROXY= bash $0 download"
        echo "  3) 确认版本号是否仍存在于 Releases（升级时 tag 会变化）"
        rm -f "$DEB_FILE"
        exit 1
    }
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$DEB_FILE" 2>/dev/null || true
    ok "已下载 $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
}

# ---------- 步骤 2：dpkg 安装 ----------
do_install() {
    need_root
    title "步骤 2/4 · dpkg 安装"
    [ -f "$DEB_FILE" ] || { err "找不到 $DEB_FILE，请先执行 download"; exit 1; }

    info "dpkg -i $DEB_FILE"
    if ! dpkg -i "$DEB_FILE"; then
        warn "dpkg 报告依赖问题，尝试 apt -f 修复..."
        apt-get install -f -y || { err "依赖修复失败，请查看上方输出"; exit 1; }
    fi
    ok "安装完成"
}

# ---------- 步骤 3：命令软链 ----------
do_link() {
    need_root
    title "步骤 3/4 · 创建命令行软链"
    local bin_dir="${APP_DIR}/files/bin/bin"
    local cmd
    for cmd in wechat-devtools wechat-devtools-cli; do
        if [ -x "${bin_dir}/${cmd}" ]; then
            ln -sf "${bin_dir}/${cmd}" "/usr/local/bin/${cmd}"
            ok "/usr/local/bin/${cmd} -> ${bin_dir}/${cmd}"
        else
            err "${bin_dir}/${cmd} 不存在，安装可能不完整"
            exit 1
        fi
    done
}

# ---------- 步骤 4：校验 ----------
do_verify() {
    title "步骤 4/4 · 安装校验"
    local installed_ver
    installed_ver=$(dpkg -l "$PKG_NAME" 2>/dev/null | awk '/^ii/{print $3}')
    if [ -n "$installed_ver" ]; then
        ok "dpkg 已登记：$PKG_NAME = $installed_ver"
    else
        err "dpkg 未找到 $PKG_NAME，安装可能失败"
        exit 1
    fi

    if [ -x "$APP_DIR/files/bin/bin/wechat-devtools" ]; then
        ok "启动器存在：$APP_DIR/files/bin/bin/wechat-devtools"
    else
        err "$APP_DIR/files/bin/bin/wechat-devtools 未生成，请检查安装日志"
        exit 1
    fi

    if [ -f "/usr/share/applications/${PKG_NAME}.desktop" ]; then
        ok "桌面菜单项已注册：按 Super 键搜索 \"微信开发者工具\" 即可启动"
    fi

    if [ -x /usr/local/bin/wechat-devtools-cli ]; then
        ok "命令可用：wechat-devtools / wechat-devtools-cli"
        warn "CLI 使用前置：GUI 设置→安全设置→开启服务端口（见 docs/30 Q3）"
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载微信开发者工具"
    apt remove --purge -y "$PKG_NAME" || true
    rm -f /usr/local/bin/wechat-devtools /usr/local/bin/wechat-devtools-cli
    rm -f "$DEB_FILE"
    ok "已卸载系统包、清理软链与 deb 安装包"
    warn "用户数据 ~/.config/wechat-devtools（登录态/项目列表）如需彻底清理请手动删除，见 docs/30 Q6"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→软链→校验）：
  download  仅下载 deb 包到 ~/Downloads（不需 sudo）
  install   仅 dpkg 安装 + 命令软链（需 sudo）
  verify    仅校验安装结果
  remove    卸载并清理软链 / deb 包（需 sudo）
  all       依次执行 download → install → link → verify（推荐）
  help      显示本帮助

环境变量：
  WXDT_VERSION  指定版本号，默认 2.02.2608070-1（升级时改，见 docs/30 Q2）
  GH_PROXY      GitHub 加速镜像前缀，默认 https://gh-proxy.com/；
                置空（GH_PROXY=）走直连（需代理）

示例：
  sudo bash $0                          # 一键安装
  sudo WXDT_VERSION=2.02.2608080-1 bash $0 all   # 升级到新版本
  bash $0 download                      # 仅下载
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        download) do_download ;;
        install)  do_download; do_install; do_link ;;
        verify)   do_verify ;;
        remove)   do_remove ;;
        all)      do_download; do_install; do_link; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
