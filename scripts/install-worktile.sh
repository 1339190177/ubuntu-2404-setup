#!/bin/bash
# ======================================================================
# install-worktile.sh — 一键安装 Worktile 桌面入口（网页版应用窗口封装）
#
# 背景：
#   Worktile 官方客户端只发 Windows/Mac/iOS/Android 四端
#   （worktile.com/client 实证，Win 9.0.0 exe / Mac 9.0.0 dmg），
#   无 Linux 版。本脚本把官方网页版封装成 Chrome --app 独立窗口：
#   独立任务栏图标、独立登录态（专用 user-data-dir），宿主机零污染。
#
# 功能：
#   1) 从官方 CDN 下载 favicon.ico 转 png 作为应用图标
#   2) 生成 ~/.local/share/applications/worktile.desktop
#      （Chrome --app 窗口 + 专用 --user-data-dir + --class 独立分组）
#   3) 校验 + 免 sudo 卸载
#
# 适用：Ubuntu 24.04 x86_64（GNOME 桌面）
# 对应文档：docs/34-工具-Worktile.md
#
# 全程无需 sudo；卸载：bash $0 remove
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-mqttx.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

APP_NAME="Worktile"
APP_ID="worktile"
WEB_URL="https://worktile.com"
ICON_URL="https://cdn-tc.worktile.com/static/site/wt/img/favicon.a824661.ico"
# Chrome --app 窗口的 WM_CLASS class 位（实测 = --class 参数值）
WM_CLASS="worktile-app"

DESKTOP_FILE="${REAL_HOME}/.local/share/applications/${APP_ID}.desktop"
# 别名：GNOME Shell 的 wmclass→应用匹配有两条路——StartupWMClass 字段比对、
# 以及把 WM_CLASS 的 class 位直接当 desktop 文件 id 查（"worktile-app.desktop"）。
# 实测（2026-09-22，X11 会话）Chrome --app 窗口 WM_CLASS=("worktile.com","worktile-app")，
# 光靠 StartupWMClass 可能因 Shell 应用索引未刷新而落空（窗口归进 Chrome 组），
# 补一个同内容别名文件，让 id 匹配这条路也通，双保险。
DESKTOP_ALIAS="${REAL_HOME}/.local/share/applications/${WM_CLASS}.desktop"
ICON_FILE="${REAL_HOME}/.local/share/icons/${APP_ID}.png"
# 专用 profile：与浏览器主 profile 隔离 → 任务栏独立分组 + 登录态独立 + 不受 Chrome 单实例锁影响
PROFILE_DIR="${REAL_HOME}/.config/${APP_ID}-chrome"

# ---------- 选浏览器：Chrome 优先，Edge 兜底 ----------
pick_browser() {
    local bin
    for bin in google-chrome-stable google-chrome microsoft-edge; do
        if command -v "$bin" >/dev/null 2>&1; then
            command -v "$bin"
            return 0
        fi
    done
    return 1
}

# ---------- 步骤 1：下载图标 ----------
do_icon() {
    title "步骤 1/3 · 获取图标（官方 CDN favicon）"
    mkdir -p "${REAL_HOME}/.local/share/icons"

    if [ -f "$ICON_FILE" ]; then
        warn "图标已存在 $ICON_FILE，跳过下载（如需更新请先删除）"
        return 0
    fi

    local tmp_ico
    tmp_ico=$(mktemp /tmp/worktile-XXXXXX.ico)
    info "下载 $ICON_URL"
    if ! curl -fsL --max-time 60 -A "Mozilla/5.0" "$ICON_URL" -o "$tmp_ico"; then
        err "图标下载失败。可手动放一张 png 到 $ICON_FILE 后重试"
        rm -f "$tmp_ico"
        exit 1
    fi

    if command -v convert >/dev/null 2>&1; then
        convert "$tmp_ico" "$ICON_FILE" && ok "ico → png 转换完成"
    else
        warn "无 ImageMagick(convert)，直接用 ico 当图标（GNOME 可识别）"
        cp "$tmp_ico" "$ICON_FILE"
    fi
    rm -f "$tmp_ico"
    chown -R "$REAL_USER":"$(id -g "$REAL_USER")" "${REAL_HOME}/.local/share/icons/${APP_ID}.png" 2>/dev/null || true
    ok "图标就位：$ICON_FILE ($(du -h "$ICON_FILE" | cut -f1))"
}

