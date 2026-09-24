# 34 · 工具 · Worktile

> 一句话：Worktile 官方没有 Linux 客户端，用 Chrome `--app` 应用窗口封装官方网页版，得到独立桌面入口 + 独立登录态 + 独立任务栏图标的"准客户端"。

---

## 背景

Worktile（项目协作工具，官网 [worktile.com](https://worktile.com)）官方客户端只发 **Windows / Mac / iOS / Android** 四端：

- 官方下载页 `https://worktile.com/client` 实证（2026-09-22）：页面明确"iOS、Android、Windows、Mac 客户端"，无任何 Linux 产物
- 官方直链形如 `https://cdn-tc.worktile.com/release/worktile-9.0.0-win.exe`（Windows 9.0.0）/ `worktile-9.0.0-mac.dmg` / Android apk，无 deb/AppImage
- GitHub 上的第三方封装（如 Carre1/Worktile-For-Linux）多年未维护，不采用

结论：走**网页版封装**路线（本项目"官方无稳定直链"模式的变体：不是 Docker，而是浏览器应用窗口——因为 Worktile 本身是 Web 应用，网页版即全功能版）。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04 x86_64（GNOME，X11 会话） |
| 封装方式 | Chrome `--app` 独立窗口 + 专用 `--user-data-dir` |
| 图标 | 官方 CDN favicon.ico 转 png（48×48，`cdn-tc.worktile.com`） |
| 桌面入口 | `~/.local/share/applications/worktile.desktop`（+ `worktile-app.desktop` 别名，见下文） |
| 浏览器依赖 | google-chrome（优先）/ microsoft-edge 兜底，本机已装（docs/05） |
| 权限 | **全程无需 sudo**（只写 `~/.local` 和 `~/.config`） |
| 信息时效 | 2026-09-22 |

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
bash scripts/install-worktile.sh          # 图标 → .desktop → 校验（无需 sudo）
```

装完按 Super 键搜 "Worktile" 启动；首次需扫码/账号登录一次，之后登录态保存在专用 profile 里。

### 手工步骤（理解原理用）

```bash
# 1) 图标：官方 favicon.ico → png
curl -fsL "https://cdn-tc.worktile.com/static/site/wt/img/favicon.a824661.ico" -o /tmp/wt.ico
convert /tmp/wt.ico ~/.local/share/icons/worktile.png

# 2) 菜单项（关键字段见下节）
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/worktile.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Worktile
Exec=/usr/bin/google-chrome-stable --user-data-dir=/home/USER/.config/worktile-chrome --class=worktile-app --app=https://worktile.com --no-first-run --no-default-browser-check
Icon=/home/USER/.local/share/icons/worktile.png
Terminal=false
Categories=Office;ProjectManagement;
StartupWMClass=worktile-app
EOF
update-desktop-database ~/.local/share/applications
```

## 参数 / 配置详解

### 为什么用 `--user-data-dir` 专用 profile（最关键的参数）

Chrome 的 `--app` 窗口如果复用浏览器主 profile，会 attach 到已运行的 Chrome 进程：

1. `--class` 对新窗口**不生效**（WM_CLASS 继承首进程）→ 任务栏和浏览器混组
2. 登录态与浏览器共用 → 退出登录浏览器会话会连带影响
3. Chrome 单实例锁可能吞掉 `--app` 参数（本机踩过同类坑：Electron 单实例锁吞参数）

专用 profile（`~/.config/worktile-chrome`）一次解决三件事：窗口独立、登录态独立持久、不受浏览器进程状态影响。代价是与浏览器不共享 cookie，首次要登录一次。

### WM_CLASS 实测与本机 GNOME 匹配（X11 会话）

Chrome `--app` + `--class=worktile-app` 在 X11 会话下的真实窗口属性（`xprop` 实测，2026-09-22）：

```
WM_CLASS(STRING) = "worktile.com", "worktile-app"
                   ↑ instance 位       ↑ class 位（= --class 参数值）
```

instance 位被 Chrome 设为目标域名，不可控。GNOME Shell 把窗口匹配到 .desktop 有两条路，脚本**双路都铺**：

| 匹配路径 | 依赖 | 本脚本对策 |
|----------|------|-----------|
| `StartupWMClass` 字段 == WM_CLASS 的 class 位 | Shell 应用索引已加载该 desktop | `StartupWMClass=worktile-app` |
| WM_CLASS class 位直接当 desktop 文件 id 查（`worktile-app.desktop`） | 同名 desktop 文件存在 | 生成同内容别名 `worktile-app.desktop` |

> 别名这一步是实测教训：只靠 StartupWMClass 时，若 Shell 应用索引未及时刷新（desktop 晚于 Shell 启动创建），窗口可能归进 Chrome 组。别名文件让 id 匹配这条路不依赖索引新鲜度。改完 desktop 后若仍混组，Alt+F2 输入 `r` 回车重启 Shell（仅 X11 会话可用）重建索引。

### 图标为什么是 favicon

官方 CDN 上没有独立的品牌 logo 大图（官网页面的 logo 均为内联 SVG/第三方客户 logo）。favicon.ico（48×48）是唯一的官方位图资产，GNOME 应用网格尺寸下显示正常。

## 验证方法

```bash
bash scripts/install-worktile.sh verify    # 菜单项/图标/浏览器/desktop 格式/网页可达 五项校验
gtk-launch worktile                        # 从菜单入口启动（等价于 Super 键搜索启动）
wmctrl -lx | grep worktile                 # 应看到 worktile.com.worktile-app 独立窗口类
```

感官验收（看一眼即可）：Super 键 → 输入 Worktile → 回车，出现**无浏览器地址栏的独立窗口**即成功。

## 脚本用法

```bash
bash scripts/install-worktile.sh [子命令]
# icon    仅下载图标
# install 图标 + 生成菜单项（缺省 all 的组成部分）
# verify  五项校验
# launch  gtk-launch 启动（测试）
# remove  卸载菜单项与图标（登录数据默认保留）
# all     icon → install → verify（默认）
```

## 常见问题

**Q1: 为什么不装 Windows 版 + Wine？**
重、脆、升级不可控；网页版即全功能版，封装窗口体验已接近原生客户端。

**Q2: 任务栏里 Worktile 和 Chrome 图标混在一起？**
见上文"双路匹配"；确认 `worktile-app.desktop` 别名存在后 Alt+F2 → `r` 重启 Shell。个别环境下仍混组时功能无损（点击 Chrome 图标也能切到窗口），属 GNOME 窗口跟踪的显示层边界。

**Q3: 想彻底清除登录数据？**

```bash
rm -rf ~/.config/worktile-chrome     # 专用 profile（含登录态）
bash scripts/install-worktile.sh remove
```

**Q4: Worktile 里的 PingCode 入口？**
脚本在菜单项右键里附了"打开 PingCode"动作（同 profile 独立窗口，pingcode.com 为 Worktile 旗下研发管理产品）。

## 影响范围 / 安全权衡

- 全部产物在用户目录（`~/.local/share/applications`、`~/.local/share/icons`、`~/.config/worktile-chrome`），`remove` 子命令可完全回滚，不碰系统目录
- 网页版登录走官方站点，凭据不落第三方封装
- 附带效果：专用 profile 会占几十 MB 磁盘（Chrome 缓存）

