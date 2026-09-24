#!/bin/bash
# ======================================================================
# install-antigravity.sh — 一键安装 Google Antigravity 2.0（桌面客户端 Hub）
#
# 功能：
#   1) 从官方下载 linux-x64 tar.gz 到 ~/Downloads（直连失败自动走本机
#      xray SOCKS5 代理 127.0.0.1:10808，可用 AG_PROXY 覆盖）
#   2) 解压到 ~/apps/antigravity-<版本>（用户级安装，全程无需 sudo）
#   3) 配置 ~/.local/bin/antigravity 命令（代理环境包装）+ GNOME 菜单项
#      （含官方图标 + antigravity:// 协议注册，Google 登录回调依赖）
#   4) 校验安装结果
#
# 适用：Ubuntu 24.04 x86_64
# 对应文档：docs/26-工具-Google-Antigravity.md
#
# 备注：
#   - Antigravity 是 Electron 应用，实测 Ubuntu 24.04 无需修复
#     chrome-sandbox 属主即可正常启动（与 VS Code tarball 不同）
#   - 官方下载页同时提供「独立 IDE」v2.5.5（另一个 tar.gz），本脚本
#     装的是页面主推的桌面客户端（Hub），如需 IDE 用 AG_URL 覆盖
#   - 卸载：bash $0 remove
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

# 下载/安装用真实用户的家目录（脚本可能被 sudo 调用）
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
DOWNLOAD_DIR="${REAL_HOME}/Downloads"
APPS_DIR="${REAL_HOME}/apps"
BIN_DIR="${REAL_HOME}/.local/bin"
ICON_DIR="${REAL_HOME}/.local/share/icons"
DESKTOP_DIR="${REAL_HOME}/.local/share/applications"

# 版本与下载地址（官方页面的 linux-x64 直链；build 号随版本变化，用 AG_URL 整体覆盖）
# 官网下载页：https://antigravity.google/download
AG_VERSION="${AG_VERSION:-2.12.0}"
AG_URL="${AG_URL:-https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.0-5051501534642176/linux-x64/Antigravity.tar.gz}"
AG_ICON_URL="https://antigravity.google/apple-touch-icon.png"
TARBALL="${DOWNLOAD_DIR}/Antigravity-${AG_VERSION}-linux-x64.tar.gz"
INSTALL_DIR="${APPS_DIR}/antigravity-${AG_VERSION}"

# 本机代理（storage.googleapis.com 直连超时，实测需走 xray）
AG_PROXY="${AG_PROXY:-socks5h://127.0.0.1:10808}"
# 应用运行时代理：Google 域名直连全超时，应用内 Go 组件（language_server
# 的 OAuth token 交换 / Gemini API 调用）必须走 SOCKS5。注意 scheme 用
# socks5://（Go 的 httpproxy 不认 socks5h，socks5 在 Go 侧也是代理解析域名）
AG_APP_PROXY="${AG_APP_PROXY:-socks5://127.0.0.1:10808}"

# ---------- 带代理兜底的下载 ----------
fetch() { # fetch <输出文件> <URL> [说明]
    local out="$1" url="$2" desc="${3:-文件}"
    mkdir -p "$(dirname "$out")"

    if curl -fsSL --connect-timeout 8 --max-time 600 -o "$out" "$url"; then
        ok "已下载 $desc（直连）"
        return 0
    fi
    warn "直连 $desc 失败，尝试本机代理 ${AG_PROXY} ..."
    if curl -fsSL --proxy "$AG_PROXY" --connect-timeout 8 --max-time 900 -o "$out" "$url"; then
        ok "已下载 $desc（经 ${AG_PROXY}）"
        return 0
    fi
    rm -f "$out"
    err "下载失败：$url"
    err "请检查网络，或用 AG_PROXY=socks5h://IP:端口 bash $0 指定代理"
    return 1
}

# ---------- 步骤 1：下载 ----------
do_download() {
    title "步骤 1/4 · 下载 Antigravity ${AG_VERSION} (Linux x64，约 165M)"
    if [ -f "$TARBALL" ]; then
        warn "已存在 $TARBALL，跳过下载（如需重下请先删除）"
        return 0
    fi
    info "URL: $AG_URL"
    fetch "$TARBALL" "$AG_URL" "Antigravity tar.gz" || exit 1
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$TARBALL" 2>/dev/null || true
    ok "已保存 $TARBALL ($(du -h "$TARBALL" | cut -f1))"
}

