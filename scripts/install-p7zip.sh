#!/bin/bash
# ======================================================================
# install-p7zip.sh — 一键安装 p7zip（7z 命令行压缩解压工具）
#
# 功能：
#   1) apt 安装 p7zip-full（Ubuntu 24.04 下是过渡包，实际拉入
#      官方 7-Zip 23.01，提供 7z / 7za / 7zr 三件套）
#   2) 校验安装结果（命令就位 + 版本输出）
#   3) 压缩→解压往返测试（临时目录，自动清理）
#
# 适用：Ubuntu 24.04，终端处理 .7z/.zip 等压缩包、脚本内压缩解压
# 对应文档：docs/25-工具-p7zip压缩解压.md
#
# 备注：
#   - RAR 解码被 dfsg 打包剥离，解 RAR 请另装 unrar（脚本不代装）
#   - agent 会话内 sudo 不可用时的 docker chroot 安装方式见 docs/24 坑 1
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

# ---------- 步骤 1：apt 安装 ----------
do_install() {
    need_root
    title "步骤 1/2 · apt 安装 p7zip-full"
    info "说明：p7zip-full 在 Ubuntu 24.04 是过渡包（16.02+transitional.1），"
    info "      实际拉入官方 7-Zip 23.01（7zip 包），命令 7z / 7za / 7zr。"
    apt update
    apt install -y p7zip-full
    ok "安装完成"
    echo
    7z --help 2>/dev/null | head -2 || true
}

# ---------- 步骤 2：校验 + 往返测试 ----------
do_verify() {
    title "步骤 2/2 · 安装校验"

    # 1) 命令是否就位
    if command -v 7z >/dev/null 2>&1; then
        ok "命令可用：$(which 7z)"
    else
        err "7z 命令未找到，安装可能失败"
        exit 1
    fi

    # 2) 版本输出（7z --help 首行是空行，取 "7-Zip" 开头那行）
    if 7z --help >/dev/null 2>&1; then
        ok "版本：$(7z --help 2>/dev/null | grep -m1 '^7-Zip')"
    else
        err "7z --help 执行失败"
        exit 1
    fi

    # 3) 配套命令
    for tool in 7za 7zr; do
        if command -v "$tool" >/dev/null 2>&1; then
            ok "附带工具：$tool → $(which $tool)"
        else
            warn "未找到 $tool（通常一起装上，缺失请检查 apt 输出）"
        fi
    done

    # 4) 压缩→解压往返测试（临时目录，结束清理）
    # tmp 必须是全局变量：EXIT trap 在函数返回后才执行，local 变量届时已销毁
    tmp="$(mktemp -d /tmp/p7zip-verify.XXXXXX)" || { err "建临时目录失败"; exit 1; }
    local content
    trap 'rm -rf "${tmp:-}"' EXIT
    content="p7zip round-trip $(date +%s)"
    printf '%s\n' "$content" > "$tmp/a.txt"
    mkdir -p "$tmp/src/nested"
    printf '%s\n' "$content" > "$tmp/src/nested/b.txt"

    if 7z a -bso0 "$tmp/test.7z" "$tmp/a.txt" "$tmp/src" >/dev/null 2>&1 \
       && 7z t -bso0 "$tmp/test.7z" >/dev/null 2>&1 \
       && 7z x -y -bso0 -o"$tmp/out" "$tmp/test.7z" >/dev/null 2>&1 \
       && [ "$(cat "$tmp/out/a.txt")" = "$content" ] \
       && [ "$(cat "$tmp/out/src/nested/b.txt")" = "$content" ]; then
        ok "往返测试通过：压缩 → 完整性校验 → 解压，内容逐字节一致（含嵌套目录）"
    else
        err "往返测试失败，请把上面的输出反馈给维护者"
        exit 1
    fi

    echo
    ok "校验通过。常用命令："
    echo "    7z a out.7z dir/            # 压缩"
    echo "    7z x out.7z -otarget/ -y    # 解压（保留目录结构）"
    echo "    7z l out.7z                 # 查看内容"
    echo "    7z t out.7z                 # 完整性测试"
    echo "    7z a -p -mhe=on out.7z dir/ # 加密（连文件名一起隐藏）"
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载 p7zip"
    apt remove --purge -y p7zip-full
    # 7zip 是 p7zip-full 的实际实现包，询问是否一并清理
    if dpkg -l 7zip 2>/dev/null | grep -q '^ii'; then
        warn "检测到 7zip（p7zip-full 的实际实现包）仍在"
        read -rp "是否一并卸载 7zip（7z 命令将消失）？[y/N] " ans
        if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
            apt remove --purge -y 7zip
            ok "已卸载 7zip"
        else
            info "保留 7zip（7z 命令仍可用）"
        fi
    fi
    apt autoremove -y 2>/dev/null || true
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行 install → verify）：
  install   仅 apt 安装 p7zip-full（需 sudo）
  verify    仅校验安装结果（命令就位 + 版本 + 压缩解压往返测试）
  remove    卸载 p7zip-full，交互式询问是否连 7zip 一起删（需 sudo）
  all       依次执行 install → verify（推荐）
  help      显示本帮助

示例：
  sudo bash $0              # 一键安装 + 校验
  sudo bash $0 install      # 只装包
  bash    $0 verify         # 只校验（无需 sudo）
  sudo bash $0 remove       # 卸载

压缩解压速查（脚本外直接用）：
  7z a -p -mhe=on out.7z dir/   # 加密压缩（推荐）
  7z x out.7z -y                # 解压
  解 RAR 需另装：sudo apt install unrar
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
