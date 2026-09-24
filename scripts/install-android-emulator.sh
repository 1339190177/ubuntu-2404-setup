#!/bin/bash
# ======================================================================
# install-android-emulator.sh — Android 官方模拟器（AVD）轻量安装
#
# 功能：
#   1) 下载 commandline-tools（dl.google.com 直连实测 9.9MB/s）到 ~/Android/Sdk
#   2) sdkmanager 安装 platform-tools(adb) / emulator / android-35 镜像
#   3) 创建 AVD 虚拟设备 dev35（Pixel 6 / Android 15 / google_apis x86_64）
#   4) KVM 权限检查（logind ACL + kvm 组双保险）
#   5) 桌面启动器 + ~/bin 命令软链（adb / emulator / sdkmanager / avdmanager）
#   6) verify：启动 AVD → 等开机 → adb 截图，全链路自检
#
# 背景：雷电 / 夜神 / MuMu 均无 Linux 版（Windows 专属 VirtualBox 方案），
#       Linux 开发调试用 Google 官方 AVD 是正统路径，KVM 加速开机仅数秒。
#
# 适用：Ubuntu 24.04（KVM 可用 + X11/Wayland 均可）
# 对应文档：docs/35-工具-安卓模拟器.md
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

# sudo 下还原真实用户（脚本可能被 sudo 调用）
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ---------- 版本与路径（固定实测值） ----------
CLT_BUILD="13114758"                 # commandline-tools v13.0（2024-11）
CLT_SHA256="7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"
SDK_ROOT="${REAL_HOME}/Android/Sdk"
AVD_NAME="dev35"
API="android-35"
IMAGE="system-images;android-35;google_apis;x86_64"
DL_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CLT_BUILD}_latest.zip"

need_java() {
    if ! command -v java >/dev/null 2>&1; then
        err "缺少 Java 17+（sdkmanager 依赖）。先执行：sudo apt install -y openjdk-17-jdk"
        exit 1
    fi
}

# ---------- 步骤 1：下载 + 解压 commandline-tools ----------
do_download() {
    title "步骤 1/6 · 下载 commandline-tools（build ${CLT_BUILD}）"
    need_java
    local zip="/tmp/commandlinetools-linux-${CLT_BUILD}_latest.zip"

    if [ -f "$zip" ] && echo "${CLT_SHA256}  $zip" | sha256sum -c --quiet 2>/dev/null; then
        ok "已存在且校验通过，跳过下载：$zip"
    else
        # aria2 多线程优先（本机已装），curl 兜底
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -x8 -s8 --console-log-level=warn --summary-interval=0 \
                   -d /tmp -o "commandlinetools-linux-${CLT_BUILD}_latest.zip" "$DL_URL" \
            || { err "aria2c 下载失败"; exit 1; }
        else
            curl -fSL -o "$zip" "$DL_URL" || { err "curl 下载失败"; exit 1; }
        fi
        echo "${CLT_SHA256}  $zip" | sha256sum -c --quiet \
            || { err "SHA-256 校验失败，文件可能损坏，删除后重试"; rm -f "$zip"; exit 1; }
        ok "下载完成且校验通过"
    fi

    mkdir -p "${SDK_ROOT}/cmdline-tools"
    rm -rf /tmp/clt-extract
    unzip -q "$zip" -d /tmp/clt-extract
    rm -rf "${SDK_ROOT}/cmdline-tools/latest"
    mv /tmp/clt-extract/cmdline-tools "${SDK_ROOT}/cmdline-tools/latest"
    ok "已解压到 ${SDK_ROOT}/cmdline-tools/latest"
}

# ---------- 步骤 2：接受许可 + 安装 SDK 包 ----------
do_sdk_packages() {
    title "步骤 2/6 · 安装 SDK 包（system image 约 1.4G，走 dl.google.com）"
    local sdkm="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
    export ANDROID_HOME="${SDK_ROOT}"

    yes | "$sdkm" --licenses > /tmp/android-licenses.log 2>&1
    ok "许可已全部接受"

    "$sdkm" "platform-tools" "emulator" "platforms;${API}" "${IMAGE}" \
        || { err "SDK 包安装失败，查看上方输出"; exit 1; }
    ok "已安装：platform-tools(adb) / emulator / ${API} / system-image"
}

# ---------- 步骤 3：创建 AVD ----------
do_avd() {
    title "步骤 3/6 · 创建 AVD 虚拟设备 ${AVD_NAME}（Pixel 6 / Android 15）"
    export ANDROID_HOME="${SDK_ROOT}"
    if "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}$"; then
        warn "AVD ${AVD_NAME} 已存在，跳过创建"
        return 0
    fi
    echo no | "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager" create avd \
        -n "$AVD_NAME" -k "$IMAGE" -d pixel_6 \
        || { err "AVD 创建失败"; exit 1; }
    ok "已创建：~/.android/avd/${AVD_NAME}.avd"
}

