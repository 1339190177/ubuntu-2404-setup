# 09 · 工具 · RustDesk 远程桌面

> 开源远程桌面，替代 ToDesk/向日葵。Linux/Windows/Mac/Android/iOS 互连。
> 本文覆盖：安装、日常使用、**被控的 Wayland/X11 深坑**、自建中继提速、被控隐私（锁屏关屏）。

---

## 选型：为什么用 RustDesk

| 维度 | ToDesk/向日葵 | **RustDesk** |
|------|--------------|-------------|
| 开源 | ❌ 闭源 | ✅ GPL |
| Linux 支持 | 一般（国产闭源软件在 Linux 偶尔崩）| ✅ 官方 deb，原生支持 |
| Wayland 兼容 | ⚠️ 被控可能黑屏 | ✅ 较好（仍有坑，见下） |
| 自建中继 | ❌ | ✅ 可自建（解决国内速度问题） |
| 国内速度 | ✅ 快（中继在国内）| ⚠️ 默认公共中继在国外 |

**结论**：Ubuntu 上 RustDesk 更合适；速度问题用自建中继解决（见 [docs/24](24-工具-RustDesk自建中继.md)）。

## 安装

```bash
# GitHub 直连（国内常超时/慢）
aria2c -x16 https://github.com/rustdesk/rustdesk/releases/download/1.3.9/rustdesk-1.3.9-x86_64.deb

# 国内镜像（推荐，gh-proxy.com 实测可用）
aria2c -x8 https://gh-proxy.com/https://github.com/rustdesk/rustdesk/releases/download/1.3.9/rustdesk-1.3.9-x86_64.deb

sudo apt-get install -y ./rustdesk-1.3.9-x86_64.deb
```

apt 会自动装依赖（libxdo3 等）、注册 `rustdesk.service`（开机自启）、加 desktop 文件。
装完 `rustdesk --get-id` 查看本机 ID。

## 日常使用

**主控（远控别人）**：打开 RustDesk → 控制框输入对方 ID → 输对方密码（或对方接受请求）。

**被控（别人远控你）**：主界面显示本机 ID 和临时密码，发给对方即可。设永久密码：界面"设置密码"，或：

```bash
rustdesk                          # 打开主界面
rustdesk --get-id                 # 查看本机 ID
rustdesk --password <新密码>      # 设置永久密码
systemctl status rustdesk         # 后台服务状态（被控核心）
```

## ⚠️ 被控深坑：Wayland vs X11（Ubuntu 24.04 默认 Wayland）

**结论先行**：Ubuntu 桌面若要**经常被远控**，永久切 X11 是零烦恼方案；几乎不被控则留 Wayland。

Wayland 被控的 6 个已知问题（X11 下全部消失）：

| 问题 | Wayland 表现 | X11 表现 |
|------|------------|---------|
| 首次连接弹"选择分享画面" | ⚠️ 必弹，要本人在场点 | ✅ 直接连接 |
| 授权按会话绑定 | ⚠️ 注销/重启后要重新授权 | ✅ 自动可用 |
| 锁屏后无法远控解锁 | ❌ Wayland 冻结屏幕共享 | ✅ 可远控解锁 |
| 鼠标键盘控制失败 | ⚠️ 需 setuid + input 组 | ✅ 稳定 |
| 多显示器只抓主屏 | ⚠️ 副屏黑屏 | ✅ 全部可见 |
| portal 偶尔崩溃 | ⚠️ 黑屏/断连，要重启 portal | ✅ 稳定 |

**临时切 X11**：注销（不是重启）→ 登录界面点用户名 → 右下角齿轮 ⚙ → "Ubuntu on Xorg" → 登录。

**永久切 X11**：

```bash
# 备份
sudo cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak.$(date +%Y%m%d)
# 启用 X11
sudo sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
sudo reboot
```

**切回 Wayland**：`sudo sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' /etc/gdm3/custom.conf && sudo reboot`

**验证当前会话**：

```bash
echo $XDG_SESSION_TYPE   # x11 / wayland
```

### 备用：Wayland 下的 GNOME 远程桌面（RDP）

若必须留在 Wayland 又要被控，可配 GNOME 自带 RDP（仍受上表限制）：

```bash
gsettings set org.gnome.desktop.remote-desktop.rdp enable true
gsettings set org.gnome.desktop.remote-desktop.rdp screen-share-mode 'mirror-primary'
systemctl --user enable --now gnome-remote-desktop.service
mkdir -p ~/.config/gnome-remote-desktop
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=CN/O=RustDesk/CN=localhost" \
    -keyout ~/.config/gnome-remote-desktop/tls-key.pem \
    -out ~/.config/gnome-remote-desktop/tls-cert.pem
grdctl rdp set-tls-key ~/.config/gnome-remote-desktop/tls-key.pem
grdctl rdp set-tls-cert ~/.config/gnome-remote-desktop/tls-cert.pem
grdctl rdp disable-view-only
grdctl rdp set-credentials rustdesk "你的密码"
systemctl --user restart gnome-remote-desktop.service
```

## 国内速度：自建中继

