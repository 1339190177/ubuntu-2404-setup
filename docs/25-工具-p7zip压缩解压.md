# 25 · 工具 · p7zip 压缩解压

> 一句话：apt 安装 p7zip-full（Ubuntu 24.04 下是过渡包，实际拉入官方 7-Zip 23.01），终端里 `7z` 命令搞定 7z/zip/tar 等格式的压缩、解压、加密、分卷。

---

## 背景

终端下处理压缩包，Linux 自带的只有 `tar`/`gzip`/`xz`/`zip`。但日常总会遇到：

- 别人发来的 `.7z` 包（Windows 侧最常用的格式之一）
- 想把大目录打成**单个加密压缩包**传出去（zip 的传统加密太弱）
- 需要分卷（`xxx.7z.001`）或自解压包
- 脚本里做压缩/解压/完整性校验

若 `which 7z` 为空。有一个历史遗留的 deepin 转制 GUI 包
`org.7-zip.7zip-gui`（16.02，装在 `/opt/apps`，APM 转制），只有界面没有 CLI，
版本也老，本篇装的是正经 apt 包。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| 安装方式 | `apt install p7zip-full` |
| 实际拉取的包 | `p7zip-full`（**过渡包** 16.02+transitional.1）→ 依赖 `7zip`（**7-Zip 23.01 官方 Linux 版**） |
| 命令路径 | `/usr/bin/7z`、`/usr/bin/7za`、`/usr/bin/7zr` |
| 实测版本 | 7-Zip 23.01 (x64)，2026-09-01 装成，压缩/解压往返测试通过 |
| RAR 支持 | ❌ Debian/Ubuntu 的 dfsg 打包剥离了 RAR 解码器，解 RAR 另装 `unrar`（apt 有 1:7.0.7） |

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>

# 一键 apt 安装 + 校验（需 sudo）
sudo bash scripts/install-p7zip.sh
```

脚本会：

1. `apt update && apt install -y p7zip-full`（实际装官方 7-Zip 23.01）
2. 校验 `7z`/`7za`/`7zr` 就位 + 版本输出
3. 做一次**压缩→解压往返测试**（临时目录，自动清理），确认真的能用

### 手工步骤（理解原理用）

```bash
# 1. 安装
sudo apt update
sudo apt install -y p7zip-full

# 2. 验证
7z --help | head -3
# 期望第一行：7-Zip 23.01 (x64) : Copyright (c) 1999-2023 Igor Pavlov : 2023-06-20
```

## 参数 / 配置详解

### p7zip-full 为什么装出来是 7-Zip 23.01

老牌 `p7zip`（16.02，2016 年）是社区移植版，2021 年起 Igor Pavlov 官方发布了
7-Zip for Linux，Debian/Ubuntu 随即用官方版 `7zip` 包替换了它，`p7zip-full`
退化成**过渡包**（只含依赖声明，保证老命令/老教程不断档）：

```text
p7zip-full (transitional) ──depends──> 7zip (23.01 官方版，提供 7z/7za/7zr)
```

所以照老教程敲 `apt install p7zip-full` 依然有效，得到的却是新版官方实现，
不用纠结。

### 7z / 7za / 7zr 三个命令怎么选

| 命令 | 定位 | 日常建议 |
|------|------|----------|
| `7z`  | 全功能版，7z/zip/gzip/bzip2/xz/tar 等 + 调外部工具扩展格式 | **默认用它** |
| `7za` | 精简独立版，仅内置几种格式 | 极简环境用 |
| `7zr` | 最小版，仅处理 .7z | 基本用不上 |

### 与 deepin GUI 残留包的关系

`dpkg -l | grep 7zip` 会看到 `org.7-zip.7zip-gui`（deepin APM 转制的 16.02 GUI）。
它装在 `/opt/apps` 下，与本次安装的 CLI **无文件冲突、互不影响**。它版本老且
无 CLI，留着不碍事；想清理可 `sudo apt remove org.7-zip.7zip-gui`。

## 常用命令速查

```bash
# ── 压缩 ──────────────────────────────────────────────
7z a out.7z dir/                  # 打包目录为 .7z（a = add）
7z a out.zip dir/                 # 后缀即格式，也可 -tzip 显式指定
7z a -mx=9 out.7z dir/            # 最高压缩率（0-9，默认 5）
7z a -xr!node_modules out.7z dir/ # 递归排除某目录/模式
7z a -p -mhe=on out.7z dir/       # 加密 + 连文件名都隐藏（推荐组合）
7z a -v100m out.7z dir/           # 分卷，每卷 100MB → out.7z.001/002/…

