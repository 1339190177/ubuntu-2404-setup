#!/bin/bash
# ======================================================================
# install-mqttx.sh — 一键安装 MQTTX 桌面版（MQTT 5.0 可视化客户端）
#
# 功能：
#   1) 从 EMQ 国内 CDN 下载 Linux amd64 deb 包到 ~/Downloads
#      （GitHub release 直连实测 ~50KB/s 拉不完 85M，EMQ CDN ~470KB/s）
#   2) apt 安装到 /opt/MQTTX（自动注册桌面菜单项 mqttx.desktop）
#   3) 校验安装结果 + 探测远端 EMQX broker 端口
#
# 适用：Ubuntu 24.04 x86_64
# 对应文档：docs/33-工具-MQTTX桌面客户端.md
#
# 备注：
#   - MQTTX 是 GUI 客户端；命令行版是另一个产物 mqttx-cli（本脚本不装）
#   - 卸载：sudo apt remove --purge mqttx
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-apipost.sh 一致） ----------
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

# MQTTX 版本与下载地址（amd64）
# 版本列表：https://github.com/emqx/MQTTX/releases（文件名与 GitHub 资产同名）
MQTTX_VERSION="${MQTTX_VERSION:-1.13.1}"
DEB_FILE="${DOWNLOAD_DIR}/MQTTX_${MQTTX_VERSION}_amd64.deb"

# 主源 = EMQ 国内 CDN（快）；备源 = GitHub release（国内直连极慢，仅 CDN 失效时兜底）
EMQ_URL="https://www.emqx.com/zh/downloads/MQTTX/v${MQTTX_VERSION}/MQTTX_${MQTTX_VERSION}_amd64.deb"
GH_URL="https://github.com/emqx/MQTTX/releases/download/v${MQTTX_VERSION}/MQTTX_${MQTTX_VERSION}_amd64.deb"

# 远端 EMQX broker（服务端在 内网服务器，见 docs/15，本地只装客户端）
BROKER_HOST="${BROKER_HOST:-10.0.0.78}"
BROKER_PORT="${BROKER_PORT:-1883}"

# ---------- 步骤 1：下载 deb 包 ----------
do_download() {
    title "步骤 1/3 · 下载 MQTTX ${MQTTX_VERSION} (Linux amd64)"
    mkdir -p "$DOWNLOAD_DIR"

    if [ -f "$DEB_FILE" ] && dpkg-deb -I "$DEB_FILE" >/dev/null 2>&1; then
        warn "已存在 $DEB_FILE 且是合法 deb，跳过下载（如需重下请先删除）"
        return 0
    fi

    info "从 EMQ 国内 CDN 下载（约 86M，~470KB/s 约 3 分钟）..."
    info "URL: $EMQ_URL"
    if curl -fL -o "$DEB_FILE" "$EMQ_URL" \
        --connect-timeout 30 --max-time 600 -A "Mozilla/5.0"; then
        :
    else
        warn "EMQ CDN 下载失败，退回 GitHub release（国内直连慢，耐心等待）..."
        rm -f "$DEB_FILE"
        curl -fL -o "$DEB_FILE" "$GH_URL" \
            --connect-timeout 30 --max-time 1800 -A "Mozilla/5.0" || {
            err "两个下载源均失败。手动下载任一直链后放至 $DEB_FILE 再重试："
            echo "    $EMQ_URL"
            echo "    $GH_URL"
            rm -f "$DEB_FILE"
            exit 1
        }
    fi
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$DEB_FILE" 2>/dev/null || true
    ok "已下载 $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
}

# ---------- 步骤 2：apt 安装 ----------
do_install() {
    need_root
    title "步骤 2/3 · apt 安装"
    [ -f "$DEB_FILE" ] || { err "找不到 $DEB_FILE，请先执行 download"; exit 1; }

    info "apt install $DEB_FILE"
    # 用 apt 装 deb 可自动补依赖（MQTTX 无额外依赖，纯 Electron 自带）
    apt-get install -y "$DEB_FILE" || { err "安装失败，请查看上方输出"; exit 1; }
    ok "安装完成"
}

# ---------- 步骤 3：校验 ----------
do_verify() {
    title "步骤 3/3 · 安装校验"
    local installed_ver
    installed_ver=$(dpkg -l mqttx 2>/dev/null | awk '/^ii/{print $3}')
    if [ -n "$installed_ver" ]; then
        ok "dpkg 已登记：mqttx = $installed_ver"
    else
        err "dpkg 未找到 mqttx，安装可能失败"
        exit 1
    fi

    if [ -x /opt/MQTTX/mqttx ]; then
        ok "程序就位：/opt/MQTTX/mqttx"
    else
        err "/opt/MQTTX/mqttx 不存在，请检查安装日志"
        exit 1
    fi

    if [ -f /usr/share/applications/mqttx.desktop ]; then
        ok "桌面菜单项已注册：/usr/share/applications/mqttx.desktop"
        ok "按 Super 键搜索 \"MQTTX\" 即可启动"
    fi
}

# ---------- 探测远端 broker（连不上先查这里） ----------
do_connect() {
    title "探测远端 EMQX broker ${BROKER_HOST}:${BROKER_PORT}"
    if nc -z -w 3 "$BROKER_HOST" "$BROKER_PORT" 2>/dev/null; then
        ok "${BROKER_HOST}:${BROKER_PORT} 可达，MQTTX 里直接填这个地址连接"
    else
        err "${BROKER_HOST}:${BROKER_PORT} 不通（服务端在内网服务器，见 docs/15）"
        exit 1
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载 MQTTX"
    apt remove --purge -y mqttx || true
    rm -f "$DEB_FILE"
    info "已清理 deb 包：$DEB_FILE"
    ok "卸载完成（用户数据 ~/.config/MQTTX 保留，需要请手动删）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→校验）：
  download  仅下载 deb 包到 ~/Downloads（不需 sudo）
  install   仅 apt 安装（需 sudo）
  verify    仅校验安装结果
  connect   探测远端 EMQX broker 端口连通性
  remove    卸载 mqttx 并清理 deb 包（需 sudo）
  all       依次执行 download → install → verify（推荐）
  help      显示本帮助

环境变量：
  MQTTX_VERSION  指定版本号，默认 1.13.1
  BROKER_HOST    远端 broker 地址，默认 10.0.0.78（内网服务器）
  BROKER_PORT    远端 broker 端口，默认 1883

示例：
  sudo bash $0                    # 一键安装
  bash $0 connect                 # 测远端 broker 通不通
  sudo MQTTX_VERSION=1.13.1 bash $0 all
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        download) do_download ;;
        install)  do_download; do_install ;;
        verify)   do_verify ;;
        connect)  do_connect ;;
        remove)   do_remove ;;
        all)      do_download; do_install; do_verify; do_connect ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
