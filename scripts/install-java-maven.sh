#!/bin/bash
# ======================================================================
# install-java-maven.sh — 一键安装 Java 17 (OpenJDK) + Maven 开发环境
#
# 功能：
#   1) apt 安装 openjdk-17-jdk + maven
#   2) 写入阿里云 Maven 镜像到 ~/.m2/settings.xml（加速依赖拉取）
#   3) 在 ~/.bashrc 追加动态 JAVA_HOME（升级 JDK 小版本自动跟随）
#   4) 可选：编译验证当前项目
#
# 适用：Ubuntu 24.04，为 RuoYi-Vue-Plus 系列 Spring Boot 项目准备本地开发环境
# 对应文档：docs/15-开发-Java与Maven环境.md
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

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "apt 安装需要 root 权限。请用 sudo 运行："
        echo "    sudo bash $0 [install|mirror|java_home|verify|all]"
        exit 1
    fi
}

# sudo 下还原真实用户（脚本可能被 sudo 调用）
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ---------- 步骤 1：apt 安装 ----------
do_install() {
    need_root
    title "步骤 1/4 · apt 安装 OpenJDK 17 + Maven"
    apt update
    apt install -y openjdk-17-jdk maven
    ok "安装完成"
    echo
    java -version
    mvn -version | head -3
}

# ---------- 步骤 2：阿里云镜像 ----------
write_mirror() {
    title "步骤 2/4 · 配置 Maven 阿里云镜像"
    local m2_dir="${REAL_HOME}/.m2"
    local settings="${m2_dir}/settings.xml"
    mkdir -p "$m2_dir"

    if [ -f "$settings" ]; then
        # 备份原文件
        cp -v "$settings" "${settings}.bak.$(date +%Y%m%d%H%M%S)"
        warn "已存在 $settings，已备份后再覆盖"
    fi

    cat > "$settings" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <localRepository>${user.home}/.m2/repository</localRepository>
  <mirrors>
    <mirror>
      <id>aliyun-public</id>
      <name>Aliyun Public</name>
      <url>https://maven.aliyun.com/repository/public</url>
      <mirrorOf>central</mirrorOf>
    </mirror>
    <mirror>
      <id>aliyun-central</id>
      <name>Aliyun Central</name>
      <url>https://maven.aliyun.com/repository/central</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
    <mirror>
      <id>aliyun-spring</id>
      <name>Aliyun Spring</name>
      <url>https://maven.aliyun.com/repository/spring</url>
      <mirrorOf>spring</mirrorOf>
    </mirror>
    <mirror>
      <id>aliyun-spring-plugin</id>
      <name>Aliyun Spring Plugin</name>
      <url>https://maven.aliyun.com/repository/spring-plugin</url>
      <mirrorOf>spring-plugin</mirrorOf>
    </mirror>
    <mirror>
      <id>aliyun-gradle-plugin</id>
      <name>Aliyun Gradle Plugin</name>
      <url>https://maven.aliyun.com/repository/gradle-plugin</url>
      <mirrorOf>gradle-plugin</mirrorOf>
    </mirror>
    <mirror>
      <id>aliyun-google</id>
      <name>Aliyun Google</name>
      <url>https://maven.aliyun.com/repository/google</url>
      <mirrorOf>google</mirrorOf>
    </mirror>
  </mirrors>
  <profiles>
    <profile>
      <id>jdk-17</id>
      <activation>
        <activeByDefault>true</activeByDefault>
        <jdk>17</jdk>
      </activation>
      <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <maven.compiler.compilerVersion>17</maven.compiler.compilerVersion>
      </properties>
    </profile>
  </profiles>
</settings>
XML
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$settings"
    ok "已写入 $settings"
}

# ---------- 步骤 3：JAVA_HOME ----------
write_java_home() {
    title "步骤 3/4 · 配置 JAVA_HOME 到 ~/.bashrc"
    local bashrc="${REAL_HOME}/.bashrc"
    local marker="# Java / Maven 环境（OpenJDK 17 via apt）"

    if grep -qF "$marker" "$bashrc"; then
        warn "$bashrc 中已存在 JAVA_HOME 配置，跳过"
        return 0
    fi

    cat >> "$bashrc" << 'EOF'

# Java / Maven 环境（OpenJDK 17 via apt）
# 动态解析 JAVA_HOME：apt 装的 java 是 /usr/lib/jvm/java-17-openjdk-amd64/bin/java
# 用 readlink 反解出真实路径，升级 JDK 小版本后自动跟随，无需手改
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH=$JAVA_HOME/bin:$PATH
EOF
    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$bashrc"
    ok "已追加到 $bashrc（新开终端生效）"
}

# ---------- 步骤 4：编译验证 ----------
do_verify() {
    title "步骤 4/4 · 编译验证"
    local project="~/win_e/projects/demo-business/demo-business-server"
    if [ ! -d "$project" ]; then
        warn "默认项目路径不存在：$project"
        read -rp "请输入要验证的项目根目录（留空跳过）: " project
        [ -z "$project" ] && { info "跳过验证"; return 0; }
    fi
    info "在 $project 下执行 mvn clean compile -DskipTests -P dev（首次较慢）"
    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    (cd "$project" && mvn clean compile -DskipTests -P dev -B) || {
        err "编译失败，请检查输出"
        return 1
    }
    ok "编译通过，环境可用"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = all，执行全部步骤）：
  install    仅 apt 安装 openjdk-17-jdk + maven
  mirror     仅写入 ~/.m2/settings.xml 阿里云镜像
  java_home  仅在 ~/.bashrc 追加 JAVA_HOME
  verify     编译验证默认项目（RuoYi-Vue-Plus 示例业务）
  all        依次执行 install → mirror → java_home → verify（推荐）
  help       显示本帮助

示例：
  sudo bash $0              # 一键全套
  sudo bash $0 install      # 只装包
  bash $0 mirror            # 只重写镜像配置（不需 sudo）
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        install)   do_install ;;
        mirror)    write_mirror ;;
        java_home) write_java_home ;;
        verify)    do_verify ;;
        all)       do_install; write_mirror; write_java_home; do_verify ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
