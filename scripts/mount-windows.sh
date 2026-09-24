#!/bin/bash
# ======================================================================
# mount-windows.sh — Ubuntu 双系统固定挂载 Windows NTFS 数据盘
#
# 功能：
#   1) 安装并固定挂载（写入 /etc/fstab，开机自动挂载）
#   2) 只做测试挂载（临时，重启失效，不改 fstab）
#   3) 卸载已挂载的 Windows 分区
#   4) 查看当前挂载状态
#   5) 还原 /etc/fstab（撤销本次修改）
#
# 设计：用 UUID + ntfs-3g 驱动 + uid/gid=当前用户，一劳永逸解决权限问题
# 适用：当前机器 (nvme0n1p5、nvme0n1p6 两个 NTFS 数据盘)
# ======================================================================

set -u   # 引用未定义变量直接报错（set -e 在交互菜单里不合适，改用手动检查）

# ---------- 颜色与基础工具 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

# ---------- 基础环境检查 ----------
need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "需要 root 权限。请用 sudo 运行："
        echo "    sudo bash $0"
        exit 1
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1 || { err "缺少命令：$1，请先安装"; exit 1; }
}

# 目标分区（这台机器的两个 NTFS 数据盘）
DEV_P5="/dev/nvme0n1p5"
DEV_P6="/dev/nvme0n1p6"
# 挂载点放在主文件夹，便于在文件管理器和应用"打开文件"对话框中直接访问
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
MNT_D="${REAL_HOME}/win_d"
MNT_E="${REAL_HOME}/win_e"
DRIVER="ntfs-3g"
REAL_UID=$(id -u "$REAL_USER")
REAL_GID=$(id -g "$REAL_USER")

# 挂载选项：uid/gid 给所有权，dmask/fmask 给权限，big_writes 提速，
#           windows_names 防止生成 Windows 不兼容文件名，nofail 防开机卡死
MOUNT_OPTS="uid=${REAL_UID},gid=${REAL_GID},dmask=022,fmask=022,big_writes,windows_names,nofail,defaults"

# ---------- 菜单 ----------
show_menu() {
    title "Windows NTFS 数据盘 挂载管理"
    echo "当前用户：$REAL_USER (uid=$REAL_UID, gid=$REAL_GID)"
    echo "目标分区：$DEV_P5 → $MNT_D"
    echo "          $DEV_P6 → $MNT_E"
    echo "驱动：$DRIVER"
    echo
    echo "  1) 一劳永逸：固定挂载 + 写入 /etc/fstab（开机自动挂载）【推荐】"
    echo "  2) 临时测试挂载（不改 fstab，重启失效）"
    echo "  3) 卸载已挂载的 Windows 分区"
    echo "  4) 查看当前挂载状态"
    echo "  5) 还原 /etc/fstab（撤销本次脚本写入的行）"
    echo "  q) 退出"
    echo
}

# ---------- 检查目标分区是否存在 ----------
check_partitions() {
    local missing=0
    for d in "$DEV_P5" "$DEV_P6"; do
        if [ ! -b "$d" ]; then
            err "找不到块设备：$d"
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && {
        warn "可用的 NTFS 分区如下："
        lsblk -f | grep -i ntfs || true
        return 1
    }
    return 0
}

# ---------- 取 UUID ----------
get_uuid() {
    blkid -s UUID -o value "$1"
}

# ---------- 检查分区是否已挂载 ----------
is_mounted() {
    mount | grep -q "^$1 on "
}

# ---------- 卸载 udisks2 自动挂载 ----------
unmount_if_mounted() {
    local dev="$1"
    if is_mounted "$dev"; then
        local mp
        mp=$(mount | grep "^$dev on " | awk '{print $3}')
        info "卸载 $dev (当前挂载在 $mp)"
        umount "$dev" && ok "已卸载 $dev" || { err "卸载 $dev 失败"; return 1; }
    fi
    return 0
}

# ---------- 测试单个分区可写 ----------
test_write() {
    local mp="$1"
    local testfile="$mp/.permission_test_$(date +%s).txt"
    if echo "permission test $(date)" > "$testfile" 2>/dev/null; then
        ok "$mp 可读写 ($(ls -l "$testfile" | awk '{print $1" "$3" "$4}'))"
        rm -f "$testfile"
        return 0
    else
        err "$mp 不可写！可能 NTFS 处于脏/休眠状态"
        warn "请去 Windows 关闭快速启动 (管理员 PowerShell 执行: powercfg /h off) 后完全关机再试"
        return 1
    fi
}