# ---------- 步骤 2：解压到 ~/apps ----------
do_install() {
    title "步骤 2/4 · 解压到 ${INSTALL_DIR}"
    if [ -d "$INSTALL_DIR" ]; then
        warn "目录已存在，先删除旧安装：$INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$APPS_DIR"
    # 包内顶层目录名随架构变化（Antigravity-x64），解压后统一改名带版本号的稳定路径
    if ! tar -xzf "$TARBALL" -C "$APPS_DIR"; then
        err "解压失败：$TARBALL"
        exit 1
    fi
    mv "${APPS_DIR}/Antigravity-x64" "$INSTALL_DIR" || {
        err "未找到解压产物 ${APPS_DIR}/Antigravity-x64（包结构可能变了）"
        exit 1
    }
    chown -R "$REAL_USER":"$(id -g "$REAL_USER")" "$INSTALL_DIR" 2>/dev/null || true
    ok "解压完成：$INSTALL_DIR ($(du -sh "$INSTALL_DIR" | cut -f1))"
}

# ---------- 步骤 3：命令 + 图标 + 菜单项 ----------
do_configure() {
    title "步骤 3/4 · 配置命令行入口与桌面菜单项"

    mkdir -p "$BIN_DIR" "$ICON_DIR" "$DESKTOP_DIR"

    # 命令入口用「代理环境包装脚本」而不是裸软链：
    #   1. Google 域名直连不通，应用内 Go 组件（token 交换/Gemini API）需 socks5 代理
    #   2. 教训（2026-09-03 实录）：若此处已存在指向 ELF 的软链，直接
    #      cat > 写入会穿透软链覆盖应用主程序——必须先删再写
    rm -f "${BIN_DIR}/antigravity"
    cat > "${BIN_DIR}/antigravity" << WRAPPER
#!/bin/bash
# Antigravity 启动包装（docs/26 FAQ Q9）：Google 域名直连超时，Go 组件走 xray SOCKS5
export http_proxy=${AG_APP_PROXY}
export https_proxy=${AG_APP_PROXY}
export all_proxy=${AG_APP_PROXY}
export HTTP_PROXY="\$http_proxy" HTTPS_PROXY="\$https_proxy" ALL_PROXY="\$all_proxy"
export no_proxy=localhost,127.0.0.1,::1
export NO_PROXY="\$no_proxy"
exec ${INSTALL_DIR}/antigravity "\$@"
WRAPPER
    chmod +x "${BIN_DIR}/antigravity"
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "${BIN_DIR}/antigravity" 2>/dev/null || true
    ok "命令：${BIN_DIR}/antigravity（代理环境包装 → ${INSTALL_DIR}/antigravity）"

    if [ ! -f "${ICON_DIR}/antigravity.png" ]; then
        fetch "${ICON_DIR}/antigravity.png" "$AG_ICON_URL" "官方图标" \
            || warn "图标下载失败，菜单项将显示默认图标（不影响使用）"
    else
        ok "图标已存在：${ICON_DIR}/antigravity.png"
    fi

    cat > "${DESKTOP_DIR}/antigravity.desktop" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Antigravity
GenericName=AI 智能体开发工具
Comment=Google Antigravity（官方 tar.gz 用户级安装 ${AG_VERSION}）
Exec=${BIN_DIR}/antigravity -- %U
Icon=${ICON_DIR}/antigravity.png
Terminal=false
Categories=Development;IDE;
StartupWMClass=Antigravity
StartupNotify=true
MimeType=x-scheme-handler/antigravity;
EOF
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    # 预注册 antigravity:// 协议处理器：否则首次 Google 登录回调时 GNOME 报
    # "未安装可以打开 antigravity://oauth-success 的应用"（应用自己注册
    # 发生在启动后，但 GIO 缓存可能没刷新；显式注册 + 刷缓存双保险）
    xdg-mime default antigravity.desktop x-scheme-handler/antigravity 2>/dev/null || true
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    ok "菜单项：${DESKTOP_DIR}/antigravity.desktop（应用列表搜 \"Antigravity\"）"
    ok "协议处理器：antigravity:// → antigravity.desktop（登录回调依赖它）"
}

