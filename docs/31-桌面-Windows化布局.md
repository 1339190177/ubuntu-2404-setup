# 31 · 桌面 · Windows化布局

> 修复桌面重装事故丢掉的扩展包（Dock/托盘/桌面图标），并把 GNOME 布局调成 Windows 习惯：底部常驻任务栏 + 单击最小化。

---

## 背景

修显示问题时重装了 `xserver-xorg-core / xinit / gdm3`（详见 docs/06/31 相关记录），
Mesa/libdrm 降级的依赖级联把一批桌面包带走。结果桌面成了**裸 GNOME**：

- 没有左侧 Dock（启动器整条消失）
- 没有系统托盘（微信、输入法图标无处安放）
- 没有桌面图标（家目录都不显示）
- `gnome-extensions list` 全空，扩展管理器/Tweaks 都没了

比标准 Ubuntu 默认布局还裸，加上 GNOME 默认布局本就和 Windows 习惯相反
（Dock 左侧竖条、智能隐藏、点图标不最小化），双重不习惯。

## 现状（2026-09-16 实测取证）

| 项 | 值 |
|---|---|
| 桌面 | GNOME Shell 46.0，X11 会话（ubuntu:GNOME） |
| 屏幕 | 单屏 1920×1200（HDMI-A-2） |
| 事故卸载 | `ubuntu-desktop` 元包 + `gnome-shell-extension-ubuntu-dock` 等 5 个扩展包 |
| 空壳包 | `gnome-shell-extension-desktop-icons-ng`：dpkg 记录"已安装"但文件全丢（`dpkg -L` 输出为空） |
| dconf 设置 | 基本幸存（`button-layout` 等还是默认值，未损坏） |

取证命令（下次怀疑桌面包残缺直接用）：

```bash
# apt 历史找卸载/重装痕迹
awk '/^Start-Date/{d=$2" "$3} /Commandline/{print d"  "$0}' /var/log/apt/history.log | tail -20

# 扩展是否还活着（schema 缺失 = 包丢了）
gnome-extensions list
gsettings get org.gnome.shell.extensions.dash-to-dock dock-position

# 空壳包检测（dpkg 记录在、文件无）
dpkg -L gnome-shell-extension-desktop-icons-ng | grep -c extensions   # 0 = 空壳
```

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
sudo bash scripts/configure-desktop-windows.sh          # 装包 + 布局一步到位
# 完成后注销重登一次（新装的扩展要重新加载）
```

### 手工步骤（理解原理用）

```bash
# 1. 精准补装 6 个包（先 --simulate 预检，确认不拉 mesa/drm/xorg）
sudo apt-get install -y gnome-shell-extension-ubuntu-dock \
    gnome-shell-extension-appindicator gnome-shell-extensions \
    gnome-shell-extension-prefs gnome-tweaks \
    gnome-shell-extension-desktop-icons-ng

# 2. 空壳包自愈（本机实测 desktop-icons-ng 需要这步）
sudo apt-get install --reinstall -y gnome-shell-extension-desktop-icons-ng

# 3. 启用扩展（直接写 enabled-extensions，避免"当前会话认不到新扩展"的坑）
gsettings set org.gnome.shell enabled-extensions \
    "['ubuntu-dock@ubuntu.com', 'ubuntu-appindicators@ubuntu.com', 'ding@rastersoft.com']"

# 4. Windows 化布局（逐项见下一章参数表）
D=org.gnome.shell.extensions.dash-to-dock
gsettings set $D dock-position 'BOTTOM'
gsettings set $D dock-fixed true
gsettings set $D autohide false
gsettings set $D intellihide false
gsettings set $D click-action 'minimize-or-overview'
gsettings set $D dash-max-icon-size 40
gsettings set $D extend-height false
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'
gsettings set org.gnome.desktop.interface enable-hot-corners false
gsettings set org.gnome.mutter center-new-windows true
```

## 参数 / 配置详解

| gsettings | 值 | 为什么 |
|---|---|---|
| `dock-position` | `BOTTOM` | Windows 任务栏在底部，肌肉记忆第一来源 |
| `dock-fixed` | `true` | 常驻不隐藏；GNOME 默认"贴边才出现"会让人觉得任务栏丢了 |
| `autohide` / `intellihide` | `false` / `false` | 两个自动隐藏开关都关掉，和 `dock-fixed` 配套 |
| `click-action` | `minimize-or-overview` | 未运行→启动；未聚焦→聚焦；已聚焦→最小化。等价 Windows 任务栏单击行为 |
| `dash-max-icon-size` | `40` | 默认 48 偏大，40 接近 Windows 任务栏图标密度 |
| `extend-height` | `false` | Dock 不占满整条边，横条样式 |
| `button-layout` | `:minimize,maximize,close` | Ubuntu 默认即如此，显式设置作为重装自愈 |
| `enable-hot-corners` | `false` | 左上热角易误触，Windows 无此物 |
| `center-new-windows` | `true` | 新窗口居中，观感更接近 Windows |

## 验证方法

```bash
bash scripts/configure-desktop-windows.sh status
```

注销重登后视觉检查：Dock 在屏幕底部且常驻；点已聚焦的应用图标窗口最小化；
窗口右上角 ─ □ ✕ 三键齐全；微信等托盘图标出现在顶部栏右侧。

## 脚本用法

```bash
sudo bash scripts/configure-desktop-windows.sh install  # 只补包
bash   scripts/configure-desktop-windows.sh apply       # 只设布局
bash   scripts/configure-desktop-windows.sh status      # 查状态
bash   scripts/configure-desktop-windows.sh reset       # 恢复 GNOME 默认（整组可逆）
```

## 常见问题

**Q1：为什么用 gsettings 直接写 enabled-extensions，不用 `gnome-extensions enable`？**
装包发生在会话启动之后时，运行中的 shell 认不到新扩展，`gnome-extensions enable`
报 "Extension does not exist"。直接写设置项后注销重登即可加载。脚本用合并写法，
不清空用户已有的其他扩展。

**Q2：为什么 sudo 下跑 gsettings 要 `runuser` 还原真实用户？**
gsettings 写的是 `~/.config/dconf/user`，root 身份跑会写进 root 的 dconf，
真实桌面毫无变化。脚本内置 `gs()` 包装统一处理（含用户 DBus 总线路径）。

**Q3：装包会不会又把显示栈搞乱？**
`--simulate` 预检过：6 个包只带 `chrome-gnome-shell` / `gir1.2-*` 等 10 个纯
用户态依赖，无 mesa/libdrm/xorg/kernel 组件。脚本未自动化预检，重大操作前
可手工跑一次 `apt-get install --simulate`。

**Q4：还是想要"真任务栏"（窗口按钮列表）和"开始菜单"怎么办？**
那是下一档方案（社区扩展 Dash to Panel + ArcMenu，GNOME 46 兼容），代价是
GNOME 大版本升级时扩展可能要跟版本。本档先满足 80% 习惯，不够再上，未预装。

**Q5：想回左侧竖条/默认布局？**
`bash scripts/configure-desktop-windows.sh reset`，或卸载扩展包
`sudo apt remove gnome-shell-extension-ubuntu-dock ...`。

## 依赖级联事故后的审计与批量恢复（通用套路）

显示栈排障引发依赖级联时，一笔 apt 交易可能连带卸掉上百个包。
下述审计套路来自一次卸载 171 包、115 包缺失的真实事故复盘。

### 审计 + 批量恢复的通用套路

```bash
# 1. 挖完整卸载清单（一笔交易的全部 Remove 行）
awk '/Start-Date:.*2026-09-15  18:00:39/{d=1;next} /^Start-Date/{d=0} d&&/^(Remove|Purge):/{
  gsub(/^(Remove|Purge): /,""); n=split($0,a,", ");
  for(i=1;i<=n;i++){split(a[i],b," "); print b[1]}}' /var/log/apt/history.log | sort -u

