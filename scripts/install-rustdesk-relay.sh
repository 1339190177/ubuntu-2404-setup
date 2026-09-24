#!/bin/bash
# ======================================================================
# install-rustdesk-relay.sh — RustDesk 自建中继（hbbs+hbbr 本机 Docker 部署）
#
# 背景（2026-09-01）：
#   云服务器 203.0.113.10 上的 RustDesk 服务（域名 relay.example.com，
#   hbbs=30006 / hbbr=30007）被临时关停约半月，域名解析也已失效。
#   过渡方案：hbbs/hbbr 部署到本机 Docker，经 frpc 穿透复用云上
#   30006/30007 端口（frps 与 RustDesk 同机但独立存活，实测正常），
#   各端客户端改个地址即可继续用。
#
# 架构（P2P 打洞成功时流量端到端直连，不经任何服务器；中继仅兜底）：
#   [任意主控端] ──► 云:30006 (hbbs tcp+udp) ──frp──► 本机:21116 hbbs
#                 ──► 云:30007 (hbbr tcp)    ──frp──► 本机:21117 hbbr
#
# ⚠️ 前提（2026-09-01 实测）：腾讯云安全组当前只放行了 63379/28800，
#   30006/30007 随云上服务停用一并被收走 → 需在控制台手动放行：
#     30006 TCP + UDP、30007 TCP
#
# 用 sudo 跑（建数据目录/root 属主需要；docker 本身免 sudo）。
# 对应文档：docs/24-工具-RustDesk自建中继.md
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与项目其它 install-*.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
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

# ---------- 配置 ----------
IMAGE="rustdesk/rustdesk-server:latest"
DATA_DIR="${REAL_HOME}/docker/rustdesk-server"          # ~/docker 是 data-root（属主 root）

PUB_IP="203.0.113.10"            # 云服务器（frps 所在，RustDesk 公网入口）
HBBS_PORT="30006"                  # 云上 hbbs 入口（tcp+udp）
HBRR_PORT="30007"                  # 云上 hbbr 入口（tcp）
L_HBBS="21116"                     # 本机 hbbs（tcp+udp 同端口）
L_HBBS_AUX="21115"                 # 本机 hbbs 辅助端口
L_HBBS_WS="21118"                  # 本机 hbbs websocket（web 客户端用）
L_HBRR="21117"                     # 本机 hbbr
L_HBRR_WS="21119"                  # 本机 hbbr websocket（web 客户端用）

FRPC_INI="${REAL_HOME}/project/base/frp/frpc/frpc.ini"
FRPC_CONTAINER="base-frpc-1"
FRPC_MARK="# 2026-09-01 RustDesk 自建中继过渡"   # frpc.ini 条目起始标记（remove 按此删到 EOF）

TOML="${REAL_HOME}/.config/rustdesk/RustDesk2.toml"    # 本机 RustDesk 客户端配置

# 云服务器旧配置（client cloud 切回用；域名解析恢复前不可用）
CLOUD_HBBS='relay.example.com:30006'
CLOUD_HBRR='relay.example.com:30007'
CLOUD_KEY='=0nI9MnSBBXY1sySp5USYVlYJ10ZNJ0SxYzU4k3NwgFMJJHe0IXQ4xGZpFjWxdjI6ISeltmIsIiI6ISawFmIsIyNwADMzoje5hnL4cjMycjNus2clRGdzVnciojI5FGblJnIsIiNwADMzoje5hnL4cjMycjNus2clRGdzVnciojI0N3boJye'

