# 28 · 工具 · 图片编辑 GIMP（含水印指南）

> 一句话：在 Ubuntu 上用 apt 安装 GIMP 2.10，本地编辑图片（裁剪/缩放/调色/标注）并加文字或图片水印，全程离线不外发。
>
> ⚠️ **日常只想加个水印 → 别用 GIMP**，用右键一键水印（docs/29，零学习成本 30ms/张）；本篇水印章节适合需要精细排版/平铺模板的场景。

---

## 背景

需要一款**本地**图片编辑器：偶尔裁剪、缩放、调整截图，以及给要外发的图片加**水印**（文字版权水印 / logo 图片水印）。要求：

- 不用在线工具（图片不出本机）
- 免费、apt 官方源可装、可复现
- 水印是刚需，不是锦上添花

选型对比：

| 候选 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| **GIMP（采用）** | Linux 事实标准、图层+文字工具天然适合水印、apt 官方源 | 界面专业，上手略陡 | ✅ |
| Pinta | 轻量、像 Windows 画图 | 图层/文字控制弱，做水印别扭 | ❌ |
| ImageMagick | 命令行批量水印强 | 不是 GUI 编辑器，单图编辑不直观 | ❌（批量场景见 Q5） |
| Krita | 强大 | 面向绘画，杀鸡用牛刀 | ❌ |

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| 安装方式 | `apt install gimp`（官方源，属本项目"官方有 apt 包"模式） |
| 当前版本 | **GIMP 2.10.36**（2026-09-14 实测，包 `2.10.36-3ubuntu0.24.04.1`） |
| 磁盘占用 | 主程序+资源 ≈ 108 MB（gimp 19.5M + gimp-data 87M + libgimp 4M，不含公共依赖） |
| 命令 | `/usr/bin/gimp` |
| 桌面入口 | `/usr/share/applications/gimp.desktop`（Super 键搜 "GIMP"） |
| 用户配置 | `~/.config/GIMP/2.10/` |

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>
sudo bash scripts/install-gimp.sh        # install → verify
```

### 手工步骤（理解原理用）

```bash
sudo apt update
sudo apt install -y gimp
gimp --version        # 期望：GNU 图像处理程序 版本 2.10.36
```

---

## 水印操作指南（核心）

### A. 文字水印（GUI，最常用）

```text
1. 打开图片：gimp 你的图片.png（或 GIMP 里 文件→打开）
2. 左侧工具箱选「文字工具 A」（快捷键 T），点图片上要放水印的位置，输入文字
   （中文用 IBus 正常输入，见 Q3）
3. 上方工具选项调字体/字号/颜色（版权水印常用白色 + 稍大字号）
4. 右侧图层面板选中该文字图层 → 「不透明度」降到 30~60%（半透明关键一步）
   └─ 想更融合：图层模式从「正常」换「叠加/柔光」
5. 移动位置：工具箱「移动工具 M」拖动文字层
6. 导出：文件→导出为（Ctrl+Shift+E）→ 文件名以 .jpg/.png 结尾 → 点「导出」
   └─ 注意是「导出」不是「保存」：保存是 .xcf 工程文件
```

### B. 图片水印（logo / 二维码盖图）

```text
1. 打开底图
2. 文件→作为图层打开… 选择 logo（PNG 带透明最佳），logo 成为新图层
3. 缩放：图层→缩放图层… 设定像素宽高（如 200）
4. 拖位置：移动工具 M
5. 降不透明度 30~60%，或图层模式换「叠加」
6. 导出 Ctrl+Shift+E
```

### C. 批量水印（无头 Script-Fu，实测可用）

给单张图加半透明右下角文字水印的完整命令（2026-09-14 本机实测）：

```bash
# 1) 生成脚本文件（避开 shell/Scheme 双层引号地狱，推荐 load 方式）
cat > /tmp/wm.scm << 'EOF'
(let* ((img (car (gimp-file-load RUN-NONINTERACTIVE "@IN@" "@IN@"))))
  (let* ((txt (car (gimp-text-fontname img -1 40 520 "$USER · 版权所有"
                                       -1 TRUE 36 PIXELS "Sans"))))
    (gimp-layer-set-opacity txt 60))
  (gimp-image-flatten img)
  (gimp-file-save RUN-NONINTERACTIVE img (car (gimp-image-get-active-layer img))
                  "@OUT@" "@OUT@")
  (gimp-quit 0))
EOF
# 2) 替换输入/输出路径后执行
sed -i 's|@IN@|~/gimp-sample.png|; s|@OUT@|~/out.png|' /tmp/wm.scm
gimp -i -b '(load "/tmp/wm.scm")'
```

批量（当前目录所有 jpg 加同款水印）：

```bash
for f in *.jpg; do
  sed "s|@IN@|$PWD/$f|; s|@OUT@|$PWD/wm-$f|" /tmp/wm.scm > /tmp/wm-one.scm
  gimp -i -b '(load "/tmp/wm-one.scm")'
