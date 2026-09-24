#!/bin/bash
# ======================================================================
# docker-deploy.sh — Docker 环境一键部署（Ubuntu 24.04）
#
# 功能：
#   1) 安装 Docker CE + Compose（阿里云 apt 源）
#   2) 配置 data-root 到 /home + 国内镜像加速
#   3) 配置内核参数 vm.overcommit_memory=1（Redis 需要）
#   4) 配置 hosts 域名解析（dev.private.com → 127.0.0.1）
#   5) 查看当前 Docker 状态
#   6) 卸载 Docker（还原）
#
# 设计：data-root 放 /home（ext4，空间大），避开系统盘
# 适用：当前机器，详见 docs/13-开发-Docker部署迁移.md
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
die()   { err "$*"; exit 1; }

# ---------- 基础环境 ----------
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")
DOCKER_DATA="/home/${REAL_USER}/docker/data"

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "需要 root 权限。请用 sudo 运行："
        echo "    sudo bash $0"
        exit 1
    fi
}

# ---------- 步骤 1：安装 Docker ----------
install_docker() {
    title "步骤 1/4：安装 Docker CE（阿里云源）"

    if command -v docker >/dev/null 2>&1; then
        warn "检测到已安装 Docker：$(docker --version)"
        read -rp "是否重新安装/升级？[y/N] " ans
        [ "${ans:-N}" != "y" ] && { info "跳过安装"; return; }
    fi

    info "卸载旧版本（如有）..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y "$pkg" >/dev/null 2>&1 || true
    done

    info "配置阿里云 Docker apt 源..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null

    info "安装 Docker CE + Compose 插件..."
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin || die "安装失败"

    info "用户 $REAL_USER 加入 docker 组（重新登录后免 sudo）..."
    usermod -aG docker "$REAL_USER"

    ok "Docker 安装完成：$(docker --version)"
}

# ---------- 步骤 2：配置 data-root + 镜像加速 ----------
configure_docker() {
    title "步骤 2/4：配置 data-root + 镜像加速"

    info "创建数据目录：$DOCKER_DATA"
    mkdir -p "$DOCKER_DATA"
    chown "$REAL_USER:$REAL_USER" "$DOCKER_DATA"

    info "写入 /etc/docker/daemon.json ..."
    tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "data-root": "$DOCKER_DATA",
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

    info "重启 Docker 生效..."
    systemctl daemon-reload
    systemctl restart docker
    sleep 2

    ok "data-root: $(docker info 2>/dev/null | grep 'Docker Root Dir' | awk '{print $3,$4}')"
    ok "镜像加速已配置（$(docker info 2>/dev/null | grep -c 'Registry Mirror') 个）"
}

# ---------- 步骤 3：内核参数 ----------
configure_kernel() {
    title "步骤 3/4：内核参数（Redis 需要）"

    info "设置 vm.overcommit_memory=1 ..."
    sysctl vm.overcommit_memory=1 >/dev/null

    if grep -q 'vm.overcommit_memory' /etc/sysctl.conf; then
        sed -i 's/.*vm.overcommit_memory.*/vm.overcommit_memory = 1/' /etc/sysctl.conf
    else
        echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
    fi
    ok "已写入 /etc/sysctl.conf（重启不丢）"
}

# ---------- 步骤 4：hosts 解析 ----------
configure_hosts() {
    title "步骤 4/4：hosts 域名解析"

    local changed=0
    if ! grep -q 'dev.private.com' /etc/hosts; then
        echo '127.0.0.1 dev.private.com' >> /etc/hosts
        ok "已添加：127.0.0.1 dev.private.com"
        changed=1
    else
        warn "dev.private.com 已存在，跳过"
    fi

    if ! grep -q 'dev.example.com' /etc/hosts; then
        echo '172.20.0.4 dev.example.com' >> /etc/hosts
        ok "已添加：172.20.0.4 dev.example.com"
        changed=1
    else
        warn "dev.example.com 已存在，跳过"
    fi

    [ $changed -eq 0 ] && info "hosts 无需修改"
}

# ---------- 状态查看 ----------
show_status() {
    title "Docker 当前状态"
    echo "版本：$(docker --version 2>/dev/null || echo '未安装')"
    echo "Compose：$(docker compose version --short 2>/dev/null || echo '未安装')"
    echo ""
    if command -v docker >/dev/null 2>&1; then
        echo "服务状态：$(systemctl is-active docker)"
        echo "data-root：$(docker info 2>/dev/null | grep 'Docker Root Dir' | awk '{print $3,$4}')"
        echo ""
        echo "--- 容器 ---"
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
        echo ""
        echo "--- 磁盘占用 ---"
        docker system df 2>/dev/null
    fi
}

# ---------- 卸载 ----------
uninstall_docker() {
    title "卸载 Docker"
    warn "这将删除 Docker 及所有容器/镜像/数据！"
    read -rp "确认卸载？输入 YES 继续：" ans
    [ "$ans" != "YES" ] && { info "已取消"; return; }

    systemctl stop docker docker.socket 2>/dev/null
    apt-get remove -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>/dev/null
    apt-get autoremove -y 2>/dev/null

    read -rp "是否删除数据目录 $DOCKER_DATA？[y/N] " ans2
    [ "${ans2:-N}" = "y" ] && rm -rf "$DOCKER_DATA"

    info "保留配置 /etc/docker/daemon.json 和 apt 源，如需删除请手动处理"
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat <<EOF
docker-deploy.sh — Docker 环境一键部署（Ubuntu 24.04）

用法：
    sudo bash $0               # 交互菜单
    sudo bash $0 install       # 直接执行完整安装（步骤 1-4）
    sudo bash $0 status        # 查看 Docker 状态
    sudo bash $0 uninstall     # 卸载 Docker

部署业务服务（安装完成后）：
    详见 docs/13-开发-Docker部署迁移.md「迁移工程」「UID 统一」章节

注意：
    - data-root 放在 $DOCKER_DATA（/home 分区，空间充足）
    - 容器统一以 UID 1000 运行，详见文档「踩坑记录」第 4 条
EOF
}

# ---------- 主入口 ----------
main() {
    cd "$(dirname "$0")"

    case "${1:-}" in
        install)
            need_root
            install_docker
            configure_docker
            configure_kernel
            configure_hosts
            title "部署完成"
            ok "Docker 环境已就绪。接下来请按文档迁移工程并启动服务。"
            echo "    文档：docs/13-开发-Docker部署迁移.md"
            ;;
        status)
            show_status
            ;;
        uninstall)
            need_root
            uninstall_docker
            ;;
        --help|-h|help)
            show_help
            ;;
        "")
            need_root
            title "Docker 环境部署管理"
            echo "当前用户：$REAL_USER (uid=$REAL_UID)"
            echo "数据目录：$DOCKER_DATA"
            echo ""
            echo "  1) 一键部署（安装+配置，推荐）"
            echo "  2) 仅安装 Docker"
            echo "  3) 仅配置 data-root + 镜像加速"
            echo "  4) 查看状态"
            echo "  5) 卸载 Docker"
            echo "  0) 退出"
            echo ""
            read -rp "请选择 [0-5]: " choice
            case "$choice" in
                1) install_docker; configure_docker; configure_kernel; configure_hosts
                   title "部署完成"; ok "Docker 环境已就绪" ;;
                2) install_docker ;;
                3) configure_docker ;;
                4) show_status ;;
                5) uninstall_docker ;;
                0) exit 0 ;;
                *) err "无效选择"; exit 1 ;;
            esac
            ;;
        *)
            err "未知参数：$1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