# ---------- 部署 hbbs/hbbr ----------
do_install() {
    need_docker
    title "部署 hbbs + hbbr（数据目录 $DATA_DIR）"

    if [ "$(id -u)" -ne 0 ]; then
        err "建数据目录需要 root（~/docker 属主是 root），请用 sudo 运行：sudo bash $0 $1"
        exit 1
    fi

    mkdir -p "$DATA_DIR"/{hbbs,hbbr}

    if docker ps -a --format '{{.Names}}' | grep -qx hbbs; then
        ok "hbbs 容器已存在，跳过（重建先：docker rm -f hbbs）"
    else
        docker run -d --name hbbs --restart always \
          -v "$DATA_DIR/hbbs:/root" \
          -p ${L_HBBS_AUX}:${L_HBBS_AUX} -p ${L_HBBS}:${L_HBBS} -p ${L_HBBS}:${L_HBBS}/udp -p ${L_HBBS_WS}:${L_HBBS_WS} \
          "$IMAGE" hbbs -r ${PUB_IP}:${HBRR_PORT} \
          || { err "hbbs 启动失败：docker logs hbbs"; exit 1; }
        ok "hbbs 已启动（本机 ${L_HBBS_AUX}/${L_HBBS} tcp+udp/${L_HBBS_WS}，下发中继 ${PUB_IP}:${HBRR_PORT}）"
    fi

    if docker ps -a --format '{{.Names}}' | grep -qx hbbr; then
        ok "hbbr 容器已存在，跳过（重建先：docker rm -f hbbr）"
    else
        docker run -d --name hbbr --restart always \
          -v "$DATA_DIR/hbbr:/root" \
          -p ${L_HBRR}:${L_HBRR} -p ${L_HBRR_WS}:${L_HBRR_WS} \
          "$IMAGE" hbbr \
          || { err "hbbr 启动失败：docker logs hbbr"; exit 1; }
        ok "hbbr 已启动（本机 ${L_HBRR}/${L_HBRR_WS}）"
    fi

    sleep 2
    do_key
}

# ---------- frp 映射 ----------
do_frp() {
    title "frpc 添加映射（云 ${HBBS_PORT}/${HBRR_PORT} → 本机 ${L_HBBS}/${L_HBRR}）"

    [ -f "$FRPC_INI" ] || { err "未找到 $FRPC_INI（frpc 部署见 ~/project/base）"; exit 1; }

    if grep -q "${REAL_USER}_hbbs_tcp_${HBBS_PORT}" "$FRPC_INI"; then
        ok "映射条目已存在，跳过"
    else
        cp "$FRPC_INI" "$FRPC_INI.bak.$(date +%Y%m%d)"
        cat >> "$FRPC_INI" << EOF

$FRPC_MARK（云上 hbbs/hbbr 已停，本机接管；云服务恢复后 remove 一键回退）
[${REAL_USER}_hbbs_tcp_${HBBS_PORT}]
type = tcp
local_ip = 192.168.1.13
local_port = ${L_HBBS}
remote_port = ${HBBS_PORT}

[${REAL_USER}_hbbs_udp_${HBBS_PORT}]
type = udp
local_ip = 192.168.1.13
local_port = ${L_HBBS}
remote_port = ${HBBS_PORT}

[${REAL_USER}_hbbr_${HBRR_PORT}]
type = tcp
local_ip = 192.168.1.13
local_port = ${L_HBRR}
remote_port = ${HBRR_PORT}
EOF
        ok "已追加 3 条映射（备份：$FRPC_INI.bak.*）"
    fi

    docker restart "$FRPC_CONTAINER" >/dev/null \
      && ok "已重启 $FRPC_CONTAINER" \
      || { err "frpc 重启失败"; exit 1; }
    sleep 5
    if tail -20 "$REAL_HOME/project/base/logs/frp/frpc.log" 2>/dev/null | grep -q "${REAL_USER}_hbbs_tcp_${HBBS_PORT}.*start proxy success"; then
        ok "frps 侧 proxy 注册成功"
    else
        warn "日志未见 proxy success，检查：tail ~/project/base/logs/frp/frpc.log"
    fi
}

# ---------- 公钥 ----------
do_key() {
    local pub
    pub=$(docker run --rm -v "$DATA_DIR:/mnt" --entrypoint cat alpine /mnt/hbbs/id_ed25519.pub 2>/dev/null)
    if [ -n "$pub" ]; then
        ok "hbbs 公钥（其他设备接入时填 Key 栏）："
        echo "      $pub"
    else
        warn "公钥读取失败（hbbs 未启动过？），文件：$DATA_DIR/hbbs/id_ed25519.pub"
    fi
}

# ---------- 客户端切换 ----------
get_pubkey() {
    docker run --rm -v "$DATA_DIR:/mnt" --entrypoint cat alpine /mnt/hbbs/id_ed25519.pub 2>/dev/null
}