# 2. 比对当前状态——注意先剥 :amd64 后缀（dpkg -s 带架构名查询行为不一致，会虚报缺失）
# 3. apt-get install --simulate 预检，grep "^Inst" 确认不碰 mesa/drm/xserver/内核
# 4. 批量装回，逐个跑 --version 验证
```

> 残留观察：glxinfo 显示 GL renderer 为 **llvmpipe（软件渲染）**——显示排障后的既有
> 状态，与本次恢复无关（本次 0 个已装包被升级、0 个被卸载）。3D/视频如感卡顿属显示栈
> 课题，红线内不擅动。

## 追加事故：GRUB 遗留 nomodeset（2026-09-16 重启后爆发）

**现象链**：桌面布局改完重启生效 → 「GPU监控」点击闪退、glxinfo 显示 llvmpipe 软渲染、
nvtop 报 `No GPU to monitor`、`/dev/dri` 只剩 card0 无 renderD 节点。

**根因**：9-15 显示事故当晚有人把 GRUB 改成 `nomodeset`（黑屏急救招），机器一直没重启
所以从未生效；9-16 08:55 重启后 nomodeset 上场 → amdgpu 双卡探测全部 `error -22`，
simpledrm 软件兜底。同时启动行里还混着两个无依据的排障参数。

**处置（GRUB 类变更高风险：先备份，逐参数核实来源后再动）**：

| 参数 | 审查结论 |
|---|---|
| `amdgpu.dc_feature_mask=0x0` | ✅ 恢复——RDNA4 社区实测记载：iGPU(Raphael/DCN3.1) HDMI 黑屏根治项，实测有效 |
| `amdgpu.runpm=0` | ✅ 恢复——社区实测记载：dGPU rlc autoload timeout（高负载挂起→暖重启唤醒失败）修复 |
| `amdgpu.ppfeaturemask=0xffffffff` | ❌ 剔除——无公开依据；解锁全部 PowerPlay 特性（含 OverDrive 超频/电压控制面），坏设置可硬挂卡，属"严禁乱配"级 |
| `amdgpu.gpu_recovery=1` | ❌ 剔除——无依据的排障遗留，dGPU 挂起病已由 runpm=0 根治 |

```bash
# 最终写入（改前备份 /etc/default/grub.bak.<时间戳>）
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amdgpu.dc_feature_mask=0x0 amdgpu.runpm=0"
sudo update-grub
```

**重启后验证清单**：`ls /dev/dri/renderD*` 应有节点；`nvtop` 应列出双卡；
`glxinfo -B` renderer 应为硬件（非 llvmpipe）；dmesg 残留 optc 警告属良性（社区已知，良性）。

**连带加固**：「GPU监控」启动器改经 `~/bin/gpu-monitor.sh` 包装——无 GPU 时终端保留并
显示诊断（原因+排查命令），不再闪退无信息。模板在 `desktop-launchers/gpu-monitor.sh.example`。

## 影响范围 / 安全权衡

- 全部操作为 apt 装包 + 用户级 dconf 设置，**不碰内核/Mesa/libdrm/Xorg**，
  此前锁定的显示降级组合（libdrm 2.4.125 + mesa 25.2.8）不受影响。
- 不装 `ubuntu-desktop` 元包（它会拉一串 snap 和大组件），走精准补包，
  代价是未来 apt 大升级不会自动"保护"这些扩展包——重装系统后重跑本脚本即可。
- 所有 gsettings 改动集中在 10 个键，`reset` 一键回默认。

