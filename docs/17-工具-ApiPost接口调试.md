# 17 · 工具 · ApiPost 接口调试

> 一句话：在 Ubuntu 上安装 ApiPost（国产接口调试 / 文档 / Mock / 压测一体化工具，可替代 Postman）。

---

## 背景

后端开发需要频繁调试 HTTP 接口、生成 API 文档、做接口自动化测试。若团队接口约定/Mock 基于 ApiPost 维护，需安装客户端与之协同。

ApiPost 官方提供 Linux 原生客户端（Electron 套壳），Ubuntu 24.04 可直接用 `.deb` 包安装。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| 安装方式 | 官方 `.deb`（AMD/x64） |
| 当前版本 | 8.2.7（2026-08 实测） |
| 安装路径 | `/opt/Apipost/` |
| 命令 | `/usr/bin/apipost`（系统）→ 已被 `~/bin/apipost` wrapper 覆盖（禁 GPU 防崩溃） |
| 桌面菜单 | `/usr/share/applications/apipost.desktop`（系统）→ 已被 `~/.local/share/applications/apipost.desktop` 覆盖 |
| 用户数据 | `~/.config/Apipost`（大写 A） |
| 官方下载页 | https://www.apipost.cn/download.html |

## 解决方案

### 一键执行（推荐）

```bash
# 进入仓库目录
cd <本仓库目录>

# 一键下载 + 安装 + 校验（需 sudo）
sudo bash scripts/install-apipost.sh
```

脚本会：

1. 从官网下载 `apipost-8.2.7.deb`（约 80M）到 `~/Downloads`
2. `dpkg -i` 安装，依赖缺失时自动 `apt -f` 修复
3. 校验 `dpkg -l` / `which apipost` / 桌面菜单项

### 手工步骤（理解原理用）

```bash
# 1. 下载（AMD/x64，版本号可在官网下载页确认）
curl -fL -o ~/Downloads/apipost-8.2.7.deb \
  "https://www.apipost.cn/dl.php?client=Linux&arch=x64&version=8.2.7" \
  -A "Mozilla/5.0"

# 2. 安装
sudo dpkg -i ~/Downloads/apipost-8.2.7.deb
# 若报依赖错误，修复一下：
sudo apt-get install -f -y

# 3. 启动：Super 键搜索 "Apipost"，或命令行：
apipost &
```

## 参数 / 配置详解

### 下载 URL 拆解

```
https://www.apipost.cn/dl.php?client=Linux&arch=x64&version=8.2.7
                                └─Linux──┘ └─x64─┘ └──版本号──┘
```

- `client`：`Linux` / `Windows` / `Mac`
- `arch`：`x64`（AMD64）或 `arm`（ARM64，如树莓派 / 飞腾）
- `version`：与官网下载页一致，升级时改这里即可

> ARM 设备把 `arch=x64` 换成 `arch=arm`。

### 为什么用 `.deb` 而非 AppImage

| 方式 | 优点 | 缺点 |
|------|------|------|
| **`.deb`（采用）** | 自动注册菜单项、`update-alternatives` 生成命令、卸载干净 | 需要 sudo |
| AppImage | 免安装、绿色 | 无菜单项、需自建快捷方式、无法统一升级 |
| Flathub | 沙箱隔离、自动更新 | 需先装 flatpak，体积更大 |

本机选 `.deb`：与现有安装风格一致（见 DBeaver / VLC 等），菜单项开箱即用。

## 验证方法

```bash
# 1. dpkg 登记
dpkg -l apipost
# 期望：ii  apipost  8.2.7  amd64

# 2. 命令可执行
which apipost && readlink -f $(which apipost)
# 期望：/usr/bin/apipost → /opt/Apipost/apipost

# 3. 桌面菜单项存在
ls /usr/share/applications/apipost.desktop
```

或直接 GUI：按 Super 键，搜索 "Apipost"，能打开主界面即安装成功。

## 脚本用法

```bash
bash scripts/install-apipost.sh help        # 查看所有子命令

bash    scripts/install-apipost.sh download # 仅下载（不需 sudo）
sudo    scripts/install-apipost.sh install  # 仅安装
bash    scripts/install-apipost.sh verify   # 仅校验
sudo    scripts/install-apipost.sh remove   # 卸载并清理 deb 包

# 指定版本（升级时）
sudo APIPOST_VERSION=8.2.7 bash scripts/install-apipost.sh all
```

