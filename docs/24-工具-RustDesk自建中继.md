# 24 · 工具 · RustDesk 自建中继（hbbs/hbbr）

> 默认公共中继在国外，国内用 RustDesk 慢/卡。自建 hbbs（ID 服务器）+ hbbr（中继）后，
> 客户端全部走自己的服务器。两条路线：**有公网 IP 服务器直接部署**；**没有则本机 Docker + frp 穿透**。

---

## 方案对比

| 方案 | 可达性 | 成本/代价 |
|------|--------|----------|
| **A. 本机部署 + frp 穿透** | 任意公网端可达（复用穿透服务器端口） | 零新增成本；中继流量多一跳 |
| **B. 本机部署 + VPN 直连** | 仅 VPN 内可达 | 最快，但要求每台客户端配 VPN |
| C. 公网服务器部署 | 公网可达 | 要有一台带公网 IP 的服务器 |

A 与 B 可叠加：客户端若在 VPN 内，直接填内网地址（如 `192.168.1.100:21116`）不走公网更快。
A 方案中继带宽 = min(本机宽带上行, 穿透服务器带宽)，两台设备打洞失败时才走中继；同 NAT/VPN 内会直连，不占中继。

## 路线 C：公网服务器部署（有服务器的情况，最简）

```bash
# 在公网服务器执行
docker run --name hbbs -p 21115:21115 -p 21116:21116 -p 21116:21116/udp -p 21118:21118 \
  -v $(pwd)/hbbs:/root -itd rustdesk/rustdesk-server hbbs
docker run --name hbbr -p 21117:21117 -p 21119:21119 \
  -v $(pwd)/hbbr:/root -itd rustdesk/rustdesk-server hbbr
```

客户端网络设置：ID 服务器 `<服务器IP>`、中继服务器 `<服务器IP>`。

## 路线 A：本机 Docker + frp 穿透（无公网 IP 的情况）

**前提**：本机能跑 Docker；有一台公网服务器跑 frps（或任何 TCP/UDP 穿透服务）。

一键脚本：[scripts/install-rustdesk-relay.sh](../scripts/install-rustdesk-relay.sh)（本机 hbbs/hbbr 容器 + frpc 映射 + 客户端配置一条龙，含回退子命令）。

**原理**：hbbs/hbbr 跑在本机 Docker，frp 把穿透服务器上的两个端口（示例 30006/30007）转到本机：

```ini
# frpc.ini 追加（frps 侧需放行对应端口）
[hbbs_tcp_30006]
type = tcp
local_ip = 192.168.1.100     # 本机内网 IP
local_port = 21116
remote_port = 30006

[hbbs_udp_30006]
type = udp
local_ip = 192.168.1.100
local_port = 21116
remote_port = 30006

[hbbr_30007]
type = tcp
local_ip = 192.168.1.100
local_port = 21117
remote_port = 30007
```

**关键坑（实测）**：hbbs 的 **UDP 21116 必须映射**（ID 注册/打洞走 UDP），只映 TCP 会出现"客户端注册不上/一直走中继"。穿透服务器安全组记得放行中继动态端口段（hbbr 中继会随机用 30000-40000 段，按需放行 TCP+UDP）。

## 客户端接入

```ini
# ~/.config/rustdesk/RustDesk2.toml（每台客户端）
[options]
custom-rendezvous-server = '<穿透服务器IP或域名>:30006'
relay-server = '<穿透服务器IP或域名>:30007'
key = '<hbbs-公钥>'
```

- `key` 是 hbbs 首次启动生成的 `id_ed25519.pub` 内容（容器卷 `hbbs/` 目录下）——填了它客户端才认你的服务器，防 ID 冒用
- VPN 内客户端可改填 `192.168.1.100:21116/21117` 直连本机，不走穿透更快
- 改完配置重启 RustDesk 生效；`hbbs` 日志出现 `update_pk <设备ID>` 即注册成功

## 公钥查看

```bash
docker run --rm -v $(pwd)/hbbs:/mnt --entrypoint cat alpine /mnt/id_ed25519.pub
```

## 常见问题

**Q1：怎么判断当前会话走中继还是直连？**
hbbr 容器日志有流量 = 走中继；无流量但连接正常 = 打洞直连。远程协助偶发卡顿多半在中继，属 A 方案预期（多一跳）。

**Q2：穿透服务器只有部分端口可用？**
remote_port 换成任意放行端口，客户端配置同步改即可；但 UDP 的 ID 端口不能省（见上）。

**Q3：想切回/切走？**
脚本 `remove` 子命令一键清理本机容器与 frpc 映射；客户端把 `custom-rendezvous-server`/`relay-server` 清空即回官方公共服务器。

**Q4：多台被控设备？**
都填同一套服务器配置即可，ID 由 hbbs 统一分配，互不影响。
