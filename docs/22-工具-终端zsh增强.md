# 22 · 工具 · 终端 zsh 增强

> 把 Ubuntu 默认的裸 bash 终端升级为"输命令好用"的现代终端：灰色历史建议、语法高亮、模糊搜索、智能跳目录、git 状态提示符。全程不动 `.bashrc`/`.profile`，可一键完整回滚。

---

## 背景

装完系统后终端是原生 bash，痛点：

- 打过的长命令只能按 `↑` 一条条翻
- 命令打错要等回车报错才知道
- `Ctrl+R` 搜历史只能精确前缀匹配
- 频繁 `cd` 长路径
- 提示符不显示 git 分支、命令耗时

方案选型结论（为什么不用别的）：

| 备选 | 结论 | 原因 |
|------|------|------|
| **zsh + 手动 source 插件（本方案）** | ✅ 采用 | 全部组件在 Ubuntu 24.04 apt 源，加载快、无框架依赖 |
| oh-my-zsh | ❌ | 加载慢（1s+），带大量用不上的插件，升级维护负担 |
| fish | ❌ | 语法与 bash 不兼容，从文档/AI 复制 bash 命令会翻车 |
| 换终端模拟器（Alacritty/Kitty） | ❌ | 痛点在 shell 层不在窗口层，GNOME Terminal 够用 |

## 目标 / 现状（2026-08-20 实测）

| 组件 | 版本 | 来源 |
|------|------|------|
| zsh | 5.9-6ubuntu2 | apt |
| zsh-autosuggestions | 0.7.0-1 | apt |
| zsh-syntax-highlighting | 0.7.1-2 | apt |
| fzf | 0.44.1-1ubuntu0.3 | apt |
| zoxide | 0.9.3-1 | apt |
| bat（命令名 `batcat`） | 0.24.0-1build1 | apt |
| eza | 0.18.2-1 | apt |
| starship | 1.26.0 | GitHub（ghfast.top 镜像）→ `/usr/local/bin/starship` |
| JetBrainsMono Nerd Font | latest | GitHub（ghfast.top 镜像）→ `~/.local/share/fonts/JetBrainsMono-Nerd-Font/` |

- zsh 交互启动耗时：**0.239s**（含 nvm 加载，可接受）
- 默认 shell：`/bin/bash → /usr/bin/zsh`
- GNOME Terminal 默认 profile 字体：`'Monospace 12'` → `'JetBrainsMono Nerd Font Mono 12'`

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
sudo bash scripts/install-zsh-toolbox.sh install   # 或直接 sudo bash scripts/install-zsh-toolbox.sh
```

7 步全自动：apt 装包 → starship → Nerd 字体 → 生成 `.zshrc`/`.zprofile` → chsh → 终端字体 → 自验证。
装完**新开终端窗口**即生效。

### 手工步骤（理解原理用）

脚本做的事拆开就是：

```bash
# 1. 包
sudo apt install zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide bat eza fontconfig

# 2. starship（本机 GitHub 直连超时，走 ghfast.top 镜像；官方脚本 https://starship.rs/install.sh 亦可）
curl -fsSL -o /tmp/starship.tar.gz "https://ghfast.top/https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz"
sudo tar -xzf /tmp/starship.tar.gz -C /usr/local/bin starship

# 3. Nerd Font（无它则 eza/starship 图标显示为方块）
curl -fsSL -o /tmp/jbmono.tar.xz "https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
mkdir -p ~/.local/share/fonts/JetBrainsMono-Nerd-Font
tar -xJf /tmp/jbmono.tar.xz -C ~/.local/share/fonts/JetBrainsMono-Nerd-Font
fc-cache -f ~/.local/share/fonts

# 4. 切默认 shell
chsh -s /usr/bin/zsh          # 无密码：sudo chsh -s /usr/bin/zsh $(whoami)

