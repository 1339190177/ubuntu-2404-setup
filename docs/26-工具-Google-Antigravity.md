# 26 · 工具 · Google Antigravity

> 装 Google Antigravity 2.0 桌面客户端（Gemini 驱动的 agentic 开发工具），
> 官方 tar.gz 用户级安装，无需 sudo，可一键卸载。

---

## 背景

[Antigravity](https://antigravity.google) 是 Google 的 AI 智能体开发平台
（Gemini 系列模型驱动）。官网下载页 `https://antigravity.google/download` 提供
五类产物，先分清楚再装：

| 产物 | 版本（2026-09-03 快照） | Linux 分发 | 本文 |
|------|------------------------|-----------|------|
| **桌面客户端（Hub，页面主推）** | 2.12.0 | `Antigravity.tar.gz` 直链 | ✅ 装这个 |
| Antigravity CLI | — | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` | 未装 |
| IDE 扩展（VS Code/JetBrains/Zed 等） | — | 各插件市场 | 未装 |
| 独立 IDE（Standalone，VS Code 系） | 2.5.5 | `Antigravity IDE.tar.gz` 直链 | 未装 |
| Python SDK | — | GitHub / pip | 未装 |

> 注意：Hub 与独立 IDE 是**两个不同的包**，版本号各自独立（2.12.0 ≠ 2.5.5，
> 不是谁比谁旧）。桌面客户端是下载页 hero 位置的主产品，本文装它。

## 目标 / 现状

- 系统：Ubuntu 24.04 x86_64，X11 会话
- 安装方式：tar.gz 解压到 `~/apps/antigravity-<版本>`（用户级，零系统污染）
- 网络：`storage.googleapis.com` **直连超时**，下载走本机代理（SOCKS5）
  （`socks5h://127.0.0.1:10808`）——脚本已内置直连失败自动兜底

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
bash scripts/install-antigravity.sh          # download → install → configure → verify
```

### 手工步骤（理解原理用）

```bash
# 1. 下载（直连会超时，直接带代理；约 165M，实际安装后 502M）
curl -fL --proxy socks5h://127.0.0.1:10808 \
  -o ~/Downloads/Antigravity-2.12.0-linux-x64.tar.gz \
  "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.12.0-5051501534642176/linux-x64/Antigravity.tar.gz"

# 2. 解压（包内顶层目录叫 Antigravity-x64，统一改名带版本号的稳定路径）
mkdir -p ~/apps
tar -xzf ~/Downloads/Antigravity-2.12.0-linux-x64.tar.gz -C ~/apps
mv ~/apps/Antigravity-x64 ~/apps/antigravity-2.12.0

# 3. 命令行入口（~/.local/bin 已在 PATH）——代理环境包装而非裸软链（FAQ Q9）
#    ⚠️ 先删可能存在的旧软链再写，避免写穿透覆盖应用（FAQ Q10）
rm -f ~/.local/bin/antigravity
cat > ~/.local/bin/antigravity << 'EOF'
#!/bin/bash
export http_proxy=socks5://127.0.0.1:10808
export https_proxy=socks5://127.0.0.1:10808
export all_proxy=socks5://127.0.0.1:10808
export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" ALL_PROXY="$all_proxy"
export no_proxy=localhost,127.0.0.1,::1
export NO_PROXY="$no_proxy"
exec ~/apps/antigravity-2.12.0/antigravity "$@"
EOF
chmod +x ~/.local/bin/antigravity

# 4. 官方图标（包里没有图标文件，从官网拿 apple-touch-icon）
mkdir -p ~/.local/share/icons
curl -fsL --proxy socks5h://127.0.0.1:10808 \
  -o ~/.local/share/icons/antigravity.png \
  https://antigravity.google/apple-touch-icon.png

# 5. GNOME 菜单项
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/antigravity.desktop << 'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Antigravity
GenericName=AI 智能体开发工具
Comment=Google Antigravity（官方 tar.gz 用户级安装 2.12.0）
Exec=~/apps/antigravity-2.12.0/antigravity -- %U
Icon=~/.local/share/icons/antigravity.png
Terminal=false
Categories=Development;IDE;
StartupWMClass=Antigravity
StartupNotify=true
EOF
update-desktop-database ~/.local/share/applications
```

## 参数 / 配置详解

| 项 | 值 | 为什么 |
|----|----|--------|
| 安装位置 | `~/apps/antigravity-2.12.0/` | 目录带版本号，升级新版本 = 解压新目录，回滚 = 删目录，互不干扰 |
| 命令入口 | `~/.local/bin/antigravity` 代理环境包装脚本 | 本机 `~/bin` 与 `~/.local/bin` 都在 PATH；包装注入 socks5 代理（Google 域名直连不通，FAQ Q9）后 exec 当前版本主程序 |
| chrome-sandbox | 保持默认（不 chown root） | Electron tarball 的经典坑是沙箱需 SUID root，**本机实测不需要**，Ubuntu 24.04 直接能跑；若报错再按 FAQ Q1 处理 |
| 下载代理 | `socks5h://127.0.0.1:10808` | 本机 xray 常驻端口；`socks5h` 让域名解析也走代理，避免 DNS 污染 |
| `StartupWMClass=Antigravity` | 固定值 | 让任务栏正确把窗口归组到菜单项（`wmctrl -l` 实测窗口标题为 Antigravity） |

## 验证方法

```bash
# 文件与软链（脚本 verify 子命令即做这三件事）
ls -l ~/.local/bin/antigravity          # → ~/apps/antigravity-2.12.0/antigravity
desktop-file-validate ~/.local/share/applications/antigravity.desktop

# 启动验证（终端或菜单均可）
gtk-launch antigravity                  # 或应用列表搜 "Antigravity"
sleep 5 && pgrep -cx antigravity        # Electron 多进程，>1 即正常

# 协议处理器验证（Google 登录回调依赖，见 FAQ Q6）
gio mime x-scheme-handler/antigravity   # 默认=antigravity.desktop 且已注册列表非空

# 看运行日志
tail -f ~/.config/Antigravity/logs/main.log
# 正常标志：Starting app (v2.12.0) with dynamic port…
```

## 脚本用法

```bash
bash scripts/install-antigravity.sh              # 一键安装（推荐）
bash scripts/install-antigravity.sh download     # 仅下载
bash scripts/install-antigravity.sh launch       # 后台启动 + 确认进程
bash scripts/install-antigravity.sh remove       # 卸载
# 升级：官网拿新直链，覆盖 AG_URL 重跑
AG_URL='<新版本linux-x64直链>' AG_VERSION=<新版本号> \
  bash scripts/install-antigravity.sh all
```

## 常见问题

**Q1：启动报 `The SUID sandbox helper binary was found, but is not configured correctly`？**
Electron 沙箱问题（Ubuntu 24.04 默认未触发）。修复：
```bash
sudo chown root:root ~/apps/antigravity-2.12.0/chrome-sandbox
sudo chmod 4755  ~/apps/antigravity-2.12.0/chrome-sandbox
```
（本机实测不需要；不要用 `--no-sandbox` 绕过，安全性差。）

**Q2：`antigravity --version` 怎么把整个应用拉起来了？**
Electron 应用不认 `--version`/`--help` 这类 flag，任何参数都会正常启动 GUI。
查版本看 `~/.config/Antigravity/logs/main.log` 里的 `Starting app (v…)`，
或看安装目录名。

**Q3：下载一直超时？**
`storage.googleapis.com` 在本网络直连不通，脚本会自动兜底走
`socks5h://127.0.0.1:10808`（本机 xray）。若 xray 没起或端口变了，
用 `AG_PROXY=socks5h://IP:端口` 显式指定。

**Q4：想装的是「独立 IDE」而不是桌面客户端？**
同一个下载页里那是个独立的包（`Antigravity IDE.tar.gz`，edgedl.me.gvt1.com
直链），Electron 结构相同，解压流程一样。可以复用本脚本：
```bash
AG_URL='https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz' \
AG_VERSION=2.5.5-ide bash scripts/install-antigravity.sh all
# 注意：该包顶层目录名与解压后命名需按实际调整（脚本 mv 的源目录写死为 Antigravity-x64）
```

**Q5：卸载后重装要重新登录吗？**
`remove` 不删 `~/.config/Antigravity`（登录态/配置都在），重装后直接恢复；
想彻底清就 `rm -rf ~/.config/Antigravity ~/.gemini/antigravity`。

**Q6：Google 登录成功后弹「未安装可以打开 antigravity://oauth-success 的应用」？**
（2026-09-03 实测踩坑）登录本身已成功，只是 `antigravity://` 自定义协议没注册，
浏览器回调无法落回应用。根因：官方 tar.gz 不带 .desktop，应用启动后虽会自己注册，
但 GIO 的候选缓存（`update-desktop-database` 产物）没跟上，GNOME 就报"无可用应用"。
修复（装完跑一遍即可）：
```bash
# 1. 确认 .desktop 声明了协议（新版 install-antigravity.sh 已内置写这行）
#    MimeType=x-scheme-handler/antigravity;
# 2. 刷新 GIO 缓存 + 显式设默认处理器
update-desktop-database ~/.local/share/applications
xdg-mime default antigravity.desktop x-scheme-handler/antigravity
# 3. 验证（应输出 antigravity.desktop，且"已注册"列表非空）
gio mime x-scheme-handler/antigravity
# 4. 回到浏览器认证成功页，点 "Click here if not working" 链接完成落回
```

**Q7：顺手检查——text/html 默认应用被抢。**
首次登录流程还会把 `text/html` 的默认应用改成 Antigravity（双击 .html 会打开它
而不是编辑器/浏览器）。本机 docs/18 约定 text/html → VS Code，被抢后恢复：
```bash
xdg-mime default code.desktop text/html
```

**Q8：在 SSH / agent 会话里启动，命令一结束应用就退出，日志还有
`GPU process isn't usable. Goodbye.` FATAL？**
不是 GPU 问题（AMD 双卡跑得好好的）。远程会话退出时进程组被整体回收，
GPU FATAL 只是退出时的连带噪音。正确启动姿势是 `setsid` 脱离会话：
```bash
DISPLAY=:1 setsid nohup ~/.local/bin/antigravity >/dev/null 2>&1 < /dev/null &
```
桌面环境里从菜单点图标启动没有这个问题。

**Q9：登录回调成功后弹 "There was an unexpected issue setting up your
account — Post https://oauth2.googleapis.com/token: dial tcp …: i/o timeout"？**
本机直连 Google 域名全部超时（下载也是，见"目标/现状"），而应用内的 Go 组件
（language_server）拿授权码换 token、后续调 Gemini API 都是**直连**——
浏览器（Edge）有自己的代理配置所以认证页正常，应用不吃系统代理。
修复：启动包装脚本注入 SOCKS5 代理环境变量（`~/.local/bin/antigravity` 已内置，
2026-09-03 实测 language_server 的 `/proc/<pid>/environ` 确认继承生效）：
```bash
export http_proxy=socks5://127.0.0.1:10808   # 注意 socks5:// 而非 socks5h://，
export https_proxy=socks5://127.0.0.1:10808  # Go 的 httpproxy 只认前者
export all_proxy=socks5://127.0.0.1:10808
export no_proxy=localhost,127.0.0.1,::1      # 本地 UI(127.0.0.1:随机端口)不走代理
exec ~/apps/antigravity-2.12.0/antigravity "$@"
```
验证代理确实通（404 即可达，直连是 000 超时）：
```bash
https_proxy=socks5h://127.0.0.1:10808 curl -s -o /dev/null -w '%{http_code}\n' https://oauth2.googleapis.com/token
```
> Chromium 渲染部分不受影响（Linux 上桌面代理设置优先级高于环境变量，
> 本地 UI 保持直连），代理只作用于 Go 组件的网络请求。

**Q10：手滑把应用主程序覆盖了（比如对软链 `cat >` 写入）？**
`cat > 软链路径` 会**写穿透到目标文件**——曾把 206MB 的 ELF 覆盖成脚本文本，
应用变成自我 exec 死循环。从 tar 包精准恢复单文件即可（无需整包重装）：
```bash
tar -xzf ~/Downloads/Antigravity-2.12.0-linux-x64.tar.gz \
  -C ~/apps/antigravity-2.12.0 --strip-components=1 Antigravity-x64/antigravity
# 全目录完整性校验（过滤属主差异，无输出=完好）
tar -dzf ~/Downloads/Antigravity-2.12.0-linux-x64.tar.gz \
  -C ~/apps/antigravity-2.12.0 --strip-components=1 2>&1 | grep -vE 'Uid 不同|Gid 不同|警告'
```
教训：对可能存在软链的路径做重定向写入，先 `ls -l` 确认、先 `rm` 再写。

## 影响范围 / 安全权衡

- **零系统改动**：不装 deb、不动 apt、不需要 sudo；所有文件都在用户家目录
  （`~/apps`、`~/.local/bin`、`~/.local/share/{icons,applications}`）
- **运行时行为**：启动会在本地起 `language_server` 进程并监听
  `127.0.0.1` 随机端口（仅本机回环）；对外通信走 Google API
  （`generativelanguage.googleapis.com` 等，需代理的网络环境下由应用自身
  网络栈处理）
- **登录**：使用需 Google 账号登录 Antigravity，凭据存 `~/.config/Antigravity`

