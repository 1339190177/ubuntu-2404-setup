#!/bin/bash
# ======================================================================
# ibus-pinyin-sync.sh — IBus 拼音用户词库自动持久化（外挂式钩子）
#
# 背景（2026-08-19 实测，docs/10「自学习的真相」）：
#   ibus-libpinyin 的自学习只在引擎内存里累积，正常打字/退出从不落盘，
#   引擎重启（注销/ibus restart）即清零。本钩子在外面补上持久化层。
#
# 机制（全部行为级实测，注意三条铁律）：
#   1. gsettings 的 export-dictionary / import-dictionary 是动作触发键：
#      写入文件路径 → 运行中的引擎执行 导出/导入 明文词库
#      （三列：汉字 拼音 频率；拼音音节用 ' 分隔）
#   2. 【铁律A】写入相同路径不会触发（GLib 同值不发信号）→ 文件名必须轮转
#   3. 【铁律B】import 对已存在词条是【加法】语义（频率累加）→
#      绝不能每轮重导入同一份词表（会指数翻倍），种子词只导一次
#   4. 【铁律C】export 动作会顺带把内存词库刷进引擎自己的缓存
#      （~/.cache/ibus/libpinyin/），引擎重启自动从缓存加载 →
#      「保存」= 触发一次 export 即可，无需手动重导入
#
# 同步循环（每 5 分钟）：
#   引擎活着 → export 攒学习（=保存） + 导入种子表里的【新】词
#   引擎不在 → 静默跳过
#   引擎词库为空但状态备份非空 → 缓存被清过，从备份恢复
#
# 种子词表 ~/.config/ibus-libpinyin/phrases.txt（固定首选的词写这里）：
#   每行一个词，三种写法（拼音可省略，自动用 pypinyin 生成；频率默认 500）：
#     进不去                      # 打 jinbuqu 稳居首选
#     座右铭 zuo'you'ming
#     阿里巴巴 ali'ba'ba 800
#   注意：词必须纯汉字；已导入过的词改频率不生效（加法语义，防止翻倍）
#
# 安装：bash $0 install    # systemd 用户定时器（开机 90s 首跑，每 5 分钟一轮）
# 卸载：bash $0 uninstall
#
# 适用：Ubuntu 24.04 + IBus + ibus-libpinyin；纯用户态，禁 sudo
# 对应文档：docs/10-输入法-IBus配置.md「自学习持久化钩子」章节
# ======================================================================

set -u

SCHEMA="com.github.libpinyin.ibus-libpinyin.libpinyin"
CONF_DIR="$HOME/.config/ibus/libpinyin"
SEED_FILE="$CONF_DIR/phrases.txt"
STATE_DIR="$HOME/.local/state/ibus-pinyin-sync"
STATE_FILE="$STATE_DIR/state.dict"
ENGINE_PATTERN="^/usr/libexec/ibus-engine-libpinyin"

# ---------- 颜色与基础工具（风格与 install-java-maven.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

refuse_root() {
    if [ "$(id -u)" -eq 0 ]; then
        err "本脚本纯用户态（gsettings + systemd --user），无需 sudo，请直接运行："
        echo "    bash $0 [sync|install|uninstall|status]"
        exit 1
    fi
}

need_schema() {
    gsettings list-schemas 2>/dev/null | grep -qx "$SCHEMA" || {
        err "未找到 schema：$SCHEMA（ibus-libpinyin 未安装？）"; exit 1; }
}

engine_pid() { pgrep -f "$ENGINE_PATTERN" 2>/dev/null | head -1; }

# ---------- 触发引擎动作（轮转文件名保证值变化） ----------
trigger_export() {   # $1 = 输出文件（本函数外已保证路径唯一）
    gsettings set "$SCHEMA" export-dictionary "$1"
}
trigger_import() {   # $1 = 输入文件
    gsettings set "$SCHEMA" import-dictionary "$1"
}