## 常见问题

**Q1：升级到新版本怎么做？**

改 `APIPOST_VERSION` 重跑即可，dpkg 会覆盖旧版本：

```bash
sudo APIPOST_VERSION=8.3.0 bash scripts/install-apipost.sh all
```

**Q2：启动后崩溃 "Uncaught Exception: Error: write EPIPE"（AMD 双显卡必现）**

**根因**：本机双 AMD 显卡（7551 + 13c0）+ 开源 amdgpu 驱动 + X11 会话下，Electron/Chromium 默认开 GPU 合成，但其 GL Passthrough 在该驱动组合下不可用（启动日志 `Passthrough is not supported, GL is disabled`）。GPU 进程崩溃后，主进程往已关闭的管道写日志 → 抛 `write EPIPE`。错误堆栈常落在 `PostmanCollectionRunner.run`（接口集合跑时高发）。

**已内置修复**（2026-08-12 实测）：

本仓库已部署 wrapper 与用户级菜单项，开箱即用，无需手动加参数：

| 文件 | 作用 |
|------|------|
| `~/bin/apipost` | 启动 wrapper，自动注入禁 GPU 参数 |
| `~/.local/share/applications/apipost.desktop` | 用户级菜单项，覆盖系统项，从 Super 键启动也生效 |

wrapper 关键参数：

```bash
exec /opt/Apipost/apipost \
    --disable-gpu \                   # 核心：完全禁用 GPU 硬件加速
    --disable-software-rasterizer \   # 禁用软件光栅化兜底
    --disable-gpu-compositing \       # 禁用 GPU 合成层
    --disable-features=Vulkan \       # 禁用 Vulkan（AMD 驱动 Vulkan 路径有 bug）
    "$@"
```

这些开关只影响 ApiPost 渲染，不影响系统其它应用。

**手动验证**：

```bash
# 1. wrapper 是否在 PATH 优先位置
which apipost              # 期望：~/bin/apipost（非 /usr/bin）

# 2. 直接测试参数是否生效（后台跑 10 秒不崩即修复成功）
nohup apipost >/tmp/ap.log 2>&1 & sleep 10; kill %1
grep -i 'EPIPE\|Passthrough' /tmp/ap.log   # 无 EPIPE 即正常
```

**如果升级 ApiPost 后又崩溃**：升级覆盖的是 `/usr/bin/apipost` 和 `/usr/share/applications/apipost.desktop`，但本文的 wrapper（`~/bin/apipost`）和用户级菜单项（`~/.local/...`）不会被动，依然优先，故修复长期有效。

**极端情况**（wrapper 仍崩）：进一步加参数排查

```bash
apipost --disable-gpu --in-process-gpu --no-sandbox
```

**Q3：怎么彻底卸载？**

```bash
sudo apt remove --purge apipost        # 卸载系统包
rm -f ~/bin/apipost                    # 删 wrapper
rm -f ~/.local/share/applications/apipost.desktop   # 删用户级菜单项
rm -rf ~/.config/Apipost               # 清用户数据（注意大写 A：项目/历史/登录态）
rm -f ~/Downloads/apipost-*.deb        # 清安装包
# 或直接用脚本（仅卸载系统包，wrapper 需手动删）：
sudo bash scripts/install-apipost.sh remove
```

**Q4：命令行 `apipost --version` 卡住？**

这是 GUI 程序，`--version` 会拉起主界面而非打印版本号。查版本用 `dpkg -l apipost`。

## 影响范围 / 安全权衡

- 安装目录 `/opt/Apipost/`，包含内置 Chromium 与 Electron 运行时，体积约 250M
- deb 包自带 `/usr/share/applications/apipost.desktop`，无需手动写 `.desktop`
- 注册了 URL Scheme `%U`，浏览器内 `apipost://` 链接可唤起客户端（用于"在 ApiPost 中打开"按钮）
- 软件自带更新检查，会联网到 apipost.cn；纯离线环境关闭"自动检查更新"即可