set_client() {
    # $1=rendezvous $2=relay $3=key（空=删除 key 行）
    local rv="$1" relay="$2" key="$3"
    [ -f "$TOML" ] || { err "未找到 $TOML（RustDesk 未安装？见 docs/09）"; exit 1; }

    # ⚠️ 双配置源坑（2026-09-01 实测）：--service 由 root 跑，读
    # /root/.config/rustdesk/RustDesk2.toml，启动后会把 root 侧旧配置同步回写
    # 到用户侧 → 只改用户侧必被还原。两侧都要改，且必须先停服务再改。
    local root_toml="/root/.config/rustdesk/RustDesk2.toml"

    systemctl stop rustdesk 2>/dev/null \
      || { err "停服务失败（权限？），必须先：sudo systemctl stop rustdesk"; exit 1; }
    sleep 2

    for f in "$TOML" "$root_toml"; do
        [ -f "$f" ] || continue
        cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
        sed -i \
          -e "s|^rendezvous_server = .*|rendezvous_server = '${rv}'|" \
          -e "s|^custom-rendezvous-server = .*|custom-rendezvous-server = '${rv}'|" \
          -e "s|^relay-server = .*|relay-server = '${relay}'|" \
          "$f"
        if [ -n "$key" ]; then
            if grep -q '^key = ' "$f"; then
                sed -i "s|^key = .*|key = '${key}'|" "$f"
            else
                sed -i "/^\[options\]/a key = '${key}'" "$f"
            fi
        else
            sed -i "/^key = /d" "$f"
        fi
    done

    systemctl start rustdesk 2>/dev/null \
      && ok "已重启 rustdesk 服务（两侧配置同步修改）" \
      || warn "服务启动失败，手动执行：sudo systemctl start rustdesk"
}

do_client() {
    local mode="${1:-}"
    title "切换本机 RustDesk 客户端指向：${mode:-（未指定）}"

    case "$mode" in
        home)
            local key; key=$(get_pubkey)
            [ -n "$key" ] || { err "读不到 hbbs 公钥（先跑 install）"; exit 1; }
            set_client "${PUB_IP}:${HBBS_PORT}" "${PUB_IP}:${HBRR_PORT}" "$key"
            ok "已指向本机自建：ID=${PUB_IP}:${HBBS_PORT} 中继=${PUB_IP}:${HBRR_PORT}"
            info "主界面左下角应显示「服务就绪」；未就绪先检查安全组（见 docs/24）"
            ;;
        cloud)
            set_client "$CLOUD_HBBS" "$CLOUD_HBRR" "$CLOUD_KEY"
            ok "已切回云服务器（${CLOUD_HBBS}；域名解析恢复前不可用）"
            ;;
        official)
            # 删除全部自定义服务器配置 = 回 RustDesk 官方默认（rs-ny.rustdesk.com，慢）
            systemctl stop rustdesk 2>/dev/null || true
            sleep 2
            for f in "$TOML" /root/.config/rustdesk/RustDesk2.toml; do
                [ -f "$f" ] || continue
                cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
                sed -i -e "/^rendezvous_server = /d" \
                       -e "/^custom-rendezvous-server = /d" \
                       -e "/^relay-server = /d" \
                       -e "/^key = /d" "$f"
            done
            systemctl start rustdesk 2>/dev/null \
              && ok "已重启 rustdesk 服务（两侧配置已清理）" || true
            ok "已恢复官方默认服务器（国内速度慢，仅应急）"
            ;;
        *)
            err "用法：$0 client home|cloud|official"
            exit 1
            ;;
    esac
}

# ---------- 校验 ----------
port_open() { timeout 4 bash -c "echo > /dev/tcp/$1/$2" 2>/dev/null; }

do_verify() {
    need_docker
    title "全链路校验"

    # 1. 容器
    docker ps --filter name=hb --format 'table {{.Names}}\t{{.Status}}'
    for c in hbbs hbbr; do
        docker ps --format '{{.Names}}' | grep -qx "$c" \
          && ok "容器 $c 运行中" || err "容器 $c 未运行"
    done

    # 2. 本机端口
    for p in ${L_HBBS_AUX} ${L_HBBS} ${L_HBRR}; do
        port_open 127.0.0.1 "$p" && ok "本机 :$p 监听" || err "本机 :$p 未监听"
    done

    # 3. frp proxy 注册
    if tail -50 "$REAL_HOME/project/base/logs/frp/frpc.log" 2>/dev/null | grep -q "${REAL_USER}_hbbs_tcp_${HBBS_PORT}.*start proxy success"; then
        ok "frp proxy 注册正常"
    else
        warn "frpc 日志未见 rustdesk proxy（frp 子命令未跑或失败）"
    fi

    # 4. 公网入口（安全组是否放行）
    if port_open "$PUB_IP" "$HBBS_PORT"; then
        ok "公网 ${PUB_IP}:${HBBS_PORT}（hbbs）可达"
    else
        err "公网 ${PUB_IP}:${HBBS_PORT} 不通 → 大概率腾讯云安全组未放行（30006 TCP+UDP、30007 TCP）"
        info "控制台放行后重跑：sudo bash $0 verify"
    fi
    port_open "$PUB_IP" "$HBRR_PORT" \
      && ok "公网 ${PUB_IP}:${HBRR_PORT}（hbbr）可达" \
      || err "公网 ${PUB_IP}:${HBRR_PORT} 不通 → 同上，安全组放行"

    do_key
    info "客户端当前指向：$(grep -m1 '^rendezvous_server' "$TOML" 2>/dev/null || echo '（读不到配置）')"
}

