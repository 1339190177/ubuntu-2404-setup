#!/bin/bash
# ======================================================================
# install-reader-docker.sh — 部署「阅读3服务器版」(hectorqin/reader) 网文阅读器
#
# 是什么：
#   开源、免费、无广告的自托管网文阅读器，浏览器访问 http://localhost:4395，
#   兼容 Legado（阅读 3.0）书源生态，支持书架/换源/听书/多端同步进度。
#
# 关键坑（2026-08-22 实测）：
#   1) 上游 hectorqin/reader 已于 2026-06 归档，GitHub README 被清空，
#      Docker Hub 官方镜像 hectorqin/reader 也已删除 → 直接拉报
#      "manifest unknown: 官方仓库可能已删除该镜像"
#      解法：改用社区转存镜像 ddsderek/reader（同源码构建，增加 PUID/PGID）
#   2) Docker Hub 直连超时；本机 daemon.json 里 4 个加速站实测只剩
#      docker.1ms.run 和 docker.m.daocloud.io 可用 → 脚本内置 fallback 链
#   3) 书源"文件导入"会触发 Vert.x 向容器根目录 /file-uploads 写临时文件，
#      容器用户(uid 1000)无权在 / 建目录 → AccessDeniedException 500
#      解法：显式挂载一个可写的 ./file-uploads:/file-uploads
#
# 功能：
#   1) 拉镜像（ddsderek/reader，加速站 fallback，成功后统一 retag）
#   2) 生成 /home/<user>/docker/reader/docker-compose.yml 并 up -d
#      （默认 127.0.0.1 仅本机访问；CPU≤1 核、内存≤1g 限额）
#   3) 自动导入书源（REST API /reader3/saveBookSources，XIU2 精品书源）
#   4) 生成桌面入口「阅读」+ 从本机服务下载应用图标
#   5) 校验：HTTP 200 + 端口绑定 + 资源限额 + 书源数（0 条会警告）
#   6) 卸载：down + 删数据（可选）+ 删桌面入口
#
# 适用：Ubuntu 24.04 + Docker（见 docs/13）
# 对应文档：docs/23-工具-网文阅读器.md
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与项目其它 install-*.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        err "未找到 docker 命令。请先安装 Docker（见 docs/13-开发-Docker部署迁移.md）"
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        err "docker daemon 不可用，请先启动：sudo systemctl start docker"
        exit 1
    fi
}

# 真实用户与家目录（脚本可能被 sudo 调用）
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")
REAL_GID=$(id -g "$REAL_USER")

# ---------- 配置 ----------
READ_PORT="${READ_PORT:-4395}"                 # 宿主机访问端口
READ_BIND="${READ_BIND:-127.0.0.1}"            # 仅本机访问（要手机访问改 0.0.0.0，见 docs/23）
CPU_LIMIT="${CPU_LIMIT:-1.0}"                  # CPU 核数上限
MEM_LIMIT="${MEM_LIMIT:-1g}"                   # 内存上限（JVM 会按容器限额自适应堆）
IMAGE="ddsderek/reader:latest"                 # 社区转存镜像（官方 hectorqin/reader 已删）
READER_DIR="${REAL_HOME}/docker/reader"        # 数据 + compose 落点
DESKTOP_FILE="${REAL_HOME}/.local/share/applications/yuedu-reader.desktop"
ICON_FILE="${REAL_HOME}/.local/share/icons/yuedu-reader.png"

# 书源订阅链接（XIU2 精品书源，22 条，2026-08-22 实测；fallback 依次尝试）
SOURCE_URLS=(
    "https://ghfast.top/https://raw.githubusercontent.com/XIU2/Yuedu/master/shuyuan"
    "https://bitbucket.org/xiu2/yuedu/raw/master/shuyuan"
)

# 镜像拉取链：直连 → 加速站（2026-08-22 实测仅这两个加速站活）
# 注意 daemon.json 里的 docker.xuanyuan.me / dockerproxy.com 已失效，勿加
MIRRORS=(
    ""
    "docker.1ms.run/"
    "docker.m.daocloud.io/"
)

