#!/bin/bash
# ======================================================================
# tune-ibus-libpinyin.sh — IBus 智能拼音（libpinyin）智能调优
#
# 背景：
#   本机决策（docs/10）：X11 会话（RustDesk 被控需要）下坚持 IBus，
#   不切 fcitx5。本脚本把 libpinyin 引擎的"越用越顺手"开关固化，
#   重装/重置后一条命令恢复。
#
# 调优项（2026-08-20 复审定案）：
#   1) lookup-table-page-size    5    → 9       每页候选 5→9，减少翻页
#   2) suggestion-candidate      强制 false      联想：上屏后弹"下一个词推荐"
#      框，必须 Esc/选词才能继续，打断输入流。2026-08-19 曾开启，
#      2026-08-20 用户反馈难受，永久关闭
#   3) enable-cloud-input        强制 false      云输入（Baidu 源）实测难用：
#      停键 ~0.6s 后异步插入云候选导致列表重排，快打快选时首选错位。
#      cloud-input-source 0=Baidu/1=Google（上游 enum CloudInputSource）
#      2026-08-19 曾开启，2026-08-20 用户定案关闭
#   实测有效：9 候选/页、emoji 候选、简拼、纠错
#   ⚠️ 自学习（用户词组）实测不工作：引擎从不写用户库（strace 证据），
#      remember-every-input 开了也无效果，勿开。详见 docs/10「自学习的真相」
#   刻意不开：fuzzy-pinyin（模糊音改变输入习惯，按需自开）
#
# 学习资产（越用越轻松的本体，重装前先 backup）：
#   ~/.cache/ibus/libpinyin/  — user_bigram.db / user_pinyin_index.bin 等
#   用户词频与自学习库，一直在活跃增长
#
# 适用：Ubuntu 24.04，GNOME + IBus + ibus-libpinyin（纯用户态，禁 sudo）
# 对应文档：docs/10-输入法-IBus配置.md「智能调优」章节
# ======================================================================

set -u

SCHEMA="com.github.libpinyin.ibus-libpinyin.libpinyin"
CACHE_DIR="$HOME/.cache/ibus/libpinyin"

# ---------- 颜色与基础工具（风格与 install-java-maven.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

# gsettings/dconf 属于用户会话，sudo 下会读写 root 的配置，禁止
refuse_root() {
    if [ "$(id -u)" -eq 0 ]; then
        err "本脚本纯用户态（gsettings + ~/.cache），无需 sudo，请直接运行："
        echo "    bash $0 [status|apply|reset|backup|restore]"
        exit 1
    fi
}

need_schema() {
    if ! gsettings list-schemas 2>/dev/null | grep -qx "$SCHEMA"; then
        err "未找到 schema：$SCHEMA（ibus-libpinyin 未安装？）"
        echo "    sudo apt install -y ibus ibus-libpinyin"
        exit 1
    fi
}

# ---------- 查看当前调优状态 ----------
do_status() {
    refuse_root; need_schema
    title "IBus libpinyin 调优状态"
    local k v
    while read -r k v; do
        printf '  %-26s %s\n' "$k" "$v"
    done < <(gsettings list-recursively "$SCHEMA" | awk '$2 ~ /^(enable-cloud-input|cloud-input-source|suggestion-candidate|lookup-table-page-size|dynamic-adjust|correct-pinyin|incomplete-pinyin|remember-every-input|fuzzy-pinyin)$/ {print $2, $3}')
    echo
    if [ -d "$CACHE_DIR" ]; then
        ok "学习资产：$CACHE_DIR（$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)）"
    else
        warn "学习资产目录不存在：$CACHE_DIR"
    fi
}

# ---------- 应用调优 ----------
do_apply() {
    refuse_root; need_schema
    title "应用智能调优（1 项开启 + 2 项强制关闭）"
    gsettings set "$SCHEMA" lookup-table-page-size 9
    gsettings set "$SCHEMA" suggestion-candidate false
    gsettings set "$SCHEMA" enable-cloud-input false
    ok "每页候选 9 个"
    ok "联想已关（上屏后不再弹推荐框，2026-08-20 定案）"
    ok "云输入已关（异步候选重排难用，2026-08-20 定案）"
    info "通常即时生效；若行为未变，注销重登（本仓库铁律，勿在当前会话瞎折腾）"
    do_status
}

# ---------- 恢复默认 ----------
do_reset() {
    refuse_root; need_schema
    title "恢复引擎默认（撤销 3 项调优，不动学习库）"
    gsettings reset "$SCHEMA" enable-cloud-input
    gsettings reset "$SCHEMA" suggestion-candidate
    gsettings reset "$SCHEMA" lookup-table-page-size
    ok "已恢复默认（云输入关 / 联想关 / 每页 5 个）"
    do_status
}

# ---------- 备份学习库 ----------
# 参数 $1：目标 tar 包路径（缺省 ~/backup-ibus-libpinyin-日期.tar.gz）
do_backup() {
    refuse_root
    title "备份学习库（自学习词频，越用越轻松的本体）"
    if [ ! -d "$CACHE_DIR" ]; then
        err "学习库目录不存在：$CACHE_DIR"
        exit 1
    fi
    local dest="${1:-$HOME/backup-ibus-libpinyin-$(date +%Y%m%d).tar.gz}"
    tar -C "$HOME/.cache/ibus" -czf "$dest" libpinyin \
        && ok "已备份：$dest（$(du -sh "$dest" | cut -f1)）" \
        || { err "备份失败"; exit 1; }
}

# ---------- 恢复学习库 ----------
do_restore() {
    refuse_root
    title "恢复学习库"
    if [ $# -lt 1 ] || [ ! -f "$1" ]; then
        err "用法：bash $0 restore <backup.tar.gz>"
        exit 1
    fi
    if pgrep -x ibus-engine-libpinyin >/dev/null 2>&1; then
        warn "拼音引擎正在运行，退出时会回写旧数据覆盖恢复结果"
        warn "建议：注销 → 切到英文键盘（或 tty）→ 再执行本命令 → 重登"
        read -rp "仍要现在恢复吗？[y/N] " ans
        [[ "${ans:-N}" =~ ^[Yy]$ ]] || { info "已取消"; exit 0; }
    fi
    mkdir -p "$HOME/.cache/ibus"
    tar -C "$HOME/.cache/ibus" -xzf "$1" \
        && ok "学习库已恢复到 $CACHE_DIR" \
        || { err "恢复失败（包损坏？）"; exit 1; }
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令] [参数]

子命令（缺省 = status，只读查看）：
  status             查看调优项当前值 + 学习库大小（只读，安全）
  apply              应用 3 项智能调优（云输入/联想/9 候选）
  reset              恢复引擎默认（撤销调优，不动学习库）
  backup  [文件]     备份学习库到 tar 包（缺省 ~/backup-ibus-libpinyin-日期.tar.gz）
  restore <文件>     从 tar 包恢复学习库（引擎运行中会提示先注销）

示例：
  bash $0                        # 看当前状态
  bash $0 apply                  # 重装后一键恢复调优
  bash $0 backup                 # 重装系统前备份学习成果
  bash $0 restore ~/backup-ibus-libpinyin-20260819.tar.gz

调优说明详见 docs/10-输入法-IBus配置.md「智能调优」章节
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-status}"
    case "$cmd" in
        status)  do_status ;;
        apply)   do_apply ;;
        reset)   do_reset ;;
        backup)  shift; do_backup "$@" ;;
        restore) shift; do_restore "$@" ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
