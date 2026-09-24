#!/bin/bash
# ======================================================================
# install-mysql-client.sh — 一键安装 MySQL 命令行客户端
#
# 功能：
#   1) apt 安装 mysql-client（Ubuntu 24.04 实际拉 MariaDB 客户端，命令兼容
#      mysql / mysqldump / mysqladmin）
#   2) 校验安装结果（which mysql / mysql --version）
#   3) 可选：交互式连接远端 MySQL 做连通性测试
#
# 适用：Ubuntu 24.04，为后端开发/运维在终端直连远端 MySQL 准备命令行工具
# 对应文档：docs/19-工具-MySQL客户端.md
#
# 备注：
#   - 只装客户端，不装服务端（服务端在 Docker 里，见 docs/13）
#   - 不写 my.cnf 固化连接信息，避免把密码/连接串带进仓库
#   - 卸载：sudo bash $0 remove
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-java-maven.sh / install-apipost.sh 一致） ----------
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
    title "步骤 1/2 · apt 安装 mysql-client"
    info "说明：mysql-client 是个 metapackage，Ubuntu 24.04 下实际拉 MySQL 8.0 官方客户端"
    info "      （mysql-client-8.0 + mysql-client-core-8.0），命令 mysql / mysqldump / mysqladmin。"
    apt update
    apt install -y mysql-client
    ok "安装完成"
    echo
    mysql --version
}

# ---------- 步骤 2：校验 ----------
do_verify() {
    title "步骤 2/2 · 安装校验"

    # 1) 命令是否就位
    if command -v mysql >/dev/null 2>&1; then
        ok "命令可用：$(which mysql) → $(readlink -f "$(which mysql)")"
    else
        err "mysql 命令未找到，安装可能失败"
        exit 1
    fi

    # 2) 版本输出
    if mysql --version 2>/dev/null; then
        ok "客户端可正常执行"
    else
        err "mysql --version 执行失败"
        exit 1
    fi

    # 3) 配套工具
    for tool in mysqldump mysqladmin; do
        if command -v "$tool" >/dev/null 2>&1; then
            ok "附带工具：$tool → $(which $tool)"
        else
            warn "未找到 $tool（通常一起装上，缺失请检查 apt 输出）"
        fi
    done

    echo
    ok "校验通过。连接示例："
    echo "    mysql -h <远端IP>  -P <端口>  -u <用户名>  -p <数据库名>"
    echo "    mysqldump -h <远端IP> -u <用户名> -p <数据库名> > dump.sql"
}

# ---------- 交互式连接测试 ----------
do_connect() {
    title "交互式连接远端 MySQL（连通性测试）"
    if ! command -v mysql >/dev/null 2>&1; then
        err "mysql 命令未安装，请先执行：sudo bash $0 install"
        exit 1
    fi

    local host port user db
    read -rp "远端主机 IP [127.0.0.1]: " host
    host="${host:-127.0.0.1}"
    read -rp "端口 [3306]: " port
    port="${port:-3306}"
    read -rp "用户名: " user
    [ -z "$user" ] && { err "用户名不能为空"; exit 1; }
    read -rp "数据库名（可留空）: " db

    info "执行：mysql -h $host -P $port -u $user -p ${db:+"<数据库>"}"
    info "（-p 后无参数，回车后会提示输入密码，密码不回显）"
    echo
    if [ -n "$db" ]; then
        mysql -h "$host" -P "$port" -u "$user" -p "$db"
    else
        mysql -h "$host" -P "$port" -u "$user" -p
    fi

    # 退出码 0 即连通
    if [ $? -eq 0 ]; then
        echo
        ok "连接成功（退出码 0）"
    fi
}

# ---------- 卸载 ----------
do_remove() {
    need_root
    title "卸载 mysql-client"
    apt remove --purge -y mysql-client
    # mariadb-client 是 mysql-client 的实际依赖，询问是否一并清理
    if dpkg -l mariadb-client >/dev/null 2>&1; then
        warn "检测到 mariadb-client（mysql-client 的实际实现包）仍在"
        read -rp "是否一并卸载 mariadb-client？[y/N] " ans
        if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
            apt remove --purge -y mariadb-client
            ok "已卸载 mariadb-client"
        else
            info "保留 mariadb-client（mysql/mysqldump 命令仍可用）"
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
  install   仅 apt 安装 mysql-client（需 sudo）
  verify    仅校验安装结果（命令是否就位、版本输出）
  connect   交互式连接远端 MySQL，做连通性测试
  remove    卸载 mysql-client（需 sudo）
  all       依次执行 install → verify（推荐）
  help      显示本帮助

示例：
  sudo bash $0              # 一键安装 + 校验
  sudo bash $0 install      # 只装包
  bash    $0 verify         # 只校验
  bash    $0 connect        # 连接远端测试
  sudo bash $0 remove       # 卸载

连接远端的通用命令（脚本外直接用）：
  mysql -h 192.168.1.10 -P 3306 -u root -p business_db
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install) do_install ;;
        verify)  do_verify ;;
        connect) do_connect ;;
        remove)  do_remove ;;
        all)     do_install; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
