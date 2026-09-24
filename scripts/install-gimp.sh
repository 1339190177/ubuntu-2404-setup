#!/bin/bash
# ======================================================================
# install-gimp.sh — 一键安装 GIMP 图片编辑器（含水印能力）
#
# 功能：
#   1) apt 安装 gimp（Ubuntu 24.04 官方源，含 gmic 插件包备用）
#   2) 校验安装结果（which gimp / gimp --version / .desktop 入口）
#   3) 生成样图供水印功能自测（verify 时可选）
#
# 适用：Ubuntu 24.04，本地编辑图片 + 加文字/图片水印
# 对应文档：docs/28-工具-图片编辑GIMP.md
#
# 备注：
#   - 走 apt 官方源（本项目两类客户端安装模式中的"官方有 apt 包"型）
#   - 水印在 GIMP 内用文字工具 + 图层不透明度完成，无需额外插件
#   - 卸载：sudo bash $0 remove
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-mysql-client.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "apt 安装需要 root 权限。请用 sudo 运行："
        echo "    sudo bash $0 [install|remove]"
        exit 1
    fi
}

# 还原真实用户（sudo 环境下生成样图归到本人，不归 root）
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# ---------- 步骤 1：apt 安装 ----------
do_install() {
    need_root
    title "步骤 1/2 · apt 安装 gimp"
    info "说明：Ubuntu 24.04 官方源为 GIMP 2.10.x，约百余个依赖包，首次安装较慢。"
    info "      gimp 自带文字工具/图层/不透明度，水印无需额外插件。"
    apt update
    apt install -y gimp
    ok "安装完成"
    echo
    gimp --version 2>/dev/null || true
}

# ---------- 步骤 2：校验 ----------
do_verify() {
    title "步骤 2/2 · 安装校验"

    # 1) 命令是否就位
    if command -v gimp >/dev/null 2>&1; then
        ok "命令可用：$(which gimp)"
    else
        err "gimp 命令未找到，安装可能失败"
        exit 1
    fi

    # 2) 版本输出（gimp --version 在无显示环境也能跑）
    if gimp --version >/dev/null 2>&1; then
        ok "版本：$(gimp --version 2>&1)"
    else
        err "gimp --version 执行失败"
        exit 1
    fi

    # 3) 桌面入口（GNOME 应用列表里能搜到"GIMP"）
    local desktop="/usr/share/applications/gimp.desktop"
    if [ -f "$desktop" ]; then
        ok "桌面入口：$desktop"
    else
        warn "未找到 $desktop（应用菜单可能搜不到，但不影响命令行启动）"
    fi

    echo
    ok "校验通过。用法："
    echo "    gimp                       # 直接打开"
    echo "    gimp 图片.png              # 打开指定图片编辑"
    echo "    水印步骤见 docs/28-工具-图片编辑GIMP.md"
}

# ---------- 生成水印自测样图 ----------
do_sample() {
    title "生成水印自测样图（纯色底 + 半透明中文水印）"

    local out="${1:-$REAL_HOME/gimp-sample.png}"
    local scm
    scm="$(mktemp /tmp/gimp-sample.XXXXXX.scm)"

    # Script-Fu 写进文件再 load，避开 shell/Script-Fu 双层引号转义地狱
    # 坑1：颜色参数是列表 '(r g b)，不能写成字符串 "(r g b)"
    # 坑2：2.10.36 的 gimp-text-fontname 是 10 参（多一个 size-type），老示例 9 参会报错
    cat > "$scm" << 'EOF'
(let* ((img (car (gimp-image-new 800 600 RGB)))
       (bg (car (gimp-layer-new img 800 600 RGB-IMAGE "bg" 100 LAYER-MODE-NORMAL))))
  (gimp-image-insert-layer img bg 0 -1)
  (gimp-image-set-active-layer img bg)
  (gimp-context-set-foreground '(52 120 198))
  (gimp-edit-fill bg FILL-FOREGROUND)
  (gimp-context-set-foreground '(255 255 255))
  (let* ((txt (car (gimp-text-fontname img -1 40 520 "$USER · 版权所有" -1 TRUE 36 PIXELS "Sans"))))
    (gimp-layer-set-opacity txt 60))
  (gimp-image-flatten img)
  (gimp-file-save RUN-NONINTERACTIVE img (car (gimp-image-get-active-layer img)) "@OUT@" "@OUT@")
  (gimp-quit 0))
EOF
    sed -i "s|@OUT@|$out|g" "$scm"
    # 坑3：root mktemp 出来是 600 root:root，runuser 切普通用户后 gimp 读不了，必须放开读权限
    chmod 644 "$scm"

    # 本机坑1：su - <user> 被 PAM 拦着要密码（root 切普通用户也要），改用 runuser
    # 本机坑2：sudo 清掉 XDG_RUNTIME_DIR 后 gimp 无头启动会挂死，runuser 前必须补回
    local uid
    uid="$(id -u "$REAL_USER")"
    if [ "$(id -u)" -eq 0 ]; then
        timeout 120 env XDG_RUNTIME_DIR="/run/user/$uid" \
            runuser -u "$REAL_USER" -- gimp -i -b "(load \"$scm\")" >/dev/null 2>&1 || true
    else
        timeout 120 gimp -i -b "(load \"$scm\")" >/dev/null 2>&1 || true
    fi
    rm -f "$scm"

    if [ -s "$out" ]; then
        ok "样图已生成（含半透明水印示范）：$out"
        info "打开细看：gimp $out"
    else
        warn "无头生成样图失败（不影响 GUI 使用），手工测试："
        echo "    gimp &   # 菜单 文件→新建 800x600"
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载 gimp"
    apt remove --purge -y gimp
    apt autoremove --purge -y 2>/dev/null || true
    ok "卸载完成（用户配置 ~/.config/GIMP/ 保留，想清干净可手动删）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行 install → verify）：
  install   仅 apt 安装 gimp（需 sudo）
  verify    仅校验安装结果（命令/版本/桌面入口）
  sample    生成一张 800x600 样图到 ~/gimp-sample.png，供水印自测
  remove    卸载 gimp（需 sudo）
  all       依次执行 install → verify（推荐）
  help      显示本帮助

示例：
  sudo bash $0              # 一键安装 + 校验
  bash    $0 verify         # 只校验
  bash    $0 sample         # 生成水印自测样图
  sudo bash $0 remove       # 卸载

水印速记（详见 docs/28）：
  文字水印：文字工具(T) 输入 → 选中图层调不透明度 30~50% → 文件→导出
  图片水印：文件→作为图层打开 logo → 调整位置/大小 → 降不透明度 → 导出
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install) do_install ;;
        verify)  do_verify ;;
        sample)  do_sample "${2:-}" ;;
        remove)  do_remove ;;
        all)     do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
