# 14 · 工具 · 远程 SSH 客户端（Tabby）

> 用 Tabby 替代 Windows 下的 Xshell，连接无桌面的 Linux 服务器。含 SSH 终端、SFTP 文件传输、多服务器分组管理。从 Xshell 一键迁移连接配置（不导入密码）。

---

## 背景：为什么选 Tabby？

Ubuntu 自带 OpenSSH 客户端（`ssh`/`scp`/`sftp` 命令行），能满足基本需求，但缺少：
- 多服务器集中管理（密码/密钥/连接配置）
- 图形化 SFTP 文件浏览与拖拽传输
- 多标签页、分屏、主题美化
- 会话保存与一键重连

**选型对比**（MobaXterm/Xshell 的现代开源替代）：

| 工具 | GitHub Stars | SSH | SFTP | 优势 | 选型 |
|------|-------------|-----|------|------|------|
| **Tabby** | 65k+ | ✅ | 需插件 | 社区大、插件多、主题丰富 | ✅ **选用** |
| Electerm | 11k+ | ✅ | ✅ 原生 | SSH+SFTP 一体、免费云同步 | 试后弃用 |
| Termius | - | ✅ | ✅ | 跨设备同步，但免费版受限 | ❌ 收费 |
| MobaXterm | - | ✅ | ✅ | Windows 专属，功能强 | ❌ Win 专用 |

**选 Tabby 的理由**：社区最活跃（65k star）、插件生态丰富、YAML 配置易迁移、跨平台。
> Electerm 曾装过试用，后决定专注用 Tabby，已 `sudo snap remove electerm` 卸载。

## 解决方案：安装 Tabby（deb 包）

Tabby 没有 Snap 包，用官方 deb。GitHub 直连慢/超时，用 aria2 多线程 + ghproxy 镜像下载：

```bash
# 1. 下载（aria2 16 线程，比 curl 快 10 倍且不断流）
aria2c -x 16 -s 16 -k 1M \
    -d /tmp -o tabby.deb \
    "https://ghproxy.net/https://github.com/Eugeny/tabby/releases/download/v1.0.225/tabby-1.0.225-linux-x64.deb"

# 2. 安装
sudo dpkg -i /tmp/tabby.deb
sudo apt-get install -f -y   # 补依赖（如有缺失）

# 3. 清理
rm /tmp/tabby.deb
```

> **下载技巧**：Tabby deb 包约 112MB，`curl` 单线程经常在 ghproxy 镜像上断流（下到 13MB 就 INTERNAL_ERROR）。`aria2 -x 16` 多线程可稳定 2MB/s 下载完。详见 [docs/04-工具-aria2下载神器.md](04-工具-aria2下载神器.md)。

### 验证

```bash
dpkg -l tabby-terminal       # 应显示 1.0.225
which tabby                  # /usr/bin/tabby
```

应用菜单会生成 "Tabby" 图标，可直接搜索启动。

## 从 Xshell 迁移连接到 Tabby

### 背景：Xshell 配置存储

Xshell 的会话存在 Windows 用户目录下：

```
C:\Users\<用户>\Documents\NetSarang Computer\6\Xshell\Sessions\
├── *.xsh                      # 每个会话一个文件（INI 格式）
├── default                    # 默认会话模板（忽略）
├── folder.ini                 # 目录元数据（忽略）
└── <分组目录>/                # 子目录即分组（支持多级）
    └── *.xsh
```

**`.xsh` 文件特点**：
- 编码：**UTF-16 LE**（带 BOM `\xff\xfe`，Python 读取要先 `raw[2:].decode('utf-16-le')`）
- 格式：INI（`[SECTION]\nKey=Value`）
- 关键字段：

  | 段 | 字段 | 含义 |
  |----|------|------|
  | `[CONNECTION]` | `Host` | 主机 IP/域名 |
  | `[CONNECTION]` | `Port` | 端口（默认 22）|
  | `[CONNECTION]` | `Protocol` | 协议（SSH/TELNET/SERIAL）|
  | `[CONNECTION:AUTHENTICATION]` | `UserName` | 用户名 |
  | `[CONNECTION:AUTHENTICATION]` | `Method` | 0=密码，1=公钥 |
  | `[CONNECTION:AUTHENTICATION]` | `Password` | 加密的密码（**不读取**）|

> **密码不迁移的理由**：Xshell 密码加密依赖 Windows DPAPI，跨平台解密复杂；且服务器密码定期改，迁移意义不大。连接时手动输入或配 SSH 密钥免密更稳妥。

### 转换脚本

脚本位置：`/tmp/xshell_to_tabby.py`（核心逻辑可复用）：

