# 04 · 工具 · aria2 下载神器

> 多线程下载工具，支持 HTTP/HTTPS/FTP/BT/磁力链。本文记录常用命令。

---

## 基本信息

| 项目 | 内容 |
|------|------|
| 命令 | `aria2c` |
| 版本 | 1.37.0 |
| 安装路径 | `/usr/bin/aria2c` |
| 安装方式 | `sudo apt-get install -y aria2` |
| 配置文件 | 无（按需创建 `~/.aria2/aria2.conf`） |
| 信息时效 | 2026-08-07 |

> 推荐**零配置**策略——默认参数已够用，需要高级特性时再按需配置。

## 快速上手

### 1. 最常用：多线程下载直链（提速明显）

```bash
# 16 线程下载（默认只有 1 个连接，加 -x 大幅提速）
aria2c -x16 https://example.com/file.zip
```

### 2. 断点续传（中断后接着下）

```bash
# 加 -c 即可，aria2 会自动识别已下载部分
aria2c -c -x16 https://example.com/large-file.iso
```

### 3. 指定下载目录和文件名

```bash
# -d 指定目录，-o 指定文件名
aria2c -x16 -d ~/下载 -o ubuntu.iso https://example.com/ubuntu.iso
```

### 4. 批量下载（从文件读 URL 列表）

```bash
# 把 URL 一行一个写进 urls.txt，aria2 依次下载
aria2c -x16 -j5 -i urls.txt    # -j5 表示同时下 5 个
```

### 5. BT/磁力链下载

```bash
# 磁力链
aria2c "magnet:?xt=urn:btih:xxxxx"

# 种子文件
aria2c file.torrent
```

## 常用参数速查

| 参数 | 含义 | 示例 |
|------|------|------|
| `-x N` | 每个服务器最大连接数（HTTP） | `-x16`（建议 16） |
| `-s N` | 分片下载的连接数 | `-s16` |
| `-j N` | 同时下载的任务数（批量时） | `-j5` |
| `-c` | 断点续传 | `-c` |
| `-d DIR` | 下载目录 | `-d ~/下载` |
| `-o NAME` | 输出文件名 | `-o file.zip` |
| `-i FILE` | 从文件读 URL 列表 | `-i urls.txt` |
| `--max-download-limit=` | 限速 | `--max-download-limit=1M` |
| `--max-tries=0` | 无限重试（网络不稳时用） | `--max-tries=0` |
| `-V`（大写） | 校验完整性（BT/种子有用） | `-V` |

## 推荐组合（直接抄）

```bash
# 通用下载（HTTP/HTTPS，提速 + 续传）
aria2c -x16 -s16 -c "https://example.com/file.zip"

# 下载到指定文件夹
aria2c -x16 -s16 -c -d ~/下载 "https://example.com/file.zip"

# 批量下载（5 个并发）
aria2c -x16 -j5 -c -d ~/下载 -i urls.txt
```

## 常见问题

### Q1：下载提示 "Too many connections for the same host"

服务器限制了单 IP 连接数。把 `-x` 调小，比如 `-x8` 或 `-x4`。

### Q2：下载速度没变快

可能原因：
- 服务器本身限速（再多的连接也没用）
- 你的带宽跑满了（用 `--max-download-limit=` 反而能验证）
- HTTPS 站点，aria2 默认复用连接，可加 `--split=N` 配合 `-s`

### Q3：想看下载进度更友好

aria2 默认显示进度条已够用。要更友好的图形界面，可装 WebUI（如 AriaNg），但需要 RPC 模式，较复杂。日常命令行足够。

### Q4：BT 下载没速度

BT 需要监听端口能被外网访问（NAT 穿透）。家庭网络通常需要端口映射，且默认端口可能被防火墙拦截。本文不做 BT 优化配置，有需要再单独搞。

## 速记口诀

> **日常下载就一条：`aria2c -x16 -c <URL>`**
> （16 线程 + 断点续传，覆盖 90% 场景）

