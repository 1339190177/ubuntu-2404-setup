# 33 · 工具 · MQTTX 桌面客户端

> 一句话：安装 EMQ 官方 MQTTX 桌面版（MQTT 5.0 可视化客户端），图形化连接远端 EMQX broker 收发/调试消息。

---

## 背景

本机 MQTT 服务端（EMQX）在远端 `db-server.example.com`（10.0.0.78），见 docs/15 —— **本地只装客户端，不起服务端**。此前缺一个可视化 MQTT 客户端：调试主题订阅、查看报文 payload、测 QoS/保留消息这些事，命令行 `mosquitto_sub/pub` 不直观。

选型：**MQTTX**，EMQ 官方出品（与服务端 EMQX 同门），跨平台桌面 GUI，支持 MQTT 3.1/3.1.1/5.0，多连接并行、payload 格式化（JSON/Hex）、定时/脚本收发。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04 LTS x86_64 |
| 安装方式 | 官方 deb（apt install ./xxx.deb） |
| 安装版本 | **MQTTX 1.13.1**（2026-09-22 实测，最新 release） |
| 程序位置 | `/opt/MQTTX/mqttx`（Electron 应用） |
| 桌面入口 | `/usr/share/applications/mqttx.desktop`，Super 键搜 "MQTTX" |
| 包名 | `mqttx`（dpkg 登记，约 86M） |
| 服务端 | 远端 EMQX `10.0.0.78:1883`（不在本篇范围） |

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
sudo bash scripts/install-mqttx.sh           # 下载 → 安装 → 校验 → 探测远端端口
```

### 手工步骤（理解原理用）

```bash
# 1. 下载 deb（EMQ 国内 CDN，与 GitHub 资产同名同内容）
curl -fL -o ~/Downloads/MQTTX_1.13.1_amd64.deb \
    "https://www.emqx.com/zh/downloads/MQTTX/v1.13.1/MQTTX_1.13.1_amd64.deb"

# 2. 安装（apt 装 deb，自动处理依赖；MQTTX 为纯 Electron 无额外依赖）
sudo apt install -y ~/Downloads/MQTTX_1.13.1_amd64.deb

# 3. 验证
dpkg -l mqttx && ls /opt/MQTTX/mqttx
```

## 参数 / 配置详解

### 下载源：为什么用 EMQ CDN 不用 GitHub

同一个文件（`MQTTX_1.13.1_amd64.deb`，85.8M）两个官方源，国内速度天差地别：

| 源 | 直链 | 实测速度（2026-09-22） |
|----|------|----------------------|
| **EMQ CDN（推荐）** | `https://www.emqx.com/zh/downloads/MQTTX/v<版本>/MQTTX_<版本>_amd64.deb` | ~470KB/s，约 3 分钟完成 |
| GitHub release | `https://github.com/emqx/MQTTX/releases/download/v<版本>/MQTTX_<版本>_amd64.deb` | ~50KB/s，**300 秒超时只拉到 9M，拉不完** |

EMQ 官网下载页（mqttx.app）只列 Windows 资产的直链，Linux deb 需按上表模式拼 URL（文件名与 GitHub 资产同名）。脚本已内置双源：CDN 失败自动退 GitHub。

### 首次连接远端 EMQX

启动 MQTTX 后新建连接（`+ New Connection`）：

| 配置项 | 值 |
|--------|-----|
| Name | 随意，如 `内网服务器-emqx` |
| Client ID | 默认自动生成即可（前缀 `mqttx_`） |
| Host | `mqtt://10.0.0.78` |
| Port | `1883` |
| Username/Password | 有账号就填，EMQX 默认允许匿名则留空 |

连上后：左上角 `New Subscription` 订阅主题（如 `#` 收全部），中间面板分上下两栏（上=发布，下=订阅到的消息流）。

### MQTTX 桌面版 ≠ mqttx-cli

EMQ 有两个 MQTTX 产物，别混：

| 产物 | 形态 | 安装方式 |
|------|------|---------|
| **MQTTX 桌面版（本篇）** | Electron GUI | deb / AppImage |
| mqttx-cli | 命令行 `mqttx pub/sub/bench` | npm / 独立二进制 |

要脚本化压测/自动化用 CLI，要看报文调试用桌面版。本机只装桌面版。

## 验证方法

```bash
# 1. 安装就位
bash scripts/install-mqttx.sh verify
# 期望：dpkg 登记版本 + /opt/MQTTX/mqttx + desktop 三项全 OK

# 2. 远端端口连通
bash scripts/install-mqttx.sh connect
# 期望：10.0.0.78:1883 可达

# 3. 图形化终验（感官项，人工）
#    Super 键搜索 "MQTTX" 启动 → 新建连接 10.0.0.78:1883 → 连上后订阅 # 收到消息流
```

## 脚本用法

```bash
bash    scripts/install-mqttx.sh help        # 所有子命令
sudo bash scripts/install-mqttx.sh           # 一键：下载→安装→校验→探测端口（推荐）
bash    scripts/install-mqttx.sh download    # 仅下载（不需 sudo）
sudo bash scripts/install-mqttx.sh install   # 仅安装
bash    scripts/install-mqttx.sh connect     # 探测远端 broker 连通性
sudo bash scripts/install-mqttx.sh remove    # 卸载并清理 deb 包
```

升级换版本：`sudo MQTTX_VERSION=<新版本> bash scripts/install-mqttx.sh all`（版本号查 https://github.com/emqx/MQTTX/releases）。

## 常见问题

**Q1：GitHub 下载超时/极慢？**

正常现象（见上文下载源对比表），换 EMQ CDN 直链，或直接用本篇脚本（已内置 CDN 优先）。

**Q2：连接 broker 失败？**

先跑 `bash scripts/install-mqttx.sh connect` 探测端口。通了还连不上再查认证（EMQX 若开了认证，匿名连接会被拒，需填用户名密码）和 Client ID 冲突（两台机器用同一 Client ID 会互相踢下线）。

**Q3：怎么彻底卸载？**

```bash
sudo bash scripts/install-mqttx.sh remove
# 或手动：sudo apt remove --purge -y mqttx
rm -rf ~/.config/MQTTX      # 用户数据（连接历史/主题收藏），可选
```

## 影响范围 / 安全权衡

- 只装 GUI 客户端，不监听任何端口、不起服务
- 磁盘占用约 260M（`/opt/MQTTX`），依赖零污染（纯 Electron 自带运行时）
- broker 地址写死远端 `10.0.0.78:1883`，不涉及本地回环服务
- 用户数据存 `~/.config/MQTTX`，卸载不自动清（防误删连接配置）

