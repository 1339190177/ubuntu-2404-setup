# 12 · 工具 · DBeaver 数据库管理（MySQL）

> 装 DBeaver CE 替代 Navicat，免费开源的跨数据库可视化管理工具，含中文化与 MySQL 驱动配置。

---

## 背景：为什么选 DBeaver？

Navicat 是收费软件（且 Linux 版支持差），需要替代品。对比选型：

| 工具 | 免费 | 跨平台 | 多数据库 | Linux 支持 | 选型 |
|------|------|--------|----------|-----------|------|
| **DBeaver CE** | ✅ 开源 | ✅ | ✅ 80+ | ✅ 原生 | ✅ **首选** |
| MySQL Workbench | ✅ 社区版 | 部分 | 仅 MySQL | 一般 | 备选 |
| DataGrip | ❌ 收费 | ✅ | ✅ | ✅ | 学生授权可用 |
| HeidiSQL | ✅ | ❌ Win | 多种 | ❌ | Windows 专用 |

**选 DBeaver CE 的理由**：
- 社区版完全免费开源（Apache 2.0）
- 跨数据库通用（MySQL/PostgreSQL/SQLite/Oracle/SQL Server...）
- Snap 安装一条命令，自动更新
- 内置中文语言包，翻译质量好
- 功能齐全：SQL 编辑器、ER 图、数据导出、表结构管理

## 解决方案

### 一键安装（Snap）

```bash
# DBeaver CE 需要 classic 模式（访问 JDK、配置等）
sudo snap install dbeaver-ce --classic
```

> Snap 版由 dbeaver-corp 官方发布，自动更新。比 apt 更省心。

### 设置中文界面

DBeaver 内置中文语言包（`UIMessages_zh.properties`），但默认按系统语言加载。Snap 包内 `dbeaver.ini` 只读，通过启动参数 `-nl zh` 强制中文：

```bash
# 1. 复制桌面快捷方式到用户目录（覆盖 snap 默认的，不会被刷新覆盖）
mkdir -p ~/.local/share/applications/
cp /var/lib/snapd/desktop/applications/dbeaver-ce_dbeaver-ce.desktop \
   ~/.local/share/applications/

# 2. 修改 Exec 行，加上 -nl zh 参数；改显示名为中文标识
sed -i 's|^Exec=/snap/bin/dbeaver-ce %U|Exec=/snap/bin/dbeaver-ce -nl zh %U|' \
   ~/.local/share/applications/dbeaver-ce_dbeaver-ce.desktop
sed -i 's|^Name=dbeaver-ce|Name=DBeaver (中文)|' \
   ~/.local/share/applications/dbeaver-ce_dbeaver-ce.desktop

# 3. 给命令行也加别名
cat >> ~/.bashrc << 'EOF'

# DBeaver 启动别名（默认中文界面）
alias dbeaver-ce='dbeaver-ce -nl zh'
EOF

# 4. 刷新桌面数据库
update-desktop-database ~/.local/share/applications/
```

### 安装 MySQL JDBC 驱动（关键步骤）

**DBeaver 不内置 MySQL 驱动**（许可证原因），首次连接前必须下载。如果联网下载失败，手动下载 jar：

```bash
# DBeaver 26.x 的 MySQL 驱动定义（来自 plugin.xml）：
#   driver id="mysql8"  → com.mysql:mysql-connector-j:8.2.0
#   driver id="mysql5"  → mysql:mysql-connector-java:5.1.49
# 默认推荐 mysql8（promoted="1"）

# 创建驱动目录（DBeaver 期望的路径）
mkdir -p ~/.local/share/DBeaverData/drivers/mysql/mysql8

# 从 Maven 中央仓库下载
curl -L -o ~/.local/share/DBeaverData/drivers/mysql/mysql8/mysql-connector-j-8.2.0.jar \
     "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar"

# 验证驱动类存在
unzip -p ~/.local/share/DBeaverData/drivers/mysql/mysql8/mysql-connector-j-8.2.0.jar \
     META-INF/MANIFEST.MF | grep Implementation-Version
# 应输出: Implementation-Version: 8.2.0
```

> **如果不装驱动会报错**：`Connection URL preparation error - Cannot generate database URL with empty sample URL template for mysql`。这个错误信息有误导性，根因是驱动 jar 缺失，不是 URL 模板问题。

## 使用方法

### 启动

- **图形界面**：应用菜单搜 "DBeaver" → 点 **"DBeaver (中文)"**
- **命令行**：`dbeaver-ce &`

### 新建 MySQL 连接

