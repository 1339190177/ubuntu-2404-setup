# 08 · 工具 · 视频播放（VLC）

> 解决双击视频打不开的问题。Ubuntu 24.04 最小化安装默认无视频播放器、无 H.264 等解码器。

---

## 背景：为什么视频打不开？

双击视频文件无反应（示例：`~/win_e/.../xxx.mp4`）。排查发现：

| 检查项 | 结果 |
|--------|------|
| 视频文件本身 | ✅ 完整可读（H.264, 480p, 1.6s, 271KB）|
| **视频播放器** | ❌ **一个都没装**（totem/mpv/vlc 全无）|
| GStreamer 解码器 | ❌ 缺 plugins-bad/ugly/libav |
| 默认视频应用 | ❌ 未设置 |
| ffmpeg | ✅ 已装（命令行可用） |

**本质原因**：系统里根本没有能播放视频的应用。Ubuntu 24.04 桌面版最小化安装不预装播放器。

**为什么不预装解码器**：H.264/H.265 等编码有专利，Ubuntu 默认不含 `ubuntu-restricted-extras`。VLC 自带所有解码器，所以装 VLC 一劳永逸。

## 解决方案：装 VLC + 设为默认

### 一键安装

```bash
# 1. 装 VLC（自带所有解码器，不依赖系统）
sudo apt-get install -y vlc

# 2. 设为各种视频格式默认应用
for mime in video/mp4 video/x-matroska video/x-msvideo video/quicktime \
            video/x-ms-wmv video/mpeg video/webm video/x-flv application/ogg; do
  xdg-mime default vlc.desktop "$mime"
done

# 3. 验证
xdg-mime query default video/mp4    # 应输出 vlc.desktop
```

### 安装结果

| 项目 | 内容 |
|------|------|
| 播放器 | **VLC 3.0.20 Vetinari** |
| 路径 | `/usr/bin/vlc` |
| 默认视频应用 | VLC（mp4/mkv/avi/mov/wmv/mpeg/webm/flv/ogg）|
| 信息时效 | 2026-08-07 |

## 使用方法

**双击视频文件** → 自动用 VLC 打开。

**命令行播放**：
```bash
vlc /path/to/video.mp4           # 图形界面播放
vlc --no-video audio.mp3         # 只放音频
cvlc video.mp4                   # 无界面控制台模式（脚本用）
```

**VLC 常用快捷键**：
| 按键 | 作用 |
|------|------|
| `空格` | 播放/暂停 |
| `f` | 全屏 |
| `m` | 静音 |
| `↑/↓` | 音量 |
| `Ctrl+←/→` | 快退/快进 1 分钟 |
| `q` | 退出 |

## 命令行替代：用 ffplay 快速预览

系统已装 ffmpeg，自带 `ffplay`（极简播放器，无界面控件，调试用）：

```bash
ffplay /path/to/video.mp4
ffplay -x 800 -y 600 video.mp4     # 指定窗口大小
ffplay -an video.mp4               # 只看画面不放声音
```
适合脚本里快速验证视频文件是否能解码。

## 常见问题

### Q1：VLC 播放卡顿/花屏

可能是 GPU 加速兼容问题。VLC 里：工具 → 首选项 → 视频 → 取消"加速视频输出(OpenGL)"，重启 VLC。

### Q2：仍然有些格式打不开（如 HEVC/H.265）

VLC 3.0+ 自带 HEVC 解码，一般够用。如真缺：
```bash
sudo apt install libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav
```

### Q3：想用系统默认播放器（Totem/视频）而非 VLC

装解码器后改默认：
```bash
sudo apt install ubuntu-restricted-extras totem
xdg-mime default org.gnome.Totem.desktop video/mp4
```

### Q4：缩略图不显示（文件管理器里视频无预览图）

```bash
sudo apt install ffmpegthumbnailer
# 然后在文件管理器首选项里开启缩略图（默认已开）
```

### Q5：Web 网页视频播放不了（如 B 站、YouTube）

这是另一回事——浏览器要 HTML5 视频支持。Edge/Firefox 现代版本都自带，无需额外装。如果还不行，检查是否装了 `libavcodec-extra`。

## 备选播放器

如果以后想要其他播放器：

```bash
sudo apt install mpv              # 极简、命令行友好、高质量
sudo apt install smplayer         # mpv/mplayer 的图形前端
sudo apt install celluloid        # mpv 的 GNOME 风格前端（推荐桌面用）
```