done
```

### Script-Fu 水印的两个签名坑（网上老教程会踩）

| 坑 | 现象 | 正确写法 |
|----|------|----------|
| 颜色参数写成字符串 | `Invalid type for argument 1 to gimp-context-set-foreground` | 传列表 `(gimp-context-set-foreground '(52 120 198))`，不是 `"(52 120 198)"` |
| `gimp-text-fontname` 老示例 9 参 | `expected 10 but received 9` | 2.10.36 是 **10 参**：`image drawable x y text border antialias size size-type fontname`，多出的 `size-type` 取 `PIXELS`/`POINTS`（无 run-mode 参数） |

## 验证方法

```bash
# 1. 命令与版本
gimp --version                    # GNU 图像处理程序 版本 2.10.36

# 2. 脚本版校验（命令/版本/桌面入口三项）
bash scripts/install-gimp.sh verify

# 3. 水印链路自测：无头生成一张"蓝底+半透明中文水印"样图并打开细看
bash scripts/install-gimp.sh sample    # → ~/gimp-sample.png
gimp ~/gimp-sample.png                 # 左下角应有半透明白字「$USER · 版权所有」

# 4. GUI 冒烟：Super 键搜 GIMP 打开，按上方「水印操作指南 A」走一遍
```

## 脚本用法

```bash
bash scripts/install-gimp.sh help          # 所有子命令

sudo bash scripts/install-gimp.sh          # 一键 install → verify（推荐）
bash    scripts/install-gimp.sh verify     # 仅校验
bash    scripts/install-gimp.sh sample     # 生成水印自测样图 ~/gimp-sample.png
bash    scripts/install-gimp.sh sample /tmp/x.png   # 指定输出路径
sudo bash scripts/install-gimp.sh remove   # 卸载
```

`sample` 子命令同时是**无头模式的三坑实测沉淀**（sudo 下跑 GIMP 无头必看）：

| 坑 | 现象 | 解法（脚本已内置） |
|----|------|--------------------|
| `su - <user>` 被 PAM 拦 | root 切普通用户也要密码 | 用 `runuser -u <user> --` |
| sudo 清掉 `XDG_RUNTIME_DIR` | gimp 无头启动**挂死不退出** | `env XDG_RUNTIME_DIR=/run/user/<uid>` 补回 |
| root 的 `mktemp` 是 600 | runuser 后 gimp 读不了 scm 文件 | `chmod 644` 后再给 gimp load |

## 常见问题

**Q1：GIMP 打开图片默认是"单窗口"还是多窗口？**

2.10 默认单窗口模式（类似 Photoshop 布局）。如果误切到多窗口：窗口→单窗口模式勾回来。

**Q2：导出 JPG 时提示质量选项，选多少？**

默认 85 即可；要求高清选 90~95。**不要用「保存」导出成品**——保存 = `.xcf` 工程（保留图层），外发用「导出为」（Ctrl+Shift+E）。

**Q3：文字工具里打不出中文？**

本机 IBus（docs/10）在 GIMP 下正常。若切换输入法无效，检查 GIMP 窗口是否获得焦点后再切换（Super+Space）；仍不行重启 IBus：`ibus restart`。无头模式下用的 "Sans" 字体（fontconfig 别名→Noto Sans CJK）实测中文渲染正常。

**Q4：图片元数据（EXIF/GPS）想一起去掉再外发？**

导出 PNG 不含 EXIF；导出 JPG 时在导出对话框「高级」里取消勾选注释/EXIF 项；或用 `exiftool -all= 图.jpg`（需另装 libimage-exiftool-perl）。

**Q5：几十张图批量加同一水印，GUI 太慢？**

见上文「C. 批量水印」for 循环；量更大（上百张/多目录）时建议改用 ImageMagick：`sudo apt install imagemagick` 后 `composite -dissolve 40% -gravity southeast watermark.png 原图.jpg out.jpg`。

**Q6：怎么彻底卸载？**

```bash
sudo bash scripts/install-gimp.sh remove       # apt remove --purge + autoremove
rm -rf ~/.config/GIMP                          # 用户配置（ brushes/预设等）
```

## 影响范围 / 安全权衡

- 纯本地离线工具，不联网上报任何数据（无遥测）
- 磁盘 ≈108 MB（主包），依赖均来自 Ubuntu 官方仓库
- 不改系统配置、不注册文件关联为默认（打开方式仍按 docs/18 的默认应用规则，可右键"使用 GIMP 打开"）
- 卸载干净，仅 `~/.config/GIMP/` 用户配置残留（见 Q6）