# ---------- 日常 ----------
do_status() {
    docker ps -a --filter name=hb --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
    grep -E "^rendezvous_server|^relay-server" "$TOML" 2>/dev/null | sed 's/^/客户端: /'
    port_open "$PUB_IP" "$HBBS_PORT" && info "公网 hbbs：可达" || warn "公网 hbbs：不通"
}

do_logs() { docker logs "${1:-hbbs}" --tail "${2:-30}" 2>&1; }

# ---------- 卸载 ----------
do_remove() {
    title "卸载自建中继"
    [ "$(id -u)" -ne 0 ] && { err "请用 sudo 运行：sudo bash $0 remove"; exit 1; }

    docker rm -f hbbs hbbr 2>/dev/null && ok "已删容器 hbbs/hbbr"

    if [ -f "$FRPC_INI" ] && grep -qF "$FRPC_MARK" "$FRPC_INI"; then
        cp "$FRPC_INI" "$FRPC_INI.bak.$(date +%Y%m%d)"
        python3 - "$FRPC_INI" "$FRPC_MARK" << 'PYEOF'
import sys
path, mark = sys.argv[1], sys.argv[2]
s = open(path).read()
i = s.find(mark)
if i >= 0:
    open(path, 'w').write(s[:i].rstrip() + '\n')
    print(f'已删除标记后的全部条目: {path}')
PYEOF
        docker restart "$FRPC_CONTAINER" >/dev/null && ok "已重启 $FRPC_CONTAINER"
    else
        info "frpc.ini 无映射条目，跳过"
    fi

    read -rp "是否删除数据目录 $DATA_DIR（含服务器密钥对，删了所有客户端要重配 key）？[y/N] " ans
    if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR" && ok "已删除 $DATA_DIR"
    else
        info "保留数据：$DATA_DIR"
    fi
    info "客户端配置未动（切回：sudo bash $0 client cloud / official）"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

RustDesk 自建中继（hbbs+hbbr）—— 云服务器中继停用期间的过渡方案，
hbbs/hbbr 跑在本机 Docker，经 frpc 穿透复用云上 30006/30007 端口。

子命令：
  install         部署 hbbs/hbbr 容器（幂等，数据在 $DATA_DIR）
  frp             frpc.ini 添加公网映射（幂等）+ 重启 frpc
  verify          全链路校验（容器/本机端口/frp/公网入口/公钥）
  key             显示 hbbs 公钥（其他设备接入填这个）
  client home     本机客户端切到自建服务器（日常用这个）
  client cloud    切回云服务器（域名/服务恢复后）
  client official 切回官方服务器（应急，慢）
  status          容器 + 客户端指向 + 公网可达性
  logs [hbbs|hbbr] [行数]   看日志（默认 hbbs 30 行）
  remove          卸载（删容器 + frpc 条目；客户端配置不动）

首次部署：sudo bash $0 install && sudo bash $0 frp
  → 腾讯云控制台放行 30006 TCP+UDP、30007 TCP
  → sudo bash $0 client home

其他设备接入（家中电脑/手机）：
  RustDesk 设置 → 网络 → ID 服务器 ${PUB_IP}:${HBBS_PORT}
  中继服务器 ${PUB_IP}:${HBRR_PORT}，Key 填脚本 key 子命令显示的公钥
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-help}"
    case "$cmd" in
        install)   shift; do_install "$@" ;;
        frp)       do_frp ;;
        verify)    do_verify ;;
        key)       do_key ;;
        client)    shift; do_client "$@" ;;
        status)    do_status ;;
        logs)      shift; do_logs "$@" ;;
        remove)    do_remove ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
