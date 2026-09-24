#!/bin/bash
# ======================================================================
# install-bbdown.sh — 一键安装 BBDown（B 站视频下载命令行工具）
#
# 功能：
#   1) 从 GitHub releases 下载 BBDown linux-x64 自包含单文件（内含 .NET
#      runtime，无任何外部依赖），安装到 ~/bin/BBDown
#   2) 下载链路：直连 GitHub → 失败自动切换 ghfast.top / ghproxy.net 镜像
#      （本机实测：github.com 可达但 release-assets 资产域名超时，镜像 1~2s 通）
#   3) 版本：优先 GitHub API 自动取最新 release，API 不通则回退内置版本
#   4) 校验：版本输出 + PATH 检查 + ffmpeg 依赖检查
#
# 适用：Ubuntu 24.04 x86_64，替代 Windows 上的唧唧/Downkyi 等 B 站下载 GUI
# 对应文档：docs/21-工具-B站视频下载.md
#
# 备注：
#   - 纯用户态安装（~/bin），无需 sudo；请勿用 sudo 运行本脚本
#     （唯一的 root 场景是缺 qrencode 时先自行 sudo apt install qrencode）
#   - 登录：BBDown 1.6.3 自带的 `BBDown login` 对 B 站改版后的接口解析失效
#     （扫码成功但 SESSDATA 存空值），login 子命令改为官方 API 直连扫码，
#     拿到 cookie 后直接写入凭据文件（实测 2026-08-16，1080P 高码率生效）
#   - 登录凭据保存在 ~/bin/BBDown.data（与二进制同目录，cookie 字符串格式）
#   - 卸载：bash $0 remove
# ======================================================================

set -u

# ---------- 版本与下载源 ----------
# API 可自动获取最新版；API 不通时回退到下面的内置版本（手动更新时改这里）
FALLBACK_VERSION="1.6.3"
FALLBACK_ASSET="BBDown_1.6.3_20240814_linux-x64.zip"
REPO="nilaoda/BBDown"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# 直连 → 镜像，依次尝试（镜像前缀直接拼在 GitHub 完整 URL 前面）
MIRRORS=(
    ""
    "https://ghfast.top/"
    "https://ghproxy.net/"
)

# ---------- 颜色与基础工具（风格与 install-java-maven.sh / install-mysql-client.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

# 本脚本纯用户态，禁止 sudo（否则会装到 root 家目录）
refuse_root() {
    if [ "$(id -u)" -eq 0 ]; then
        err "本脚本安装到 ~/bin，无需 sudo。请直接运行："
        echo "    bash $0 [install|verify|login|update|remove]"
        exit 1
    fi
}

BIN_DIR="$HOME/bin"
TARGET="$BIN_DIR/BBDown"

# ---------- 查询最新版本与资产名 ----------
# 从 GitHub API 取最新 release，输出 "版本号 资产文件名"；失败输出空串
query_latest() {
    curl -s --connect-timeout 8 --max-time 15 "$API_URL" 2>/dev/null \
        | grep -oE '"(tag_name|browser_download_url)": *"[^"]+"' \
        | sed -E 's/"(tag_name|browser_download_url)": *"([^"]+)"/\1 \2/' \
        | awk '
            $1 == "tag_name"   { ver = $2 }
            $1 == "browser_download_url" && $2 ~ /linux-x64\.zip$/ { asset = $2 }
            END { if (ver != "" && asset != "") { print ver, asset } }
        '
}

# ---------- 多源下载 ----------
# 依次尝试 直连/镜像，成功返回 0 并落盘到 $1（目标文件路径），URL 通过全局变量传回
download() {
    local dest="$1" url_base="$2" asset="$3" prefix dl_url
    for prefix in "${MIRRORS[@]}"; do
        dl_url="${prefix}${url_base}/${asset}"
        if [ -z "$prefix" ]; then
            info "尝试直连：$dl_url"
        else
            info "尝试镜像：$prefix"
        fi
        if curl -sL --connect-timeout 10 --max-time 180 -o "$dest" "$dl_url" \
           && [ -s "$dest" ] && file -b "$dest" | grep -qi zip; then
            DOWNLOAD_URL="$dl_url"
            return 0
        fi
        warn "该源下载失败，换下一个..."
        rm -f "$dest"
    done
    return 1
}