# ---------- 步骤 1：拉镜像（带 fallback + retag） ----------
do_pull() {
    need_docker
    title "步骤 1 · 拉取镜像 $IMAGE"

    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        ok "镜像已存在：$IMAGE（跳过；要更新先 docker rmi $IMAGE）"
        return 0
    fi

    local prefix pulled=1
    for prefix in "${MIRRORS[@]}"; do
        local target="${prefix}${IMAGE}"
        if [ -z "$prefix" ]; then
            info "尝试直连 Docker Hub ..."
        else
            info "尝试加速站 ${prefix} ..."
        fi
        if docker pull "$target"; then
            if [ -n "$prefix" ]; then
                docker tag "$target" "$IMAGE"
                docker rmi "$target" >/dev/null
                ok "已拉取并重打标签为 $IMAGE"
            else
                ok "已直连拉取 $IMAGE"
            fi
            pulled=0
            break
        fi
        warn "${target} 拉取失败，换下一个源"
    done
    [ "$pulled" -eq 0 ] || { err "所有源均拉取失败，请检查网络后重试"; exit 1; }
}

# ---------- 步骤 2：写 compose 并启动 ----------
write_compose() {
    title "步骤 2 · 生成配置 $READER_DIR/docker-compose.yml"
    # ~/docker 是 Docker data-root，属主 root，普通用户建不了目录 → 必须 sudo 跑
    if ! mkdir -p "$READER_DIR"/{storage,log,file-uploads} 2>/dev/null; then
        err "无法创建 $READER_DIR（~/docker 属主是 root）"
        err "请用 sudo 运行：sudo bash $0"
        exit 1
    fi
    chown -R "$REAL_UID:$REAL_GID" "$READER_DIR"

    # cat 加引号定界符防止变量展开；端口用 sed 替换
    cat > "$READER_DIR/docker-compose.yml" << 'EOF'
services:
  reader:
    image: ddsderek/reader:latest
    container_name: reader
    restart: unless-stopped
    ports:
      # 仅本机访问（要手机/局域网访问改为 "0.0.0.0:__PORT__:8080"，安全取舍见 docs/23）
      - "__BIND__:__PORT__:8080"
    # 资源限额：JVM(8u191+) 按 1g 容器限额自适应堆，阅读器够用
    deploy:
      resources:
        limits:
          cpus: "__CPUS__"
          memory: __MEM__
    environment:
      - TZ=Asia/Shanghai
      # prod=单用户模式（自用推荐）；多用户改 prod_multuser 并加 SECUREKEY/INVITECODE
      - SPRING_PROFILES_ACTIVE=prod
      - PUID=__UID__
      - PGID=__GID__
    volumes:
      - ./storage:/storage        # 书源/书架/阅读进度（核心数据，勿删）
      - ./log:/log                # 应用日志
      # 坑：书源"文件导入"走 Vert.x 上传，默认写容器根 /file-uploads，
      # uid 1000 无权在 / 建目录 → 500 AccessDenied，必须显式挂出来
      - ./file-uploads:/file-uploads
EOF
    sed -i "s/__PORT__/${READ_PORT}/;s/__BIND__/${READ_BIND}/;s/__CPUS__/${CPU_LIMIT}/;s/__MEM__/${MEM_LIMIT}/;s/__UID__/${REAL_UID}/;s/__GID__/${REAL_GID}/" \
        "$READER_DIR/docker-compose.yml"
    chown "$REAL_UID:$REAL_GID" "$READER_DIR/docker-compose.yml"
    ok "compose 已生成（${READ_BIND}:${READ_PORT}，CPU≤${CPU_LIMIT}，内存≤${MEM_LIMIT}）"
}

do_up() {
    title "启动容器"
    (cd "$READER_DIR" && docker compose up -d) || { err "启动失败，查看日志：docker logs reader"; exit 1; }
    ok "容器已启动：reader（${READ_PORT} → 8080）"
}