# ---------- 步骤 2：生成 .desktop ----------
do_install() {
    title "步骤 2/3 · 生成桌面菜单项（无需 sudo）"

    local browser_bin
    browser_bin=$(pick_browser) || {
        err "未找到 google-chrome / microsoft-edge，请先安装其一（见 docs/05）"
        exit 1
    }
    info "使用浏览器内核：$browser_bin"

    mkdir -p "${REAL_HOME}/.local/share/applications"
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=项目协作工具（官方网页版应用窗口，无 Linux 客户端的封装方案）
Exec=${browser_bin} --user-data-dir=${PROFILE_DIR} --class=${WM_CLASS} --app=${WEB_URL} --no-first-run --no-default-browser-check
Icon=${ICON_FILE}
Terminal=false
Categories=Office;ProjectManagement;
StartupWMClass=${WM_CLASS}
StartupNotify=true
Actions=PingCode;

[Desktop Action PingCode]
Name=打开 PingCode（研发管理）
Exec=${browser_bin} --user-data-dir=${PROFILE_DIR} --class=${WM_CLASS} --app=https://pingcode.com --no-first-run --no-default-browser-check
EOF
    chmod 644 "$DESKTOP_FILE"
    cp "$DESKTOP_FILE" "$DESKTOP_ALIAS"
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$DESKTOP_FILE" "$DESKTOP_ALIAS" 2>/dev/null || true

    # 让 GNOME 立即看到新菜单项
    update-desktop-database "${REAL_HOME}/.local/share/applications" 2>/dev/null || true
    ok "桌面菜单项已生成：$DESKTOP_FILE"
    ok "按 Super 键搜索 \"Worktile\" 即可启动"
}

# ---------- 步骤 3：校验 ----------
do_verify() {
    title "步骤 3/3 · 安装校验"
    local fail=0

    [ -f "$DESKTOP_FILE" ] && ok "菜单项存在：$DESKTOP_FILE" \
        || { err "缺少 $DESKTOP_FILE"; fail=1; }
    [ -f "$ICON_FILE" ] && ok "图标存在：$ICON_FILE" \
        || { err "缺少 $ICON_FILE"; fail=1; }

    local browser_bin
    if browser_bin=$(pick_browser); then
        ok "浏览器内核就绪：$browser_bin"
    else
        err "浏览器内核缺失（google-chrome/microsoft-edge）"; fail=1
    fi

    if command -v desktop-file-validate >/dev/null 2>&1; then
        if desktop-file-validate "$DESKTOP_FILE" 2>/dev/null; then
            ok "desktop-file-validate 通过"
        else
            err "desktop 文件格式有误："; desktop-file-validate "$DESKTOP_FILE"; fail=1
        fi
    fi

    if curl -fs --max-time 20 -o /dev/null "$WEB_URL"; then
        ok "网页版可达：$WEB_URL (HTTP 200)"
    else
        warn "网页版探测失败（可能临时网络抖动，不影响已生成的菜单项）"
    fi

    [ "$fail" -eq 0 ] && ok "全部校验通过 ✅" || { err "存在校验失败项"; exit 1; }
}

# ---------- 启动（测试用） ----------
do_launch() {
    gtk-launch "$APP_ID" 2>/dev/null || {
        err "gtk-launch 失败，请从 GNOME 应用网格手动点 Worktile"
        exit 1
    }
    ok "已发出启动请求"
}

# ---------- 卸载 ----------
do_remove() {
    title "卸载 Worktile 桌面入口（无需 sudo）"
    rm -f "$DESKTOP_FILE" "$DESKTOP_ALIAS" "$ICON_FILE"
    update-desktop-database "${REAL_HOME}/.local/share/applications" 2>/dev/null || true
    ok "已删除菜单项与图标"
    if [ -d "$PROFILE_DIR" ]; then
        warn "登录数据保留在 $PROFILE_DIR（彻底清理请手动 rm -rf）"
    fi
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

把 Worktile 官方网页版封装成独立桌面应用（Chrome --app 窗口，
独立 profile + 独立任务栏图标；官方无 Linux 客户端的替代方案）。

子命令（缺省 = all，执行 图标→安装→校验）：
  icon     仅下载图标到 ~/.local/share/icons（不需 sudo）
  install  仅生成 .desktop 菜单项
  verify   仅校验安装结果
  launch   用 gtk-launch 启动（测试）
  remove   卸载菜单项与图标（登录数据默认保留）
  all      依次执行 icon → install → verify（推荐）
  help     显示本帮助

环境变量：
  WEB_URL   网页版地址，默认 https://worktile.com

示例：
  bash $0                # 一键安装
  bash $0 verify         # 复查安装
  bash $0 remove         # 卸载
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        icon)     do_icon ;;
        install)  do_icon; do_install ;;
        verify)   do_verify ;;
        launch)   do_launch ;;
        remove)   do_remove ;;
        all)      do_icon; do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