# ---------- 操作 1：固定挂载 + 写 fstab ----------
do_install() {
    title "一劳永逸：固定挂载 + 写入 /etc/fstab"
    check_partitions || return 1
    check_cmd "$DRIVER"
    check_cmd blkid

    local uuid5 uuid6
    uuid5=$(get_uuid "$DEV_P5")
    uuid6=$(get_uuid "$DEV_P6")

    if [ -z "$uuid5" ] || [ -z "$uuid6" ]; then
        err "无法获取分区 UUID，请检查分区表"
        return 1
    fi
    info "UUID: $DEV_P5 = $uuid5"
    info "UUID: $DEV_P6 = $uuid6"

    # 防止重复写入 fstab
    if grep -qE "^UUID=$uuid5\s" /etc/fstab || grep -qE "^UUID=$uuid6\s" /etc/fstab; then
        warn "/etc/fstab 中已存在这两个分区的挂载项，避免重复写入。"
        warn "如需重新配置，请先执行菜单 5 还原，或手动编辑 /etc/fstab。"
        return 1
    fi

    # 1) 卸载已有挂载
    title "步骤 1/4：卸载现有挂载"
    unmount_if_mounted "$DEV_P5" || return 1
    unmount_if_mounted "$DEV_P6" || return 1

    # 2) 创建挂载点
    title "步骤 2/4：创建挂载点"
    for mp in "$MNT_D" "$MNT_E"; do
        if [ -d "$mp" ]; then
            info "$mp 已存在"
        else
            mkdir -p "$mp" && ok "已创建 $mp"
        fi
    done

    # 3) 挂载 + 测试可写
    title "步骤 3/4：挂载并验证读写权限"
    info "挂载选项：$MOUNT_OPTS"
    mount -t "$DRIVER" -o "$MOUNT_OPTS" "UUID=$uuid5" "$MNT_D" \
        || { err "挂载 $DEV_P5 失败"; return 1; }
    mount -t "$DRIVER" -o "$MOUNT_OPTS" "UUID=$uuid6" "$MNT_E" \
        || { err "挂载 $DEV_P6 失败"; umount "$MNT_D"; return 1; }

    test_write "$MNT_D" || { umount "$MNT_D" "$MNT_E"; return 1; }
    test_write "$MNT_E" || { umount "$MNT_D" "$MNT_E"; return 1; }

    # 4) 备份并写入 fstab
    title "步骤 4/4：备份并写入 /etc/fstab"
    local bak="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a /etc/fstab "$bak"
    ok "已备份 /etc/fstab → $bak"

    {
        echo ""
        echo "# ---- Windows NTFS 数据盘（由 mount-windows.sh 添加 $(date +%F)）----"
        echo "UUID=$uuid5 $MNT_D $DRIVER $MOUNT_OPTS 0 0"
        echo "UUID=$uuid6 $MNT_E $DRIVER $MOUNT_OPTS 0 0"
    } >> /etc/fstab
    ok "已写入 /etc/fstab"

    # 验证：卸载后用 mount -a 重新挂载，能成功说明配置正确
    title "验证 fstab 配置（卸载后用 mount -a 重挂）"
    umount "$MNT_D" "$MNT_E"
    if mount -a; then
        ok "mount -a 成功"
    else
        err "mount -a 失败！fstab 可能有误，已自动还原备份"
        cp -a "$bak" /etc/fstab
        return 1
    fi

    title "完成 ✅"
    show_status
    echo
    warn "重要提醒：建议去 Windows 关闭「快速启动」"
    echo "   管理员 PowerShell 执行: powercfg /h off"
    echo "   否则 Windows 休眠后 Ubuntu 可能只能只读挂载"
}

# ---------- 操作 2：临时测试挂载 ----------
do_test_mount() {
    title "临时测试挂载（不改 fstab）"
    check_partitions || return 1
    check_cmd "$DRIVER"

    local uuid5 uuid6
    uuid5=$(get_uuid "$DEV_P5")
    uuid6=$(get_uuid "$DEV_P6")

    unmount_if_mounted "$DEV_P5" || return 1
    unmount_if_mounted "$DEV_P6" || return 1

    mkdir -p "$MNT_D" "$MNT_E"

    info "挂载选项：$MOUNT_OPTS"
    mount -t "$DRIVER" -o "$MOUNT_OPTS" "UUID=$uuid5" "$MNT_D" \
        || { err "挂载 $DEV_P5 失败"; return 1; }
    mount -t "$DRIVER" -o "$MOUNT_OPTS" "UUID=$uuid6" "$MNT_E" \
        || { err "挂载 $DEV_P6 失败"; umount "$MNT_D"; return 1; }

    test_write "$MNT_D" || return 1
    test_write "$MNT_E" || return 1

    title "临时挂载完成 ✅（重启后失效，不会改 fstab）"
    show_status
}

