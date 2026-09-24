#!/bin/bash
# ======================================================================
# install-watermark.sh — 一键水印工具（傻瓜式：右键图片 → 脚本 → 完成）
#
# 功能：
#   1) apt 安装 imagemagick（convert，毫秒级水印，无需打开任何软件）
#   2) 部署 ~/bin/watermark 命令行工具（支持自定义文字/位置/字号/透明度）
#   3) 部署 Nautilus 右键脚本「添加文字水印」（文件管理器选中即加）
#
# 定位：日常加水印用这个（零学习成本）；复杂编辑/精修才开 GIMP（docs/28）
# 对应文档：docs/29-工具-一键水印.md
#
# 备注：
#   - 输出一律 原名_wm.扩展名，绝不覆盖原图
#   - 卸载：sudo bash $0 remove
# ======================================================================

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "安装依赖需要 root。请用 sudo 运行：sudo bash $0 install"
        exit 1
    fi
}

REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

FONT="Noto-Sans-CJK-SC"          # fc-list 实测存在，中文渲染正常
DEFAULT_TEXT="$USER · 版权所有"

# ---------- CLI 工具内容（heredoc 一次性写入） ----------
write_cli() {
    local dest="$1"
    cat > "$dest" << 'CLI_EOF'
#!/bin/bash
# watermark — 给图片加半透明文字水印（ImageMagick 实现）
# 用法：watermark [选项] 图片1 [图片2 ...]
#   -t "文字"   水印文字（默认 $USER · 版权所有）
#   -o 位置     southeast|southwest|northeast|northwest|center（默认右下）
#   -p 分母     字号 = 图片宽/分母（默认 18，越大字越小）
#   -a 透明度   0~1，默认 0.65
# 输出：原名_wm.扩展名（不覆盖原图）
set -u

TEXT="$USER · 版权所有"
GRAVITY="southeast"
RATIO=18
ALPHA=0.65
FONT_NAME="Noto-Sans-CJK-SC"

while getopts ":t:o:p:a:h" opt; do
    case "$opt" in
        t) TEXT="$OPTARG" ;;
        o) GRAVITY="$OPTARG" ;;
        p) RATIO="$OPTARG" ;;
        a) ALPHA="$OPTARG" ;;
        h|*) sed -n '2,9p' "$0"; exit 0 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { sed -n '2,9p' "$0"; exit 1; }

command -v convert >/dev/null 2>&1 || { echo "缺 imagemagick，先装：sudo apt install imagemagick"; exit 1; }
command -v identify >/dev/null 2>&1 || { echo "缺 imagemagick(convert 有 identify 无？)，重装：sudo apt install --reinstall imagemagick"; exit 1; }

ok_cnt=0; fail_cnt=0
for f in "$@"; do
    if [ ! -f "$f" ]; then echo "跳过（不存在）：$f"; continue; fi

    base="${f%.*}"; ext="${f##*.}"
    out="${base}_wm.${ext}"

    # 字号自适应图片宽度，小图保底 12
    w=$(identify -format "%w" "$f" 2>/dev/null) || { echo "跳过（非图片）：$f"; continue; }
    ps=$(( w / RATIO )); [ "$ps" -lt 12 ] && ps=12

    if convert "$f" -gravity "$GRAVITY" \
            -font "$FONT_NAME" -fill "rgba(255,255,255,${ALPHA})" \
            -pointsize "$ps" -annotate +24+24 "$TEXT" \
            -quality 92 "$out" 2>/dev/null; then
        echo "✓ $out"
        ok_cnt=$((ok_cnt+1))
    else
        echo "✗ 失败：$f" >&2
        fail_cnt=$((fail_cnt+1))
    fi
done

# 图形会话里弹结果通知（右键脚本场景的反馈通道，纯终端无害）
if command -v notify-send >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    notify-send -i emblem-photos "水印完成" "成功 $ok_cnt 张${fail_cnt:+，失败 $fail_cnt 张}（原图保留，新图带 _wm 后缀）"
fi
[ "$fail_cnt" -eq 0 ] || exit 1
CLI_EOF
    chmod +x "$dest"
}