# ---------- 种子表解析：输出「当前词库中不存在」的新种子 ----------
# 输入：种子文件 + 当前词库 dump；输出：可直接 import 的三列文件
new_seeds() {
    python3 - "$SEED_FILE" "$1" "$2" << 'PYEOF'
import os, re, sys
try:
    from pypinyin import lazy_pinyin
except ImportError:
    lazy_pinyin = None

seed_path, dump_path, out_path = sys.argv[1:4]
existing = set()
if os.path.exists(dump_path):
    for line in open(dump_path, encoding='utf-8'):
        parts = line.split()
        if parts:
            existing.add(parts[0])

out = []
if os.path.exists(seed_path):
    for line in open(seed_path, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        word = parts[0]
        if not re.fullmatch(r'[\u4e00-\u9fff]+', word) or word in existing:
            continue
        if len(parts) == 1:                       # 词
            if lazy_pinyin:
                out.append((word, "'".join(lazy_pinyin(word)), 500))
        elif len(parts) == 2:
            if parts[1].isdigit():                # 词 频率
                if lazy_pinyin:
                    out.append((word, "'".join(lazy_pinyin(word)), int(parts[1])))
            else:                                 # 词 拼音
                out.append((word, parts[1], 500))
        else:                                     # 词 拼音 频率
            out.append((word, parts[1], int(parts[2])))

with open(out_path, 'w', encoding='utf-8') as f:
    for word, py, fr in out:
        f.write(f"{word} {py} {max(1, fr)}\n")
print(len(out))
PYEOF
}

# ---------- 单轮同步 ----------
do_sync() {
    need_schema
    local epid; epid="$(engine_pid)"
    [ -z "$epid" ] && exit 0   # 引擎未运行：静默等下一轮

    mkdir -p "$STATE_DIR" "$CONF_DIR"
    [ -f "$SEED_FILE" ] || printf '# 种子词表：每行一个词，可选拼音与频率（详见 scripts/ibus-pinyin-sync.sh 头部说明）\n' > "$SEED_FILE"

    # 每次触发都用唯一文件名（铁律A：同值路径不触发动作）
    local ts; ts="$(date +%s%N)"
    local k=0
    fresh_dump() { k=$((k+1)); echo "$STATE_DIR/dump-${ts}-${k}.dict"; }
    local dump prev

    # 1) 导出当前词库（= 保存：顺带刷进引擎缓存，重启可自动恢复）
    #    引擎刚拉起的几秒内可能还没就绪（实测动作会被丢弃）→ 空结果重试一次
    dump="$(fresh_dump)"
    trigger_export "$dump"; sleep 2
    if [ ! -s "$dump" ]; then
        sleep 4
        dump="$(fresh_dump)"
        trigger_export "$dump"; sleep 2
    fi

    # 2) 引擎词库为空但备份还在 → 缓存被清过（如缓存清理工具），先恢复
    if [ ! -s "$dump" ] && [ -s "$STATE_FILE" ]; then
        local restore="$STATE_DIR/restore-${ts}.dict"
        cp "$STATE_FILE" "$restore"
        trigger_import "$restore"; sleep 2
        rm -f "$restore"
        dump="$(fresh_dump)"
        trigger_export "$dump"; sleep 2
    fi

    # 3) 导入种子表里的【新】词（只导一次，防加法翻倍）
    local seeds_new="$STATE_DIR/seeds-${ts}.dict"
    local n; n="$(new_seeds "$dump" "$seeds_new" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ]; then
        trigger_import "$seeds_new"; sleep 2
        dump="$(fresh_dump)"
        trigger_export "$dump"; sleep 2
    fi
    rm -f "$seeds_new"

    # 4) 最终结果存为状态备份
    [ -s "$dump" ] && mv -f "$dump" "$STATE_FILE"

    # 5) 毒丸：把 import-dictionary 指回空文件（实测引擎每次启动会重放
    #    dconf 里残留的导入值 → 不中和的话每次重启都会把旧词表再加一遍）
    local pill="$STATE_DIR/pill.dict"
    : > "$pill"
    trigger_import "$pill"

    find "$STATE_DIR" -name 'dump-*.dict' -o -name 'seeds-*.dict' -o -name 'restore-*.dict' 2>/dev/null \
        | xargs -r rm -f
}

# ---------- 安装钩子 ----------
do_install() {
    refuse_root; need_schema
    title "安装输入法词库自动同步钩子"
    mkdir -p "$STATE_DIR" "$CONF_DIR" "$HOME/.config/systemd/user"
    [ -f "$SEED_FILE" ] || printf '# 种子词表：每行一个词，可选拼音与频率（详见 scripts/ibus-pinyin-sync.sh 头部说明）\n进不去\n' > "$SEED_FILE"
    ok "种子词表：$SEED_FILE（$(grep -vcE '^\s*(#|$)' "$SEED_FILE") 个词）"

    local script_path; script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    cat > "$HOME/.config/systemd/user/ibus-pinyin-sync.service" << EOF
[Unit]
Description=IBus libpinyin 用户词库自动同步（引擎活着=攒学习，缓存被清=自动恢复）

[Service]
Type=oneshot
ExecStart=/bin/bash ${script_path} sync
EOF

    cat > "$HOME/.config/systemd/user/ibus-pinyin-sync.timer" << EOF
[Unit]
Description=IBus 拼音词库每 5 分钟同步一次

[Timer]
OnBootSec=90s
OnUnitActiveSec=5min
Persistent=true
Unit=ibus-pinyin-sync.service

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now ibus-pinyin-sync.timer
    ok "定时器已启用：$(systemctl --user is-active ibus-pinyin-sync.timer)"
    info "当前轮立即跑一次..."
    do_sync
    [ -s "$STATE_FILE" ] && ok "状态文件：$STATE_FILE（$(wc -l < "$STATE_FILE") 个词条）"
    echo
    ok "完成。日常用法："
    echo "    固定某词到首选 → 加进 $SEED_FILE（≤5 分钟生效，或手动 bash $0 sync）"
    echo "    打字的学习成果 → 每 5 分钟自动保存，注销/重启自动恢复"
}

# ---------- 卸载 ----------
do_uninstall() {
    refuse_root
    title "卸载输入法词库同步钩子"
    systemctl --user disable --now ibus-pinyin-sync.timer 2>/dev/null
    rm -f "$HOME/.config/systemd/user/ibus-pinyin-sync."{service,timer}
    systemctl --user daemon-reload
    ok "定时器已移除"
    info "保留（不影响系统）：$SEED_FILE 与 $STATE_DIR（确认不要可手动删除）"
}

# ---------- 状态 ----------
do_status() {
    refuse_root; need_schema
    title "词库同步状态"
    local epid; epid="$(engine_pid)"
    [ -n "$epid" ] && ok "引擎运行中（PID $epid）" || warn "引擎未运行（等待首次中文输入）"
    if [ -s "$STATE_FILE" ]; then
        ok "状态文件：$STATE_FILE（$(wc -l < "$STATE_FILE") 词条，最近更新 $(stat -c %y "$STATE_FILE" | cut -d. -f1)）"
        echo "    最新词条：$(head -3 "$STATE_FILE" | tr '\n' ' ')"
    else
        warn "状态文件为空或不存在（install 后引擎有输入才会积累）"
    fi
    [ -f "$SEED_FILE" ] && ok "种子词表：$(grep -vcE '^\s*(#|$)' "$SEED_FILE") 个词" || warn "无种子词表"
    if systemctl --user is-active ibus-pinyin-sync.timer >/dev/null 2>&1; then
        ok "定时器：运行中（下次 $(systemctl --user list-timers ibus-pinyin-sync.timer --no-legend | awk '{print $1, $2}'))"
    else
        warn "定时器未安装/未运行（bash $0 install）"
    fi
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

子命令（缺省 = status）：
  sync       跑一轮同步（保存学习 + 导入新种子 + 空库时自动恢复备份）
  install    安装 systemd 用户定时器钩子（开机 90s 首跑，每 5 分钟一轮）
  uninstall  移除定时器钩子（保留词表与状态数据）
  status     查看引擎/状态文件/种子词表/定时器

原理（实测三条铁律）：
  A. gsettings 动作键同值不触发 → 导入/导出文件名必须轮转
  B. import 对已有词条是加法 → 种子只导一次，禁止每轮重导入
  C. export 动作会刷引擎缓存，重启自动加载 → 保存=export，无需手动恢复

文件：
  种子词表  ~/.config/ibus/libpinyin/phrases.txt     （固定首选的词）
  状态备份  ~/.local/state/ibus-pinyin-sync/state.dict
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-status}"
    case "$cmd" in
        sync)      do_sync ;;
        install)   do_install ;;
        uninstall) do_uninstall ;;
        status)    do_status ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
