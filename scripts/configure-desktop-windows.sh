#!/bin/bash
# ======================================================================
# configure-desktop-windows.sh — 修复桌面扩展残缺 + 布局 Windows 化
#
# 背景：2026-09-15 重装 xserver-xorg/gdm3 时依赖级联把 ubuntu-desktop
# 元包和桌面扩展（Ubuntu Dock / 托盘 / Tweaks）带走，桌面成"裸 GNOME"
# （只剩顶栏）。本脚本精准补回扩展包，并把布局调成 Windows 习惯：
#   - Dock 挪到底部、常驻不隐藏（= 底部任务栏）
#   - 单击图标最小化/恢复（= Windows 任务栏点击行为）
#   - 窗口按钮 ─ □ ✕、新窗口居中、关热角
#
# 红线：不碰内核/Mesa/libdrm/Xorg 显示栈，只做 apt 装扩展包 + 用户级
# gsettings，全部可逆（reset 子命令恢复 GNOME 默认）。
#
# 对应文档：docs/31-桌面-Windows化布局.md
# ======================================================================

set -u

# ---------- 颜色与基础工具 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "该操作需要 root。请用 sudo 运行：sudo bash $0 install"
        exit 1
    fi
}

# sudo 下还原真实用户（gsettings 必须以真实用户跑，否则写进 root 的 dconf）
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID=$(id -u "$REAL_USER")
USER_BUS="unix:path=/run/user/${REAL_UID}/bus"

# 以真实用户身份执行 gsettings（自动带上用户 DBus 会话总线）
gs() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$REAL_USER" -- env DBUS_SESSION_BUS_ADDRESS="$USER_BUS" gsettings "$@"
    else
        DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-$USER_BUS}" gsettings "$@"
    fi
}

# 残缺桌面包清单（2026-09-15 事故实测丢失的 5 个 + 空壳修复 1 个）
DOCK_PKGS=(
    gnome-shell-extension-ubuntu-dock      # 左侧/底部 Dock（本脚本核心）
    gnome-shell-extension-appindicator     # 系统托盘（微信等图标）
    gnome-shell-extensions                 # GNOME 官方扩展合集（window-list 等）
    gnome-shell-extension-prefs            # 扩展管理器 GUI
    gnome-tweaks                           # 优化(Tweaks) 设置工具
    gnome-shell-extension-desktop-icons-ng # 桌面图标（事故中成"空壳包"）
)

ENABLE_EXTS=(
    ubuntu-dock@ubuntu.com
    ubuntu-appindicators@ubuntu.com
    ding@rastersoft.com
)

# ---------- 步骤 1：补装扩展包 ----------
do_install() {
    need_root
    title "步骤 1/2 · apt 补装桌面扩展包（不动显示栈）"
    apt-get update -qq
    apt-get install -y "${DOCK_PKGS[@]}"

    # 空壳包自愈：dpkg 认为已装但文件全丢（9-15 事故实测状态）→ 强制重装
    if ! dpkg -L gnome-shell-extension-desktop-icons-ng 2>/dev/null | grep -q "extensions"; then
        warn "desktop-icons-ng 是空壳包（有记录无文件），强制重装修复"
        apt-get install --reinstall -y gnome-shell-extension-desktop-icons-ng
    fi
    ok "扩展包就绪"
}