# ---------- 操作 3：卸载 ----------
do_unmount() {
    title "卸载 Windows 分区"
    local any=0
    for mp in "$MNT_D" "$MNT_E"; do
        if mountpoint -q "$mp"; then
            umount "$mp" && ok "已卸载 $mp" || err "卸载 $mp 失败"
            any=1
        fi
    done
    # 也卸载 /media 下 udisks2 的自动挂载
    for dev in "$DEV_P5" "$DEV_P6"; do
        if is_mounted "$dev"; then
            unmount_if_mounted "$dev"
            any=1
        fi
    done
    [ "$any" -eq 0 ] && warn "当前没有需要卸载的 Windows 分区"
}

# ---------- 操作 4：查看状态 ----------
show_status() {
    title "当前挂载状态"
    echo "----- 目标分区挂载情况 -----"
    local found=0
    for dev in "$DEV_P5" "$DEV_P6"; do
        if is_mounted "$dev"; then
            mount | grep "^$dev on " | sed 's/^/  /'
            found=1
        fi
    done
    [ "$found" -eq 0 ] && warn "目标分区当前未挂载"

    echo
    echo "----- /mnt 下挂载点 -----"
    for mp in "$MNT_D" "$MNT_E"; do
        if mountpoint -q "$mp"; then
            ok "$mp (已挂载)"
            echo "    可用空间: $(df -h "$mp" | awk 'NR==2{print $4" / "$2}')"
        else
            warn "$mp (未挂载)"
        fi
    done

    echo
    echo "----- /etc/fstab 中相关行 -----"
    if grep -qE "($MNT_D|$MNT_E)" /etc/fstab; then
        grep -nE "($MNT_D|$MNT_E)" /etc/fstab | sed 's/^/  /'
    else
        warn "fstab 中没有写入挂载项（即未配置开机自动挂载）"
    fi
}

# ---------- 操作 5：还原 fstab ----------
do_restore() {
    title "还原 /etc/fstab"
    echo "可用的备份文件："
    local backups
    backups=$(ls -1t /etc/fstab.bak.* 2>/dev/null)
    if [ -z "$backups" ]; then
        warn "没有找到任何 /etc/fstab.bak.* 备份"
        return 1
    fi
    # 列出供选择
    local i=1
    declare -a arr
    while IFS= read -r f; do
        arr[i]="$f"
        echo "  $i) $f"
        i=$((i+1))
    done <<< "$backups"
    echo "  0) 取消"
    read -rp "选择要还原的备份编号 [0]: " choice
    choice=${choice:-0}
    if [ "$choice" = "0" ]; then
        info "已取消"
        return 0
    fi
    local target="${arr[$choice]:-}"
    if [ -z "$target" ]; then
        err "无效的选择"
        return 1
    fi
    # 先卸载，避免还原后状态不一致
    do_unmount
    cp -a "$target" /etc/fstab
    ok "已还原 /etc/fstab ← $target"
    warn "如需应用，可执行: sudo mount -a"
}

# ---------- 主循环 ----------
main() {
    need_root
    check_cmd mount
    check_cmd umount
    check_cmd blkid

    # 处理命令行直接传参：sudo bash mount-windows.sh install
    if [ $# -ge 1 ]; then
        case "$1" in
            install)  do_install; exit $? ;;
            test)     do_test_mount; exit $? ;;
            unmount)  do_unmount; exit $? ;;
            status)   show_status; exit $? ;;
            restore)  do_restore; exit $? ;;
        esac
    fi

    while true; do
        show_menu
        read -rp "请选择 [1-5/q]: " choice
        case "$choice" in
            1) do_install ;;
            2) do_test_mount ;;
            3) do_unmount ;;
            4) show_status ;;
            5) do_restore ;;
            q|Q)
                info "再见 👋"
                break
                ;;
            *)
                warn "无效选项：$choice"
                ;;
        esac
        echo
        read -rp "按回车继续..." _
    done
}

main "$@"