# 5. 终端字体：GNOME Terminal → 偏好设置 → 配置 → 外观 → 关闭"使用系统等宽字体"
#    → 字体选 JetBrainsMono Nerd Font Mono（脚本用 gsettings 自动做了）
```

## 参数 / 配置详解（.zshrc 关键段）

生成的 `~/.zshrc`（73 行，管理标记 `ZSH-TOOLBOX-MANAGED`）分七段：

| 段 | 关键设置 | 为什么 |
|----|---------|--------|
| 历史 | `SHARE_HISTORY` `HISTSIZE=50000` `HIST_IGNORE_DUPS` | 多终端实时共享历史、去重；`HIST_IGNORE_SPACE`：空格开头的命令（含密码）不记录 |
| 补全 | `compinit` + `menu select` + 大小写不敏感 | Tab 补全弹菜单、方向键选、`cd /ULB` 也能补 `/usr/local/bin` |
| **环境继承** | 见下表 | **最关键的一段**，防止切 shell 后原有环境失效 |
| autosuggestions | apt 包路径 source | 灰色建议按 `→` 采纳、`End` 全收 |
| fzf | `key-bindings.zsh` + `completion.zsh` | `Ctrl+R` 模糊搜历史 / `Ctrl+T` 模糊找文件 / `Alt+C` 模糊跳目录 |
| 别名 | `ls→eza` `ll/la/lt` `bat→batcat` | 图标仅当字体目录存在时加 `--icons`；`cat` 故意**不**劫持，避免管道/脚本场景意外 |
| 高亮 | syntax-highlighting **放最后** | 官方要求：必须在其他插件之后 source 才能正确包装 |

**环境继承段**——`.bashrc` 里这些配置是 bash 专用的，切 zsh 后必须在新 shell 里得到等价物：

| 原配置 | zsh 侧方案 |
|--------|-----------|
| `~/bin`、`~/.local/bin` 进 PATH | `.zshrc` 显式追加（taos/BBDown wrapper 在这） |
| JAVA_HOME 动态解析（docs/15） | 同款 readlink 反解写进 `.zshrc` |
| nvm + Node（docs/21） | `nvm.sh` 原生支持 zsh，直接 source |
| `XQAPI_API_KEY`（codex CLI 依赖） | 同款 python 解析写进 `.zshrc` |
| DBeaver 中文别名 | 同款 alias |
| `~/.profile` 整体 | `~/.zprofile` 里 `emulate sh -c "source ~/.profile"`（zsh 登录 shell 不读它） |

> 以后往 `.bashrc` 加环境变量时，记得同步一份到 `.zshrc` 环境继承段（或直接放 `~/.zshrc.local`）。

## 验证方法

```bash
sudo bash scripts/install-zsh-toolbox.sh status    # 各组件状态总览
runuser -u $USER -- zsh -ic 'echo $JAVA_HOME; command -v node'   # 环境继承抽查
```

脚本 install 尾部自带 11 项验证（插件加载/fzf 绑定/字体/JAVA_HOME/nvm/XQAPI/chsh），全部 `[OK]` 即成。

日常体验确认：新开终端 →

1. 输入历史命令前几个字母 → 出灰色建议 → 按 `→` 采纳
2. 故意敲 `lsddd` → 命令名变红；敲 `ls` → 变绿
3. `Ctrl+R` → 输关键词模糊搜历史
4. `cd` 进几个常用目录后，`z 关键词` 直达
5. 进 git 仓库 → 提示符显示分支名

## 脚本用法

```bash
sudo bash scripts/install-zsh-toolbox.sh install    # 一键安装（缺省子命令）
sudo bash scripts/install-zsh-toolbox.sh status     # 状态查看（不需 sudo）
sudo bash scripts/install-zsh-toolbox.sh uninstall  # 完整回滚
sudo bash scripts/install-zsh-toolbox.sh help
```

- 安装时可重跑：已装的包/starship/字体自动跳过，`.zshrc` 属脚本托管会重写（个人配置放 `~/.zshrc.local`，不会被覆盖）
- 用户自有的 `.zshrc`/`.zprofile`（无管理标记）会被备份到 `~/.config/zsh-toolbox/backup-时间戳/`
- 回滚信息记录在 `~/.config/zsh-toolbox/state.env`（原 shell、备份路径、终端旧字体）

## 常见问题

**Q1：为什么 starship/字体下载会失败？**
本机 GitHub release 资产直连超时（docs/21 同款问题），脚本自动 fallback `ghfast.top` → `ghproxy.net`。实测两者均靠 ghfast.top 成功。全失败只 warn 不中断，网络恢复后重跑 `install` 补装。

**Q2：VS Code / Tabby 里的终端还是 bash？**
正常。已开终端不重启不影响；IDE 终端 profile 独立配置（VS Code 可在 terminal 下拉里选 zsh 或改 `terminal.integrated.defaultProfile.linux`）。bash 本身未被破坏，随时可用。

**Q3：`zsh -ic` 手动测试时插件"没加载"？**
在 sudo/root 环境下跑 zsh 读的是 root 的家目录。要以真实用户身份：`runuser -u $USER -- zsh -ic '...'`（脚本验证步骤已内置）。

**Q4：图标显示成方块（tofu）？**
终端没用到 Nerd 字体：确认 GNOME Terminal 偏好设置里该 profile 的字体是 JetBrainsMono Nerd Font Mono 且"使用系统等宽字体"已关；或重跑 install 修复字体。

**Q5：怎么改提示符样式？**
starship 配置文件 `~/.config/starship.toml`（默认不存在），预设见 https://starship.dev/zh-CN/presets/ 。

## 影响范围 / 安全权衡

- **零侵入**：全程不修改 `~/.bashrc`、`~/.profile`（装后 md5 校验一致），bash 环境原样保留
- 新增文件全部集中：`~/.zshrc`、`~/.zprofile`、`~/.config/zsh-toolbox/`、`~/.local/share/fonts/JetBrainsMono-Nerd-Font/`、`/usr/local/bin/starship`
- chsh 只改本用户；`sudo bash scripts/install-zsh-toolbox.sh uninstall` 完整还原
- 风险点：`alias ls→eza` 改变交互 ls 的输出样式（脚本/非交互不受影响，`uninstall` 或 `.zshrc.local` 里 `unalias ls` 可恢复）
- 保留物：`~/.zsh_history`（uninstall 不删，可手动清理）