# ---------- 步骤 1：下载安装 ----------
do_install() {
    refuse_root
    title "步骤 1/2 · 下载并安装 BBDown 到 ~/bin"

    # 依赖检查
    for tool in curl unzip file; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            err "缺少依赖：$tool。请先执行：sudo apt install -y $tool"
            exit 1
        fi
    done

    # 版本与资产名：API 优先，失败回退内置
    local version asset url_base
    info "查询 GitHub 最新版本..."
    local latest
    latest="$(query_latest)"
    if [ -n "$latest" ]; then
        version="${latest%% *}"
        asset="$(basename "${latest#* }")"
        ok "最新版：$version（API 获取）"
    else
        version="$FALLBACK_VERSION"
        asset="$FALLBACK_ASSET"
        warn "GitHub API 不通，回退内置版本 $version"
    fi
    url_base="https://github.com/${REPO}/releases/download/${version}"

    mkdir -p "$BIN_DIR"
    local tmp_zip
    tmp_zip="$(mktemp /tmp/bbdown.XXXXXX.zip)"
    if ! download "$tmp_zip" "$url_base" "$asset"; then
        rm -f "$tmp_zip"
        err "所有下载源均失败。可手动排查："
        echo "    1. 浏览器打开 $url_base 下载 $asset"
        echo "    2. unzip 解压后把 BBDown 放到 $TARGET"
        exit 1
    fi
    ok "下载成功（来源：$DOWNLOAD_URL）"

    # 解压并安装（zip 里就是单个自包含可执行文件）
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/bbdown.XXXXXX)"
    unzip -o -q "$tmp_zip" -d "$tmp_dir"
    if [ ! -f "$tmp_dir/BBDown" ]; then
        err "解压后未找到 BBDown 可执行文件，包内容异常"
        rm -rf "$tmp_zip" "$tmp_dir"
        exit 1
    fi
    install -m 755 "$tmp_dir/BBDown" "$TARGET"
    rm -rf "$tmp_zip" "$tmp_dir"
    ok "已安装：$TARGET"
}

# ---------- 步骤 2：校验 ----------
do_verify() {
    refuse_root
    title "步骤 2/2 · 安装校验"

    # 1) 命令是否就位
    if command -v BBDown >/dev/null 2>&1; then
        ok "命令可用：$(which BBDown)"
    else
        if [ -x "$TARGET" ]; then
            warn "$TARGET 存在但不在 PATH。请把下面这行加进 ~/.profile 后重开终端："
            echo '    export PATH="$HOME/bin:$PATH"'
        else
            err "BBDown 未安装，请先执行：bash $0 install"
        fi
        exit 1
    fi

    # 2) 版本输出（BBDown 没有 --version，版本号在 --help 首行）
    local ver_line
    ver_line="$(BBDown --help 2>/dev/null | head -1)"
    echo "    $ver_line"
    if echo "$ver_line" | grep -q "BBDown version"; then
        ok "可正常执行"
    else
        err "BBDown --help 执行异常"
        exit 1
    fi

    # 3) ffmpeg 依赖（下载后音视频混流需要）
    if command -v ffmpeg >/dev/null 2>&1; then
        ok "混流依赖：ffmpeg → $(which ffmpeg)"
    else
        warn "未安装 ffmpeg（下载可以，但音视频合并会失败）。请执行：sudo apt install -y ffmpeg"
    fi

    echo
    ok "校验通过。快速上手："
    echo "    bash $0 login                                   # 扫码登录（解锁 1080P+ 画质）"
    echo "    BBDown \"https://www.bilibili.com/video/BVxxxx\"  # 下载单个视频"
    echo "    BBDown -info \"BVxxxx\"                          # 只解析不下载，看可用画质"
}

# ---------- 扫码登录（官方 API 直连） ----------
# 背景：BBDown 1.6.3 的 `BBDown login` 对 B 站 2025+ 登录接口解析失效，
# 扫码确认后只存下无用的 ticket，SESSDATA 为空 → 永远"未登录"。
# 此处直接走官方 qrcode generate/poll 接口，拿到 cookie_info 后写凭据文件。
do_login() {
    refuse_root
    title "扫码登录 B 站账号（官方 API 直连，解锁高清画质）"
    if ! command -v BBDown >/dev/null 2>&1; then
        err "BBDown 未安装，请先执行：bash $0 install"
        exit 1
    fi
    for tool in curl python3 qrencode; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            err "缺少依赖：$tool。请先执行：sudo apt install -y curl qrencode"
            exit 1
        fi
    done

    info "未登录只能下 480P；登录后可下账号权限内的最高画质（1080P/4K/大会员内容）"

    # 1) 生成二维码
    local tmp_dir info_json qr_url qr_key
    tmp_dir="$(mktemp -d /tmp/bbdown-login.XXXXXX)"
    info_json="$(curl -s --connect-timeout 10 --max-time 20 \
        "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")"
    qr_url="$(printf '%s' "$info_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["url"])' 2>/dev/null)"
    qr_key="$(printf '%s' "$info_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["qrcode_key"])' 2>/dev/null)"
    if [ -z "$qr_key" ]; then
        err "获取登录二维码失败（generate 接口异常或网络不通）"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # 2) 渲染二维码并弹屏（弹不了就给链接）
    qrencode -o "$tmp_dir/qr.png" -s 12 -m 3 "$qr_url"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$tmp_dir/qr.png" >/dev/null 2>&1 && ok "二维码已弹出屏幕：$tmp_dir/qr.png"
    fi
    info "手机 B 站 App 扫描该二维码，或在「已登录 B 站的浏览器」打开下面链接点确认："
    echo "    $qr_url"
    info "二维码约 3 分钟内有效，等待扫码..."

    # 3) 轮询扫码状态（data.code：86101 未扫码 / 86090 待确认 / 0 成功 / 86038 过期）
    local poll_url resp status i
    poll_url="https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=${qr_key}"
    for i in $(seq 1 85); do
        sleep 2
        resp="$(curl -s --connect-timeout 10 --max-time 20 -D "$tmp_dir/headers.txt" "$poll_url")"
        status="$(printf '%s' "$resp" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["data"]["code"])