# ---------- Nautilus 右键脚本内容 ----------
write_nautilus() {
    local dest="$1"
    cat > "$dest" << 'NAU_EOF'
#!/bin/bash
# Nautilus 右键脚本：选中图片 → 右键 → 脚本 → 添加文字水印
# 逐行读取选中文件（文件名可含空格），只处理常见图片格式
exec 2>>/tmp/nautilus-watermark.log
echo "--- $(date '+%F %T') ---" >> /tmp/nautilus-watermark.log

WM="$HOME/bin/watermark"
[ -x "$WM" ] || { notify-send -u critical "一键水印" "未找到 $WM，请先运行 install-watermark.sh"; exit 1; }

n=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "${f##*.}" in
        jpg|jpeg|png|webp|bmp|gif|tiff|JPG|JPEG|PNG|WEBP)
            "$WM" "$f" && n=$((n+1)) ;;
    esac
done <<< "${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS:-}"

# watermark 内部已弹通知；这里兜底提示 0 张的情况
if [ "$n" -eq 0 ]; then
    notify-send "一键水印" "没有可处理的图片（支持 jpg/png/webp 等）"
fi
exit 0
NAU_EOF
    chmod +x "$dest"
}

# ---------- 安装 ----------
do_install() {
    need_root
    title "步骤 1/3 · apt 安装 imagemagick"
    apt update
    apt install -y imagemagick
    ok "imagemagick $(convert --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) 就绪"

    title "步骤 2/3 · 部署 ~/bin/watermark"
    mkdir -p "$REAL_HOME/bin"
    write_cli "$REAL_HOME/bin/watermark"
    chown "$REAL_USER:" "$REAL_HOME/bin/watermark"
    ok "命令就位：~/bin/watermark（~/.profile 默认含 ~/bin，新终端生效）"

    title "步骤 3/3 · 部署 Nautilus 右键脚本"
    local nau_dir="$REAL_HOME/.local/share/nautilus/scripts"
    mkdir -p "$nau_dir"
    write_nautilus "$nau_dir/添加文字水印"
    chown "$REAL_USER:" "$nau_dir/添加文字水印"
    ok "右键菜单就位：选中图片 → 右键 → 脚本 → 添加文字水印"
}

# ---------- 校验 ----------
do_verify() {
    title "安装校验"
    local fail=0

    command -v convert >/dev/null 2>&1 \
        && ok "convert：$(convert --version | head -1 | cut -d' ' -f2-3)" \
        || { err "convert 未安装"; fail=1; }

    fc-list 2>/dev/null | grep -qi "Noto Sans CJK SC" \
        && ok "中文字体：Noto Sans CJK SC 存在" \
        || { err "缺中文字体（fonts-noto-cjk）"; fail=1; }

    [ -x "$REAL_HOME/bin/watermark" ] \
        && ok "CLI：~/bin/watermark" \
        || { err "~/bin/watermark 缺失"; fail=1; }

    [ -x "$REAL_HOME/.local/share/nautilus/scripts/添加文字水印" ] \
        && ok "右键脚本：~/.local/share/nautilus/scripts/添加文字水印" \
        || { err "Nautilus 脚本缺失"; fail=1; }

    [ "$fail" -eq 0 ] && echo && ok "校验通过。冒烟测试："
    return $fail
}

# ---------- 卸载 ----------
do_remove() {
    title "卸载一键水印"
    rm -fv "$REAL_HOME/bin/watermark" \
           "$REAL_HOME/.local/share/nautilus/scripts/添加文字水印"
    rm -fv /tmp/nautilus-watermark.log
    if [ "$(id -u)" -eq 0 ]; then
        apt remove --purge -y imagemagick 2>/dev/null
        apt autoremove --purge -y 2>/dev/null || true
    else
        warn "以普通用户运行，仅移除用户文件；卸载 imagemagick 请加 sudo"
    fi
    ok "卸载完成（生成的 *_wm.* 图片不自动删，自行清理）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行 install → verify）：
  install   装 imagemagick + 部署 ~/bin/watermark + Nautilus 右键脚本（需 sudo）
  verify    校验依赖/字体/CLI/右键脚本是否就位
  remove    卸载（用户文件 + 可选卸载 imagemagick）
  help      显示本帮助

日常用法（装完后）：
  文件管理器选中图片 → 右键 → 脚本 → 添加文字水印     ← 傻瓜式
  watermark 图片.png                                    ← 命令行
  watermark -t "自定义文字" -o southeast a.jpg b.png     ← 自定义
  for f in *.jpg; do watermark "\$f"; done               ← 批量
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install) do_install ;;
        verify)  do_verify ;;
        remove)  do_remove ;;
        all)     do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