# ---------- 步骤 3：桌面入口 ----------
write_desktop() {
    title "步骤 3 · 生成桌面入口「阅读」"

    mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"

    # 图标直接从本机运行中的服务取（前端自带），不走外网
    if curl -sf --max-time 10 "http://localhost:${READ_PORT}/img/icons/android-chrome-512x512.png" \
        -o "$ICON_FILE" && [ -s "$ICON_FILE" ]; then
        chown "$REAL_UID:$REAL_GID" "$ICON_FILE" 2>/dev/null || true
        ok "图标：$ICON_FILE"
    else
        rm -f "$ICON_FILE"
        warn "图标下载失败（服务未就绪？），桌面入口用默认图标"
    fi

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=阅读（网文）
Comment=阅读3服务器版 — 免费无广告网文阅读器
Exec=xdg-open http://localhost:${READ_PORT}
Icon=${ICON_FILE}
Terminal=false
Categories=Network;Literature;
EOF
    chown "$REAL_UID:$REAL_GID" "$DESKTOP_FILE" 2>/dev/null || true
    chmod +x "$DESKTOP_FILE"
    ok "桌面入口：$DESKTOP_FILE（应用列表搜「阅读」）"
}

# ---------- 书源查询/导入（REST API 前缀是 /reader3，别的前缀都 404） ----------
api() {
    curl -s -X POST "http://localhost:${READ_PORT}/reader3/$1" \
        -H 'Content-Type: application/json' "${@:2}"
}

# 坑：API 导书源/自动登录绕过了"登录初始化"，userConfig 文件不存在时
# 页面一加载就弹「没有备份文件,请修复」→ 缺则补一份空配置（已有则不碰，防覆盖）
init_user_config() {
    local r=$(curl -s --max-time 8 "http://localhost:${READ_PORT}/reader3/getUserConfig")
    if echo "$r" | grep -q '没有备份文件'; then
        api saveUserConfig -d '{}' | grep -q '"isSuccess":true' \
            && ok "已初始化用户配置（userConfig，消除「没有备份文件」弹窗）" \
            || warn "用户配置初始化失败，页面可能弹「没有备份文件,请修复」"
    fi
}

source_count() {
    api getBookSources -d '{}' 2>/dev/null | python3 -c "
import json,sys
try: print(len(json.load(sys.stdin)['data']))
except Exception: print(0)
"
}

do_sources() {
    title "导入/更新书源（XIU2 精品书源）"
    init_user_config
    local tmp=$(mktemp) ok=0
    for u in "${SOURCE_URLS[@]}"; do
        info "下载：$u"
        if timeout 30 curl -sL "$u" -o "$tmp" && python3 -c "import json;d=json.load(open('$tmp'));exit(0 if d else 1)" 2>/dev/null; then
            ok=1; break
        fi
        warn "下载失败或内容非法，换下一个链接"
    done
    [ "$ok" -eq 1 ] || { err "所有书源链接都失败，检查网络或手动在网页导入"; exit 1; }

    info "导入到 reader..."
    local resp=$(api saveBookSources --data-binary "@$tmp")
    rm -f "$tmp"
    echo "$resp" | grep -q '"isSuccess":true' \
        && ok "导入成功：$(echo "$resp" | grep -oE '(新增|更新)[0-9]+条书源' | tr '\n' ' ')" \
        || { err "导入失败：$resp"; exit 1; }
    info "当前书源总数：$(source_count)"
}

# ---------- 步骤 4：校验 ----------
do_verify() {
    title "步骤 4 · 校验"

    docker ps --filter name=reader --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    # 端口绑定检查：期望 ${READ_BIND}
    if docker port reader 8080 2>/dev/null | grep -q "^${READ_BIND}:"; then
        ok "端口绑定：${READ_BIND}:${READ_PORT}（$([ "${READ_BIND}" = "127.0.0.1" ] && echo '仅本机可访问' || echo '局域网可访问')）"
    else
        warn "端口绑定与期望 ${READ_BIND} 不符：$(docker port reader 8080 2>/dev/null | tr '\n' ' ')"
    fi

    # 资源限额检查
    local mem=$(docker inspect reader --format '{{.HostConfig.Memory}}' 2>/dev/null)
    local cpu=$(docker inspect reader --format '{{.HostConfig.NanoCpus}}' 2>/dev/null)
    if [ -n "$mem" ] && [ "$mem" != "0" ]; then
        ok "资源限额：CPU≤$(awk "BEGIN{print $cpu/1000000000}") 核，内存≤$(awk "BEGIN{printf \"%.0f\", $mem/1024/1024}")MB"
    else
        warn "未检测到资源限额（容器是旧配置创建的？重跑 install 应用新 compose）"
    fi

    info "等待 HTTP 就绪（最多 60s）..."
    local i html
    for i in $(seq 1 30); do
        html=$(curl -s --max-time 3 "http://localhost:${READ_PORT}/" || true)
        if echo "$html" | grep -q '<title>阅读</title>'; then
            ok "HTTP 200，页面标题「阅读」— 服务正常"
            info "访问入口：http://localhost:${READ_PORT}"
            local n=$(source_count)
            if [ "${n:-0}" -gt 0 ]; then
                ok "书源已配置：${n} 条"
            else
                warn "未配置书源（0 条）— 搜索将搜不到任何书！"
                info "  一键导入：sudo bash $0 sources"
                info "  手动导入：网页「导入书源 → 网络导入」粘贴书源链接（见 docs/23）"
            fi
            return 0
        fi
        sleep 2
    done
    err "服务未就绪，排查：docker logs reader"
    exit 1
}