默认公共中继在国外（`rs-ny.rustdesk.com`），国内使用慢/卡。自建 hbbs/hbbr 后在客户端配置：

```ini
# ~/.config/rustdesk/RustDesk2.toml
[options]
custom-rendezvous-server = '<服务器IP或域名>:30006'
relay-server = '<服务器IP或域名>:30007'
key = '<hbbs-公钥>'
```

完整部署见 [docs/24-工具-RustDesk自建中继](24-工具-RustDesk自建中继.md)。

## 🔒 被远控时的隐私：锁屏 + 关屏

RustDesk 是**物理屏幕镜像**（非远程会话），本地屏幕始终同步显示。办公室/公共场所被控时，用"锁屏 + DPMS 关屏"：对方看到锁屏界面并可输入密码解锁干活，物理屏幕黑着。

```bash
# 配套脚本 scripts/lock-for-remote.sh.example（拷到 ~/bin/ 后用）
~/bin/lock-for-remote.sh on      # 锁屏 + 关显示器
~/bin/lock-for-remote.sh off     # 唤醒显示器
```

典型工作流（远控办公电脑）：

```
离开前：lock-for-remote.sh on → 锁屏关屏 → 走人
远程端：家中任意设备 RustDesk 连办公电脑 ID → 输登录密码解锁 → 正常干活
回到工位：动鼠标唤醒 → 输密码接管
```

原理：`loginctl lock-session` 锁 GNOME 屏；`xset dpms force off` 关显示器（**仅 X11 可用**——切 X11 的又一个理由）。

局限：物理鼠标键盘仍可操作（只是看不到屏幕）；彻底隔离需虚拟显示器方案（dummy plug），RustDesk 不原生支持。

> RustDesk 不暴露连接事件（无 DBus/钩子），做不到"被连自动关屏"；监听输入空闲的 daemon 有误判风险，手动脚本/桌面图标/快捷键是最可靠形态。

## ⚠️ 已知坑：重启后离线（libdesktop_drop_plugin.so）

**现象**：重启后 RustDesk 显示"离线"，日志反复报：

```
/usr/share/rustdesk/rustdesk: error while loading shared libraries:
libdesktop_drop_plugin.so: cannot open shared object file: No such file or directory
```

`--server`（被控核心）崩溃-重启循环。

**根因**：二进制有 `RUNPATH: $ORIGIN/lib`，但 systemd 以 sudo 环境拉起 `--server` 子进程时 `$ORIGIN` 解析可能失效。

**修复（两道保险）**：

```bash
# 保险1：ldconfig 收录 rustdesk 库目录
echo "/usr/share/rustdesk/lib" | sudo tee /etc/ld.so.conf.d/rustdesk.conf
sudo ldconfig

# 保险2：systemd 服务注入 LD_LIBRARY_PATH
sudo mkdir -p /etc/systemd/system/rustdesk.service.d
sudo tee /etc/systemd/system/rustdesk.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment=LD_LIBRARY_PATH=/usr/share/rustdesk/lib
EOF
sudo systemctl daemon-reload
sudo systemctl restart rustdesk
```

**验证**：`ps -eo pid,cmd | grep "[r]ustdesk"` 应有 3 个进程（--service/--server/--tray）；`journalctl -u rustdesk --since "1 minute ago" | grep -i error` 无 libdesktop_drop 错误。

## ⚠️ 教训：不要给 rustdesk 加 setuid

为"输入模拟稳定"加 `chmod u+s` 反而会让 GTK+ 拒绝运行（安全机制），直接崩溃。RustDesk **不需要 setuid**，正确权限 `-rwxr-xr-x`。误加后撤销：

```bash
sudo chmod u-s /usr/share/rustdesk/rustdesk
```

日志里 `Cannot load libcuda.so.1` 警告无关紧要（NVIDIA CUDA 库，非 N 卡用不到，优雅降级）。

## 常见问题

**Q1：RustDesk 打不开界面** → `systemctl restart rustdesk`；还不行 `pkill rustdesk && rustdesk &`

**Q2：远控别人连不上** → 依次查：对方客户端开着吗/ID 对吗 → 本机能否到中继（`curl -v https://rs-ny.rustdesk.com`）→ 防火墙拦 UDP 21116 吗 → 换网络（手机热点）排除运营商问题

**Q3：被控时鼠标键盘无反应** → Wayland 输入控制受限，切 X11 会话（见上文）

**Q4：开机不自启** → `systemctl is-enabled rustdesk` 应为 enabled；否则 `sudo systemctl enable --now rustdesk`

**Q5：卸载** → `sudo apt-get purge rustdesk && rm -rf ~/.config/rustdesk`

## 替代方案备忘

| 软件 | 特点 | 适合 |
|------|------|------|
| **RustDesk** ⭐ | 开源，可自建中继 | Linux 首选 |
| ToDesk / 向日葵 | 国产，国内快，闭源 | 只用 Windows 时考虑 |
| AnyDesk | 国外，轻量 | 国外网络环境 |
| Remmina | Linux 原生 RDP/VNC 客户端 | 只主控不被控，连 Windows 远程桌面 |