except Exception:
    print("-1")' 2>/dev/null)"
        if [ "$status" = "86090" ]; then
            info "已扫码，请在手机上点击「确认登录」..."
        elif [ "$status" = "0" ]; then
            printf '%s' "$resp" > "$tmp_dir/success.json"
            break
        elif [ "$status" = "86038" ]; then
            err "二维码已过期，请重新执行：bash $0 login"
            rm -rf "$tmp_dir"
            exit 1
        fi
    done
    if [ ! -f "$tmp_dir/success.json" ]; then
        err "等待超时（未扫码或未确认），请重新执行：bash $0 login"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # 4) 提取 cookie 写入凭据文件（优先响应体 cookie_info，兜底 Set-Cookie 头；不回显敏感值）
    local data_file
    data_file="$(dirname "$TARGET")/BBDown.data"
    if python3 - "$tmp_dir/success.json" "$data_file" << 'PYEOF'
import json, re, sys
src, dst = sys.argv[1], sys.argv[2]
cookies = {}
try:
    for c in json.load(open(src))['data'].get('cookie_info', {}).get('cookies', []):
        cookies[c['name']] = c['value']
except Exception:
    pass
if not cookies:
    hdr = open(src.rsplit('/', 1)[0] + '/headers.txt').read()
    for m in re.finditer(r'^set-cookie:\s*([^=;\s]+)=([^;]*)', hdr, re.M | re.I):
        cookies[m.group(1)] = m.group(2)
if not cookies.get('SESSDATA'):
    print('ERROR: 未拿到 SESSDATA（接口返回异常）')
    sys.exit(1)
need = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']
open(dst, 'w').write('; '.join(f'{k}={cookies[k]}' for k in need if k in cookies))
print('字段:', ','.join(k for k in need if k in cookies))
PYEOF
    then
        ok "登录成功，凭据已写入 $data_file"
        ok "验证：BBDown -info BV1GJ411x7h7 应出现 1080P 流，且无「尚未登录」提示"
    else
        err "凭据写入失败"
        rm -rf "$tmp_dir"
        exit 1
    fi
    rm -rf "$tmp_dir"
}

# ---------- 升级（重新下载最新版覆盖） ----------
do_update() {
    info "升级 = 重新下载最新版覆盖 ~/bin/BBDown"
    do_install
    do_verify
}

# ---------- 卸载 ----------
do_remove() {
    refuse_root
    title "卸载 BBDown"
    if [ -f "$TARGET" ]; then
        rm -f "$TARGET"
        ok "已删除 $TARGET"
    else
        warn "$TARGET 不存在，无需删除"
    fi
    # 凭据与二进制同目录（BBDown 用 AppContext.BaseDirectory 定位）
    if [ -f "$BIN_DIR/BBDown.data" ]; then
        read -rp "是否一并删除登录凭据 $BIN_DIR/BBDown.data（删除后需重新扫码）？[y/N] " ans
        if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
            rm -f "$BIN_DIR/BBDown.data"
            ok "已删除 $BIN_DIR/BBDown.data"
        else
            info "保留 $BIN_DIR/BBDown.data"
        fi
    fi
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

子命令（缺省 = all，执行 install → verify）：
  install   下载并安装 BBDown 到 ~/bin（无需 sudo）
  verify    校验安装结果（命令就位 / 版本输出 / ffmpeg 依赖）
  login     扫码登录 B 站账号（官方 API 直连，解锁 1080P+ 画质）
  update    升级到 GitHub 最新版（重新下载覆盖；升级后需重新 login）
  remove    卸载 BBDown（可选一并删除登录凭据 ~/bin/BBDown.data）
  all       依次执行 install → verify（推荐）
  help      显示本帮助

示例：
  bash $0              # 一键安装 + 校验
  bash $0 install      # 只安装
  bash $0 verify       # 只校验
  bash $0 login        # 扫码登录（依赖 qrencode，缺则先 sudo apt install -y qrencode）
  bash $0 remove       # 卸载

脚本外的常用命令（详见 docs/21）：
  BBDown "https://www.bilibili.com/video/BV1GJ411x7h7"   # 下载单个视频
  BBDown -info "BV1GJ411x7h7"                            # 只解析看画质
  BBDown "https://space.bilibili.com/12345"              # 批量下载 UP 主全部投稿
  BBDown "https://www.bilibili.com/medialist/detail/ml123"  # 下载收藏夹
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install) do_install ;;
        verify)  do_verify ;;
        login)   do_login ;;
        update)  do_update ;;
        remove)  do_remove ;;
        all)     do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