# ---------- 日常运维 ----------
do_status() {
    (cd "$READER_DIR" && docker compose ps)
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://localhost:${READ_PORT}/" || true
    info "书源：$(source_count) 条"
}

do_logs() {
    docker logs reader --tail "${1:-50}" "${2:-}" 2>&1 | less -R
}

do_stop()   { (cd "$READER_DIR" && docker compose stop);  ok "已停止"; }
do_start()  { (cd "$READER_DIR" && docker compose start); ok "已启动：http://localhost:${READ_PORT}"; }
do_restart(){ (cd "$READER_DIR" && docker compose restart); ok "已重启"; }

# ---------- 卸载 ----------
do_remove() {
    title "卸载阅读器"
    (cd "$READER_DIR" && docker compose down) 2>/dev/null
    rm -fv "$DESKTOP_FILE"; ok "已删桌面入口"

    read -rp "是否删除书源/书架等数据 $READER_DIR ？[y/N] " ans
    if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "$READER_DIR"
        ok "已删除 $READER_DIR（书源、书架、进度全部清空）"
    else
        info "保留数据：$READER_DIR（重装后进度还在）"
    fi

    read -rp "是否删除镜像 $IMAGE ？[y/N] " ans
    if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        docker rmi "$IMAGE" 2>/dev/null && ok "已删除镜像" || warn "镜像删除失败（可能正被使用）"
    fi
    ok "卸载完成"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：bash $0 [子命令]

子命令（缺省 = all，执行 pull → compose → verify → sources → 桌面入口）：
  pull     拉镜像（ddsderek/reader，加速站 fallback）
  install  生成 $READER_DIR/docker-compose.yml 并启动
  sources  导入/更新书源（XIU2 精品书源 22 条，REST API 自动导入）
  desktop  生成桌面入口「阅读」+ 图标
  verify   校验容器/端口绑定/资源限额/书源数
  status   查看容器状态与书源数
  logs     看日志（默认 50 行）
  stop     停止容器
  start    启动容器
  restart  重启容器
  remove   卸载（down + 可选删数据/镜像）
  all      全流程（推荐）
  help     显示本帮助

环境变量：
  READ_PORT   宿主机端口，默认 4395
  READ_BIND   绑定地址，默认 127.0.0.1（仅本机）；手机访问改 0.0.0.0
  CPU_LIMIT   CPU 上限（核），默认 1.0
  MEM_LIMIT   内存上限，默认 1g

示例：
  bash $0                    # 一键部署（含导入书源）
  READ_PORT=4400 bash $0     # 换端口部署
  bash $0 sources            # 重装后单独补导书源
  bash $0 stop               # 停止
  bash $0 remove             # 卸载

装完后的日常用法：
  桌面/应用列表点「阅读」，或浏览器开 http://localhost:4395
  书源已由脚本自动导入；要换书源包：网页「导入书源」或改脚本 SOURCE_URLS 后重跑 sources
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-all}"
    case "$cmd" in
        pull)    do_pull ;;
        install) need_docker; do_pull; write_compose; do_up ;;
        sources) do_sources ;;
        desktop) write_desktop ;;
        verify)  do_verify ;;
        status)  do_status ;;
        logs)    shift; do_logs "$@" ;;
        stop)    do_stop ;;
        start)   do_start ;;
        restart) do_restart ;;
        remove)  do_remove ;;
        all)     need_docker; do_pull; write_compose; do_up; do_verify; do_sources; write_desktop ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