# ---------- 步骤 2：启用扩展 + Windows 化设置 ----------
do_apply() {
    title "步骤 2/2 · 启用扩展 + 布局 Windows 化"

    # 合并方式写 enabled-extensions（不清空用户已有的其他扩展）
    local cur new u
    cur=$(gs get org.gnome.shell enabled-extensions 2>/dev/null \
        | tr -d '[]' | tr ',' '\n' | sed "s/[ ']//g" | grep -v '^$' || true)
    new="[$(printf "'%s', " "${ENABLE_EXTS[@]}" | sed 's/, $//')]"
    for u in $cur; do
        echo "$new" | grep -q "'$u'" || new="${new%\]}, '$u']"
    done
    gs set org.gnome.shell enabled-extensions "$new"
    ok "已启用扩展：$(gs get org.gnome.shell enabled-extensions)"

    local D=org.gnome.shell.extensions.dash-to-dock
    # Dock = 底部任务栏：底部 + 常驻 + 单击最小化 + 图标 40px
    gs set $D dock-position      'BOTTOM'                # 左侧竖条 → 底部横条
    gs set $D dock-fixed          true                   # 常驻（不自动隐藏）
    gs set $D autohide            false                  # 关"贴边才出现"
    gs set $D intellihide         false                  # 关"有窗口全屏时隐藏"
    gs set $D click-action        'minimize-or-overview' # 单击=聚焦/再点=最小化
    gs set $D dash-max-icon-size  40                     # 图标略缩，接近任务栏密度
    gs set $D extend-height       false                  # 不占满整条边
    # 窗口行为对齐 Windows
    gs set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'
    gs set org.gnome.desktop.interface enable-hot-corners false  # 关左上热角
    gs set org.gnome.mutter center-new-windows true                # 新窗口居中

    ok "布局设置完成（已是运行中会话则即时生效；新装扩展需注销重登一次）"
}

# ---------- 状态查看 ----------
do_status() {
    title "桌面 Windows 化 · 当前状态"
    echo "-- 扩展包 --"
    local p
    for p in "${DOCK_PKGS[@]}"; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            # 额外检测空壳包（有记录无文件）
            if dpkg -L "$p" 2>/dev/null | grep -qE "extensions|gnome-tweaks|bin/"; then
                echo "  ✓ $p"
            else
                echo "  ✗ $p（空壳包，跑 install 修复）"
            fi
        else
            echo "  ✗ $p（未安装）"
        fi
    done
    echo "-- 已启用扩展 --"
    gs get org.gnome.shell enabled-extensions 2>/dev/null || echo "  （读不到，需桌面会话在运行）"
    echo "-- 布局关键值 --"
    local D=org.gnome.shell.extensions.dash-to-dock
    printf "  dock-position=%s dock-fixed=%s autohide=%s click-action=%s\n" \
        "$(gs get $D dock-position 2>/dev/null)" \
        "$(gs get $D dock-fixed 2>/dev/null)" \
        "$(gs get $D autohide 2>/dev/null)" \
        "$(gs get $D click-action 2>/dev/null)"
    printf "  button-layout=%s hot-corners=%s center-new-windows=%s\n" \
        "$(gs get org.gnome.desktop.wm.preferences button-layout 2>/dev/null)" \
        "$(gs get org.gnome.desktop.interface enable-hot-corners 2>/dev/null)" \
        "$(gs get org.gnome.mutter center-new-windows 2>/dev/null)"
}

# ---------- 恢复 GNOME 默认布局 ----------
do_reset() {
    title "恢复 GNOME 默认布局（Dock 回左侧竖条，按钮只剩 ✕）"
    local D=org.gnome.shell.extensions.dash-to-dock
    for k in dock-position dock-fixed autohide intellihide click-action \
             dash-max-icon-size extend-height; do
        gs reset $D "$k"
    done
    gs reset org.gnome.desktop.wm.preferences button-layout
    gs reset org.gnome.desktop.interface enable-hot-corners
    gs reset org.gnome.mutter center-new-windows
    ok "已恢复默认（扩展仍保持启用；完全卸载用 apt remove）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]   （install 需 sudo，其余用户身份即可）

子命令（缺省 = all，install + apply）：
  install   sudo apt 补装 6 个桌面扩展包（含空壳包自愈），不碰显示栈
  apply     启用 Dock/托盘/桌面图标扩展 + 应用 Windows 化布局设置
  status    查看包、扩展、布局关键值的当前状态
  reset     恢复 GNOME 默认布局（左侧竖条 Dock，可逆出口）
  all       install → apply（推荐，重装系统后一键恢复）
  help      显示本帮助

示例：
  sudo bash $0            # 一键全套（装包 + 布局）
  bash $0 status          # 看当前状态
  bash $0 reset           # 不习惯可整组回滚
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install)  do_install ;;
        apply)    do_apply ;;
        status)   do_status ;;
        reset)    do_reset ;;
        all)      do_install; do_apply ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