```python
#!/usr/bin/env python3
"""
Xshell .xsh → Tabby config.yaml SSH profile
- 保留分组（Xshell 目录结构 → Tabby group 字段）
- 不导入密码
- 跳过非 SSH 协议
"""
import configparser, os, yaml
from pathlib import Path

XSESS = "~/win_c/Users/<用户名>/Documents/NetSarang Computer/6/Xshell/Sessions"
TABBY_CONFIG = Path.home() / ".config/tabby/config.yaml"

def read_xsh(filepath):
    """读取 UTF-16 LE 或 UTF-8 编码的 .xsh 文件"""
    with open(filepath, 'rb') as f:
        raw = f.read()
    if raw[:2] == b'\xff\xfe':          # UTF-16 LE BOM
        text = raw[2:].decode('utf-16-le')
    elif raw[:3] == b'\xef\xbb\xbf':    # UTF-8 BOM
        text = raw[3:].decode('utf-8', errors='ignore')
    else:
        text = raw.decode('utf-8', errors='ignore')
    if text.startswith('\ufeff'):       # 残留 BOM
        text = text[1:]
    return text

# 1. 遍历所有 .xsh，提取 host/port/user
sessions = []
for root, dirs, files in os.walk(XSESS):
    rel = os.path.relpath(root, XSESS)
    for f in sorted(files):
        if f in ('folder.ini', 'default') or not f.endswith('.xsh'):
            continue
        cp = configparser.ConfigParser(strict=False)
        cp.read_string(read_xsh(os.path.join(root, f)))
        host = cp.get('CONNECTION', 'Host', fallback='')
        port = cp.get('CONNECTION', 'Port', fallback='22')
        proto = cp.get('CONNECTION', 'Protocol', fallback='SSH')
        user = cp.get('CONNECTION:AUTHENTICATION', 'UserName', fallback='')
        if proto.upper() != 'SSH' or not host:
            continue
        group = '' if rel == '.' else rel.replace(os.sep, '/')
        sessions.append({
            'type': 'ssh', 'name': f[:-4], 'host': host,
            'port': int(port) if str(port).isdigit() else 22,
            'user': user, **({'group': group} if group else {})
        })

# 2. 合并进 Tabby config.yaml（备份原文件）
config = yaml.safe_load(TABBY_CONFIG.read_text(encoding='utf-8')) or {}
backup = TABBY_CONFIG.with_suffix('.yaml.before-xshell-import')
backup.write_text(TABBY_CONFIG.read_text(encoding='utf-8'), encoding='utf-8')
config.setdefault('profiles', []).extend(sessions)
TABBY_CONFIG.write_text(
    yaml.dump(config, allow_unicode=True, default_flow_style=False, sort_keys=False),
    encoding='utf-8')
print(f"导入 {len(sessions)} 个 SSH 连接")
```

### 执行迁移

```bash
# 1. 确保 PyYAML 已装
pip3 install --user pyyaml

# 2. 关闭 Tabby（避免配置冲突）
pkill -f tabby
rm -f ~/.config/tabby/SingletonLock  # 清理单例锁

# 3. 执行转换（脚本会自动备份原 config.yaml）
python3 /tmp/xshell_to_tabby.py

# 4. 启动 Tabby 验证
tabby &
```

## 使用方法

### Tabby：连接服务器

1. 启动 Tabby → 左侧 **"连接"** 标签（或 `Ctrl+Shift+T`）
2. 在分组树中找到目标连接 → **双击**即可连接
3. 首次连接会提示：
   - 输入密码（不保存）
   - 或选 **Private Key** 指向 `~/.ssh/id_ed25519`（免密，见下文）
4. 确认主机指纹（首次）→ 进入终端

**多标签**：`Ctrl+T` 新开标签，`Ctrl+Tab` 切换。
**分屏**：`Ctrl+Shift+D` 右分屏，`Ctrl+Shift+S` 下分屏。

### 装 SFTP 插件（Tabby 默认不带）

Tabby 默认不带 SFTP，需手动装：

1. `Ctrl+,` 打开设置 → 左侧 **"插件"**
2. 搜索 `sftp` → 安装 **SFTP** 插件
3. 重启 Tabby，SSH 连上后 `Ctrl+Shift+S` 打开 SFTP 面板

## 配置 SSH 密钥免密登录（推荐）

迁移后连接都要输密码较麻烦。配 SSH 密钥一劳永逸（Tabby 和命令行通用）：

```bash
# 1. 生成密钥（已有可跳过）
ssh-keygen -t ed25519 -C "$USER@ubuntu"
# 一路回车（不设密钥密码则登录免密）

# 2. 把公钥推到服务器（首次需输密码）
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@172.20.0.4

# 3. 之后免密登录
ssh root@172.20.0.4         # 直接进，不用输密码
```

Tabby 里连接时，认证方式选 **Private Key** → 指向 `~/.ssh/id_ed25519`，即可免密。

## 常见问题

### Q1：Tabby 启动后白屏 / 闪退

Electron 应用与某些 GPU 驱动冲突。试禁用 GPU 加速：

```bash
tabby --disable-gpu
```

如有效，编辑 `~/.config/tabby/config.yaml` 加：

```yaml
env:
  DISABLE_GPU: "1"
```

### Q2：连接服务器超时 / Connection refused

```bash
# 1. 测试网络连通性
nc -zv <host> 22

# 2. 内网地址（10.x / 192.168.x）需先连 OpenVPN，见 docs/11-网络-OpenVPN.md
# 3. 确认服务器 sshd 已运行：sudo systemctl status ssh
```

### Q3：中文显示乱码

Tabby 默认 UTF-8，一般无此问题。如出现：设置 → Appearance → Font 选 `Noto Sans Mono CJK SC` 或 `Sarasa Mono SC`。

### Q4：如何卸载

```bash
sudo dpkg -r tabby-terminal
rm -rf ~/.config/tabby/
```

## 备选方案

如果以后想换其他工具：

```bash
# Termius（跨平台，免费版功能受限）
sudo snap install termius-app

# Remmina（GNOME 自带远程客户端，支持 SSH/VNC/RDP）
sudo apt install remmina remmina-plugin-secret

# FileZilla（纯 SFTP 客户端，类似 WinSCP）
sudo apt install filezilla

# VS Code Remote-SSH（远程开发最强方案）
# 在 VS Code 里装 "Remote - SSH" 扩展即可
```