# ---------- 步骤 4：KVM 权限 ----------
do_kvm() {
    title "步骤 4/6 · KVM 硬件加速权限检查"
    if [ ! -e /dev/kvm ]; then
        err "/dev/kvm 不存在：BIOS 需开启 SVM/VMX 虚拟化"
        exit 1
    fi
    # 通道 1：logind 对活动桌面会话用户的 ACL（无需任何配置）
    if getfacl /dev/kvm 2>/dev/null | grep -q "user:${REAL_USER}:rw"; then
        ok "logind ACL 已授予 ${REAL_USER} 读写权（活动桌面会话自动生效）"
    fi
    # 通道 2：kvm 组（持久保障，不依赖会话活跃状态）
    if id -nG "$REAL_USER" | tr ' ' '\n' | grep -qx kvm || getent group kvm | grep -q "\b${REAL_USER}\b"; then
        ok "已在 kvm 组"
    else
        info "加入 kvm 组（需 sudo，重登后生效；此前 ACL 已可用）..."
        sudo usermod -aG kvm "$REAL_USER" \
            && ok "已加入 kvm 组（注销重登后生效）" \
            || warn "sudo 失败——不影响当前桌面会话使用（ACL 已授权）"
    fi
}

# ---------- 步骤 5：桌面启动器 + 命令软链 ----------
do_launcher() {
    title "步骤 5/6 · 桌面启动器 + ~/bin 软链"
    local icon="${REAL_HOME}/.local/share/icons/android-emulator.png"
    local desk="${REAL_HOME}/.local/share/applications/android-emulator.desktop"

    # 图标：已有则复用；无则用 Pillow 画（无 Pillow 就跳过，用通用图标）
    if [ ! -f "$icon" ]; then
        mkdir -p "${REAL_HOME}/.local/share/icons"
        python3 - << 'PYEOF' 2>/dev/null || true
from PIL import Image, ImageDraw
S=128; img=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(img)
green=(61,220,132,255); dark=(7,34,20,255)
d.rounded_rectangle([4,4,S-4,S-4],radius=28,fill=(16,24,20,255))
d.pieslice([34,34,94,94],start=180,end=360,fill=green)
d.rounded_rectangle([34,62,94,104],radius=8,fill=green)
d.rounded_rectangle([22,64,32,96],radius=5,fill=green)
d.rounded_rectangle([96,64,106,96],radius=5,fill=green)
d.rounded_rectangle([46,100,56,116],radius=5,fill=green)
d.rounded_rectangle([72,100,82,116],radius=5,fill=green)
d.ellipse([50,50,58,58],fill=dark); d.ellipse([70,50,78,58],fill=dark)
d.line([44,36,36,20],fill=green,width=5); d.line([84,36,92,20],fill=green,width=5)
img.save('~/.local/share/icons/android-emulator.png')
PYEOF
    fi
    local icon_line="Icon=computer"
    [ -f "$icon" ] && icon_line="Icon=${icon}"

    cat > "$desk" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Android 模拟器 (${AVD_NAME})
Comment=AVD 官方模拟器 · Pixel 6 / Android 15 · adb 调试用
Exec=${SDK_ROOT}/emulator/emulator -avd ${AVD_NAME}
${icon_line}
Terminal=false
StartupWMClass=qemu-system-x86_64
Categories=Development;
EOF
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$desk" 2>/dev/null
    update-desktop-database "${REAL_HOME}/.local/share/applications" 2>/dev/null
    ok "桌面启动器：$desk"

    mkdir -p "${REAL_HOME}/bin"
    ln -sf "${SDK_ROOT}/platform-tools/adb"                    "${REAL_HOME}/bin/adb"
    ln -sf "${SDK_ROOT}/emulator/emulator"                     "${REAL_HOME}/bin/emulator"
    ln -sf "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"   "${REAL_HOME}/bin/sdkmanager"
    ln -sf "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager"   "${REAL_HOME}/bin/avdmanager"
    ok "命令可用：adb / emulator / sdkmanager / avdmanager（~/bin 已在 PATH）"
}