1. 左上角点 **"新建数据库连接"**（或 `Ctrl+Shift+N`）
2. 搜索 `mysql`，选 **MySQL**（带推荐标志，对应 mysql8 驱动）
3. 填写连接信息：
   - **Server Host**：数据库地址
   - **Port**：端口（默认 3306）
   - **Username / Password**：账号密码
   - 勾选 **"保存密码"**
4. 点 **"测试连接"** → 成功后点 **"完成"**

### 从 Navicat 迁移连接（密码解密）

Navicat 的 `.ncx` 连接文件里的密码是加密的，需要解密才能迁移。算法见 [HyperSine/how-does-navicat-encrypt-password](https://github.com/HyperSine/how-does-navicat-encrypt-password)：

| Navicat 版本 | 密文长度 | 算法 | 密钥 |
|-------------|---------|------|------|
| Navicat 11 | 32 hex | Blowfish ECB（链式 CBC）| `SHA1("3DC5CA39")` |
| Navicat 12+ | 64+ hex | AES-128-CBC | Key=`libcckeylibcckey`，IV=`libcciv libcciv ` |

**NCX 文件位置**（Windows）：`C:\Users\<用户>\Documents\Navicat\` 或导出的 `connections.ncx`

解密脚本（基于权威实现，需要 `cryptography` 库）：

```bash
# 安装依赖
pip3 install --user cryptography

# 下载权威解密脚本（GitHub 直连超时，用 ghproxy 镜像）
curl -L -o /tmp/nav_ncx-dump.py \
     "https://ghproxy.net/https://raw.githubusercontent.com/HyperSine/how-does-navicat-encrypt-password/master/python3/ncx-dump.py"

# 老版 cryptography 库需要改一行 import
sed -i 's|from cryptography.hazmat.decrepit.ciphers.algorithms import Blowfish|from cryptography.hazmat.primitives.ciphers.algorithms import Blowfish|' /tmp/nav_ncx-dump.py

# 解密（输出 INI 格式的明文连接信息）
python3 /tmp/nav_ncx-dump.py /path/to/connections.ncx
```

> ⚠️ **DBeaver 不支持直接写配置文件批量导入**（6.1.3+ 起，用户名/密码存在加密的 `credentials-config.json`，第三方写入无效）。解密后只能**手动新建连接**或用 **CSV 导入**（文件 → 导入）。

## 常见问题

### Q1：报错 "empty sample URL template for mysql"

**根因**：MySQL JDBC 驱动没下载。DBeaver 出于许可证原因不内置 MySQL 驱动。

**解决**：见上文「安装 MySQL JDBC 驱动」，手动下载 `mysql-connector-j-8.2.0.jar` 到 `~/.local/share/DBeaverData/drivers/mysql/mysql8/`。

### Q2：snap 应用中文输入法不工作

Snap 的 classic 应用有时与 IBus/fcitx 有兼容问题。若 DBeaver 里无法输入中文：

```bash
# 设置 GTK_IM_MODULE（IBus 用户）
echo 'export GTK_IM_MODULE=ibus' >> ~/.profile
echo 'export QT_IM_MODULE=ibus' >> ~/.profile
# 重新登录生效
```

### Q3：首次连接很慢 / 一直转圈

DBeaver 首次连接 MySQL 会下载 JDBC 驱动（约 2.4MB）。如果网络慢，参考上文手动下载驱动 jar。

### Q4：连接报 "Communications link failure"

网络不通。检查：

```bash
# 测试端口连通性
nc -zv <host> <port>

# 如果是内网地址（10.x / 192.168.x），先连 OpenVPN
# 见 docs/11-网络-OpenVPN.md
```

### Q5：如何修改已导入的连接

右键连接 → **编辑连接**（Edit Connection），修改后保存。

### Q6：DBeaver 配置文件在哪

| 文件 | 位置 | 用途 |
|------|------|------|
| `data-sources.json` | `~/.local/share/DBeaverData/workspace6/General/.dbeaver/` | 连接定义（host/port，无密码）|
| `secure_storage` | `~/.local/share/DBeaverData/secure/` | 加密凭据（密码）|
| `drivers/` | `~/.local/share/DBeaverData/drivers/` | JDBC 驱动 jar |

## 卸载

```bash
# 卸载 DBeaver
sudo snap remove dbeaver-ce

# 清理配置（可选，会删除所有连接和驱动）
rm -rf ~/.local/share/DBeaverData/
rm -f ~/.local/share/applications/dbeaver-ce_dbeaver-ce.desktop
# 删除 ~/.bashrc 里的 dbeaver 别名
```