# ---------- 步骤 4：校验 ----------
do_verify() {
    title "步骤 4/4 · 安装校验"
    local fail=0

    [ -x "${INSTALL_DIR}/antigravity" ] \
        && ok "主程序存在：${INSTALL_DIR}/antigravity" \
        || { err "主程序缺失"; fail=1; }

    [ -x "${BIN_DIR}/antigravity" ] && grep -q "^exec ${INSTALL_DIR}/antigravity" "${BIN_DIR}/antigravity" \
        && ok "PATH 命令可用：antigravity（代理包装）" \
        || { err "${BIN_DIR}/antigravity 包装脚本异常"; fail=1; }

    [ -f "${DESKTOP_DIR}/antigravity.desktop" ] \
        && ok "桌面菜单项已注册" \
        || { err "菜单项缺失"; fail=1; }

    # chrome-sandbox 提示：Electron 应用若启动报 SUID sandbox 错误，
    # 执行 sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox
    # 本机 Ubuntu 24.04 实测无需此步

    # 已知坑：应用首次 Google 登录流程会把 text/html 默认应用抢成自己
    # （docs/18 约定 text/html → VS Code）。发现被抢时提醒恢复。
    local html_default
    html_default=$(xdg-mime query default text/html 2>/dev/null || true)
    if [ "$html_default" = "antigravity.desktop" ]; then
        warn "text/html 默认应用被 Antigravity 抢走，恢复 VS Code："
        info "  xdg-mime default code.desktop text/html   # docs/18 的既定配置"
    fi

    if [ "$fail" -eq 0 ]; then
        ok "全部校验通过。启动方式：应用列表搜 Antigravity，或终端执行 antigravity"
    else
        err "存在校验失败项，请查看上方输出"
        exit 1
    fi
}

# ---------- 启动（真机验证用） ----------
do_launch() {
    title "启动 Antigravity（后台）"
    # setsid 脱离会话：在 SSH/agent 会话里直接 gtk-launch 或裸 nohup 启动，
    # 会话退出时进程组被回收，应用被杀且日志里出现误导性的
    # "GPU process isn't usable. Goodbye." FATAL（实测 2026-09-03）
    DISPLAY="${DISPLAY:-:1}" setsid nohup "${BIN_DIR}/antigravity" \
        >/dev/null 2>&1 < /dev/null &
    sleep 5
    if pgrep -x antigravity >/dev/null; then
        ok "进程已运行（$(pgrep -cx antigravity) 个）"
    else
        err "启动后未检测到进程，查看日志：~/.config/Antigravity/logs/main.log"
        exit 1
    fi
}

# ---------- 卸载 ----------
do_remove() {
    title "卸载 Antigravity（用户级，无需 sudo）"
    # 注意：用 -x 精确匹配进程名，避免 pkill -f 匹配到本脚本自身命令行；
    # language_server 是独立进程名，不杀会变孤儿继续占端口
    pkill -x antigravity 2>/dev/null && { info "已停止运行中的 Antigravity"; sleep 2; } || true
    pkill -x language_server 2>/dev/null && info "已停止残留的 language_server" || true
    rm -rf "$INSTALL_DIR"
    rm -f "${BIN_DIR}/antigravity" "${DESKTOP_DIR}/antigravity.desktop" "$TARBALL"
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    ok "已删除：$INSTALL_DIR、命令软链、菜单项、安装包"
    info "保留：${ICON_DIR}/antigravity.png 与 ~/.config/Antigravity（用户数据/登录态，可手动删）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

子命令（缺省 = all，执行下载→安装→配置→校验）：
  download   仅下载 tar.gz 到 ~/Downloads（不需 sudo）
  install    仅解压到 ~/apps/antigravity-<版本>
  configure  仅配置命令软链 + 图标 + 菜单项
  verify     仅校验安装结果
  launch     后台启动并确认进程
  remove     卸载（停止进程、删安装目录/软链/菜单项/安装包）
  all        依次 download → install → configure → verify（推荐）
  help       显示本帮助

环境变量：
  AG_VERSION    版本号，默认 2.12.0（仅影响目录/文件命名）
  AG_URL        完整下载直链（官方 build 号随版本变，升级时改这里）
  AG_PROXY      下载兜底代理，默认 socks5h://127.0.0.1:10808（本机 xray）
  AG_APP_PROXY  应用运行时代理（写进启动包装），默认 socks5://127.0.0.1:10808
                （注意 scheme 是 socks5 不是 socks5h，Go 的 httpproxy 只认前者）

示例：
  bash $0                          # 一键安装
  bash $0 download                 # 仅下载
  AG_URL=<新版本直链> bash $0 all  # 升级到新版本
  bash $0 remove                   # 完整卸载
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        download)  do_download ;;
        install)   do_download; do_install ;;
        configure) do_configure ;;
        verify)    do_verify ;;
        launch)    do_launch ;;
        remove)    do_remove ;;
        all)       do_download; do_install; do_configure; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