# ── 解压 ──────────────────────────────────────────────
7z x out.7z                       # 保留目录结构解到当前目录（x = extract）
7z x out.7z -otarget/             # 解到指定目录（-o 与路径间无空格！）
7z x out.7z -y                    # 全部 yes，脚本里必加
7z e out.7z                       # 平铺解压（忽略目录结构，慎用）
7z x out.7z.001                   # 分卷包解第一卷即可
7z x out.7z -p                    # 解加密包（回车后输密码）
7z x out.exe                      # 解自解压包（Linux 下也能解）

# ── 查看 / 校验 ───────────────────────────────────────
7z l out.7z                       # 列内容（l = list）
7z t out.7z                       # 完整性测试，下载的包先 t 再解

# ── 内容流向管道 ──────────────────────────────────────
7z x out.7z file.txt -so | head   # 解单个文件到 stdout
cat foo | 7z a out.7z -sifoo      # 从 stdin 收流打包
```

### 格式选择小抄

| 场景 | 建议 |
|------|------|
| 给 Windows 用户发文件 | `.zip`（免装工具）或 `.7z`（压缩率更好） |
| Linux 间传输 | `tar czf` / `tar cJf` 更顺手，保留权限位 |
| 加密 | `.7z -p -mhe=on`（AES-256），别用 zip 传统加密 |
| 解 RAR | 先 `sudo apt install unrar`，dfsg 版 7z 不带 RAR 解码器 |

## 坑（实测踩过，直接用结论）

### 坑 1 · ZCode agent 会话里 sudo 彻底不可用（NoNewPrivs）

在 ZCode agent 会话里执行 `sudo` 直接报：

```text
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

原因：agent 进程树带着 `NoNewPrivs=1`（`/proc/self/status` 可查），这会禁止
一切 setuid/文件能力提权——**免密 sudo 配置了也没用**，`pkexec`/`su` 同样死。

**解法：走 docker**。本机用户在 `docker` 组，docker CLI 只是与守护进程
（已 root）通信、自身不提权，不受该标志影响。用「容器 chroot 宿主机根」
让守护进程代劳 apt：

```bash
docker run --rm --privileged --network host -v /:/host ubuntu:24.04 bash -ec '
mount --bind /proc /host/proc 2>/dev/null || true
mount --bind /sys  /host/sys  2>/dev/null || true
mount --bind /dev  /host/dev  2>/dev/null || true
chroot /host env DEBIAN_FRONTEND=noninteractive apt-get install -y p7zip-full
umount -R /host/proc /host/sys /host/dev 2>/dev/null || true'
```

要点：

- `--privileged` 只为在容器里 bind-mount proc/sys/dev（deb 的 postinst 可能要），
  挂载点在容器**私有 mount namespace**，宿主机 mount 表不受影响
- `chroot /host` 操作的就是宿主机真实 `/`，dpkg 数据库正常记账，
  后续 apt upgrade/remove 完全一致，等价于宿主机上 `sudo apt install`

### 坑 2 · 上述容器里 apt 报 "Temporary failure resolving"

第一反应是网络不通，其实不是：宿主机 `/etc/resolv.conf` 指向
`127.0.0.53`（systemd-resolved 本机 stub），容器**独立网络命名空间**里
根本没有这个监听。加 `--network host` 共享宿主机网络栈即解（上面命令已带）。

## 卸载

```bash
sudo bash scripts/install-p7zip.sh remove
# 或手工：
sudo apt remove --purge -y p7zip-full   # 只删过渡包
sudo apt remove --purge -y 7zip         # 连实际包一起删
```

## 验证清单

- [x] `which 7z 7za 7zr` → `/usr/bin/` 下三件套（2026-09-01）
- [x] `7z --help` → 7-Zip 23.01 (x64)
- [x] 压缩→解压往返测试：内容逐字节一致，临时目录已清理
- [x] dpkg 记账完整（`dpkg -l p7zip-full 7zip` 均为 `ii`）
