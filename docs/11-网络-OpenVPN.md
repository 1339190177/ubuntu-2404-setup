# 11 · 网络 · OpenVPN 客户端（NetworkManager + 命令行）

> 把 .ovpn 配置（路由器/公司/自建服务端下发的均适用）迁到 Ubuntu 24.04 并稳定使用。
> 两种日常用法：NetworkManager 图形连接 + 命令行脚本。核心价值是**导入 NetworkManager 的两个坑**和 Ubuntu 24.04 的持久化现象。

---

## 文件布局

| 文件 | 用途 |
|------|------|
| `/etc/openvpn/client/xxx.ovpn` | OpenVPN 配置（命令行用） |
| `/etc/openvpn/client/auth.txt` | 用户名密码两行（权限 600） |
| `~/bin/vpn-connect.sh` | 启动/停止/状态脚本（模板见 [scripts/vpn-connect.sh.example](../scripts/vpn-connect.sh.example)） |
| NetworkManager 连接 | 图形界面托盘一键连断 |

## 安装步骤（重装可复用）

```bash
# 1. 配置目录
sudo mkdir -p /etc/openvpn/client

# 2. 放置 .ovpn（从服务端管理页/管理员处获取）
sudo cp YourClient.ovpn /etc/openvpn/client/xxx.ovpn

# 3. 创建凭据文件（两行：用户名、密码）
sudo tee /etc/openvpn/client/auth.txt >/dev/null <<'EOF'
<你的用户名>
<你的密码>
EOF
sudo chmod 600 /etc/openvpn/client/auth.txt

# 4. 让 .ovpn 引用凭据文件（命令行方式需要）
sudo sed -i 's|^auth-user-pass$|auth-user-pass /etc/openvpn/client/auth.txt|' /etc/openvpn/client/xxx.ovpn
```

## 方式 1：NetworkManager 图形连接（日常推荐）

```bash
# 导入原始 .ovpn —— ⚠️ 两个坑（实测）：
# 坑 1：必须 sudo 导入。普通用户导入会落到 /run/NetworkManager/...（tmpfs，重启全丢）
# 坑 2：必须用「裸 auth-user-pass」的原始 ovpn 导入；
#       带 auth 文件路径的改版会让 NM 识别不出密码认证，得到残缺配置
sudo nmcli connection import type openvpn file YourClient.ovpn

# 推荐关闭开机自动连 + 不接管默认网关（按需调整）
sudo nmcli con mod OpenVPN-Client connection.autoconnect no \
     ipv4.never-default yes ipv6.method disable

# 凭据入库（连接时不弹密码框）
sudo nmcli con mod OpenVPN-Client +vpn.data "username=<你的用户名>, password-flags=0"
sudo nmcli con mod OpenVPN-Client vpn.secrets "password=<你的密码>"
```

之后右上角网络图标 → VPN → 一键连接/断开。改密一条命令更新：
`sudo nmcli con mod OpenVPN-Client vpn.secrets "password=新密码"`（同时更新 auth.txt 第二行）。

**Ubuntu 24.04 持久化现象（不是故障）**：NM 导入后，连接会持久化为
`/etc/netplan/90-NM-<uuid>.yaml`（passthrough 机制），CA 证书被抽到
`/root/.cert/nm-openvpn/`——这两处看着意外，属正常行为，别手动清理。

## 方式 2：命令行（更可控）

```bash
# 前台调试（实时日志，Ctrl+C 断开）
sudo openvpn --config /etc/openvpn/client/xxx.ovpn

# 或用模板脚本管理（拷贝 scripts/vpn-connect.sh.example 到 ~/bin/）
sudo ~/bin/vpn-connect.sh start    # 后台连接
sudo ~/bin/vpn-connect.sh status   # 状态
sudo ~/bin/vpn-connect.sh stop     # 断开
```

## 连不上时的排查顺序

1. **服务器可达性**：

```bash
ping -c 3 <VPN服务器IP>
nc -zv <VPN服务器IP> <端口>
```

ping/nc 都超时 → 服务器没开 / 防火墙拦截 / 当前网络不允许。

2. **看日志**：`tail -f /var/log/openvpn-xxx.log` 或前台跑看实时输出。

3. **常见错误对照**：

| 错误 | 原因 | 解决 |
|------|------|------|
| `TCP connection ... timeout` | 服务器连不上 | 查服务器/端口/网络 |
| `AUTH_FAILED` | 密码错；或账号被占用（单会话限制的共享号常见） | 核对凭据；换账号；同步更新 auth.txt 和 NM secrets |
| `VERIFY ERROR` | CA 证书不匹配 | 重新导出 .ovpn |
| `Inactivity timeout` | 连上了但没数据 | 路由/MTU 问题 |

## ⚠️ 安全提醒

- `auth.txt` 是明文密码，权限必须 600（仅 root 可读）
- `.ovpn` 和 `auth.txt` 不要提交进 git（`.gitignore` 已含 `*.ovpn` / `auth.txt`）
- 弱密码尽快在服务端改强