# ---------- 步骤 6：验证（启动 → 开机 → adb 截图） ----------
do_verify() {
    title "步骤 6/6 · 全链路验证（启动 ${AVD_NAME}）"
    local adb_bin="${SDK_ROOT}/platform-tools/adb"
    export ANDROID_HOME="${SDK_ROOT}"

    info "启动模拟器（窗口将出现在桌面）..."
    nohup "${SDK_ROOT}/emulator/emulator" -avd "$AVD_NAME" -no-snapshot-save -no-audio -gpu host \
        > "/tmp/emu-${AVD_NAME}.log" 2>&1 &
    local emu_pid=$!

    info "等待 Android 开机（KVM 加速，通常 10~60 秒）..."
    local booted=0
    for i in $(seq 1 36); do
        local boot
        boot=$("$adb_bin" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if [ "$boot" = "1" ]; then booted=1; break; fi
        sleep 5
    done
    if [ "$booted" != "1" ]; then
        err "开机超时（3 分钟）。查看日志：/tmp/emu-${AVD_NAME}.log"
        kill "$emu_pid" 2>/dev/null
        exit 1
    fi
    ok "开机完成（约 $((i*5)) 秒）"

    "$adb_bin" devices | grep -q "emulator-" && ok "adb 已连接" || { err "adb 未发现设备"; exit 1; }

    "$adb_bin" exec-out screencap -p > "/tmp/${AVD_NAME}-verify.png" \
        && ok "截图已保存：/tmp/${AVD_NAME}-verify.png"

    echo
    info "常用调试命令："
    echo "    adb install -r xxx.apk          # 装 APK（开发主场景）"
    echo "    adb install --abi arm64-v8a -r xxx.apk   # ARM-only APK 走翻译层"
    echo "    adb logcat -s YourTag           # 看日志"
    echo "    adb emu kill                    # 关闭模拟器"
    ok "验证全部通过，环境可用"
}

# ---------- 状态 ----------
do_status() {
    title "Android 模拟器环境状态"
    echo "SDK 路径：${SDK_ROOT}"
    if [ -d "${SDK_ROOT}" ]; then
        du -sh "${SDK_ROOT}" 2>/dev/null
        ls "${SDK_ROOT}" 2>/dev/null | tr '\n' ' '; echo
    else
        warn "SDK 未安装"
    fi
    echo
    echo "AVD 列表："
    [ -x "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager" ] \
        && ANDROID_HOME="${SDK_ROOT}" "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -E "Name|Device|Based" || echo "  （无）"
    echo
    echo "adb 设备："
    [ -x "${SDK_ROOT}/platform-tools/adb" ] && "${SDK_ROOT}/platform-tools/adb" devices | tail -n +2
    return 0
}

# ---------- 卸载 ----------
do_uninstall() {
    title "卸载 Android 模拟器环境"
    "${SDK_ROOT}/platform-tools/adb" emu kill >/dev/null 2>&1
    pkill -f "qemu-system-x86_64.*${AVD_NAME}" 2>/dev/null
    sleep 2
    rm -rf "${SDK_ROOT}"
    rm -rf "${REAL_HOME}/.android/avd/${AVD_NAME}.avd" "${REAL_HOME}/.android/avd/${AVD_NAME}.avd.qcow2"
    rm -f  "${REAL_HOME}/.local/share/applications/android-emulator.desktop" \
           "${REAL_HOME}/.local/share/icons/android-emulator.png" \
           "${REAL_HOME}/bin/adb" "${REAL_HOME}/bin/emulator" \
           "${REAL_HOME}/bin/sdkmanager" "${REAL_HOME}/bin/avdmanager" \
           "/tmp/commandlinetools-linux-${CLT_BUILD}_latest.zip"
    warn "kvm 组成员身份未移除（无害，如需彻底清理：sudo gpasswd -d ${REAL_USER} kvm）"
    ok "已卸载：SDK 目录 / AVD / 启动器 / 软链"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

子命令（缺省 = install，执行步骤 1-5；verify 单独跑）：
  install    下载+安装全部组件并建 AVD（不自动启动）
  verify     启动 ${AVD_NAME} 并全链路验证（开机/adb/截图）
  kvm        仅检查/修复 KVM 权限（logind ACL + kvm 组）
  status     查看安装状态 / AVD 列表 / adb 设备
  uninstall  全部卸载（SDK/AVD/启动器/软链）
  help       显示本帮助

示例：
  bash $0 install && bash $0 verify   # 全新安装并验证
  bash $0 status                      # 日常查看
  adb install -r myapp.apk            # 开发调试：装 APK 到模拟器

固定版本（实测 2026-09-23）：
  commandline-tools ${CLT_BUILD} / emulator 37.1.11 / ${API} google_apis x86_64
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-install}"
    case "$cmd" in
        install)   do_download; do_sdk_packages; do_avd; do_kvm; do_launcher
                   info "安装完成。验证：bash $0 verify" ;;
        verify)    do_verify ;;
        kvm)       do_kvm ;;
        status)    do_status ;;
        uninstall) do_uninstall ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
