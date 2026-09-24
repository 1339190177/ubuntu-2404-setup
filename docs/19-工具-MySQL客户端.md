# 19 · 工具 · MySQL 客户端

> 一句话：在 Ubuntu 上用 apt 安装 MySQL 8.0 命令行客户端，让后端开发/运维能在终端直连远端 MySQL（不必每次开 DBeaver）。

---

## 背景

本机已有两条 MySQL 相关配置：

| 已有 | 位置 | 作用 |
|------|------|------|
| DBeaver（GUI） | docs/12 | 图形化查表、导数据、看 ER 图 |
| MySQL 服务端 | Docker 容器（docs/13） | 本地业务库实例 |

但**缺一个命令行客户端**。后端日常会有这些场景，开 GUI 太重：

- 脚本里 `mysql -h ... -e "select ..."` 取数据
- `mysqldump` 导出远端库到本地 `.sql`
- SSH 到服务器后随手查一行数据
- CI/部署脚本里跑初始化 SQL

若 `which mysql` 为空（未装客户端），本篇补齐。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| 安装方式 | `apt install mysql-client` |
| 安装版本 | **MySQL 8.0.46**（2026-08-12 实测） |
| 实际拉取的包 | `mysql-client-8.0` + `mysql-client-core-8.0`（`mysql-client` 是 metapackage） |
| 命令路径 | `/usr/bin/mysql`、`/usr/bin/mysqldump`、`/usr/bin/mysqladmin` |
| 服务端 | **不在本篇范围**（在 Docker，见 docs/13） |

## 解决方案

### 一键执行（推荐）

```bash
# 进入仓库目录
cd <本仓库目录>

# 一键 apt 安装 + 校验（需 sudo）
sudo bash scripts/install-mysql-client.sh
```

脚本会：

1. `apt update && apt install -y mysql-client`（实际装 MySQL 8.0 客户端三件套）
2. 校验 `which mysql` / `mysql --version` / `mysqldump` / `mysqladmin` 是否就位

### 手工步骤（理解原理用）

```bash
# 1. 安装（mysql-client 是 metapackage，自动带上 8.0 版本的实际包）
sudo apt update
sudo apt install -y mysql-client

# 2. 验证
mysql --version
# 期望：mysql  Ver 8.0.46-0ubuntu0.24.04.3 for Linux on x86_64 ((Ubuntu))

# 3. 连远端（-p 后无参数，回车后输密码，密码不回显）
mysql -h 192.168.1.10 -P 3306 -u root -p business_db
```

## 参数 / 配置详解

### 为什么 `mysql-client` 装出来是 MySQL 8.0，不是 MariaDB

这是个常见误解。Ubuntu 不同版本行为不同：

| Ubuntu 版本 | `apt install mysql-client` 实际装的 | 原因 |
|-------------|-------------------------------------|------|
| 20.04 LTS   | MySQL 8.0 客户端                    | 仓库里有 `mysql-client-8.0` |
| **22.04 LTS** | **MariaDB 客户端**（`mariadb-client`）| Canonical 把默认换成了 MariaDB |
| **24.04 LTS** | **MySQL 8.0 客户端**（`mysql-client-8.0`）| 又换回来了 |

本机 24.04 实测（2026-08-12）：

```
$ apt show mysql-client 2>/dev/null | grep -E "Package|Depends"
Package: mysql-client
Depends: mysql-client-8.0       ← 拉的是 MySQL 8.0，不是 mariadb-client

$ dpkg -l | grep -E "mysql-client|mariadb-client"
ii  mysql-client              8.0.46-0ubuntu0.24.04.3  all   MySQL database client (metapackage...)
ii  mysql-client-8.0          8.0.46-0ubuntu0.24.04.3  amd64 MySQL database client binaries
ii  mysql-client-core-8.0     8.0.46-0ubuntu0.24.04.3  amd64 MySQL database core client binaries
```

> **如果你确实想要 MariaDB 客户端**（例如要连 MariaDB 服务端，用其特有语法）：`sudo apt install mariadb-client`。日常连 MySQL 服务端用本篇的 `mysql-client` 即可，协议兼容。

### 三个包的关系

| 包 | 作用 |
|----|------|
| `mysql-client` | metapackage，只声明依赖，本身不含文件 |
| `mysql-client-8.0` | 提供 `mysql`、`mysqldump`、`mysqladmin` 等命令的 wrapper |
| `mysql-client-core-8.0` | 实际的二进制与库（`/usr/bin/mysql` 真身在这） |

卸载时只 `apt remove mysql-client` 只删 metapackage，命令仍在；要彻底清需带上 `mysql-client-8.0`（见下文「彻底卸载」）。

### 连接参数速查

```bash
mysql -h <主机IP>  -P <端口>  -u <用户>  -p  [数据库名]
      │             │          │         │    └─ 进入后直接 use 这个库
      │             │          │         └─ -p 后留空 = 回车后交互输密码（推荐，不进 history）
      │             │          └─ 用户名
      │             └─ 端口，默认 3306，可省略
      └─ 远端主机，本机可省略或写 127.0.0.1
```

| 场景 | 命令 |
|------|------|
| 连本地 Docker 里的 MySQL | `mysql -h 127.0.0.1 -P 3306 -u root -p` |
| 连远端业务库 | `mysql -h 192.168.1.10 -u biz_user -p business_db` |
| 跑一条 SQL 就走 | `mysql -h 192.168.1.10 -u root -p business_db -e "select count(*) from t_user;"` |
| 导出全库 | `mysqldump -h 192.168.1.10 -u root -p business_db > biz.sql` |
| 只导表结构 | `mysqldump -h 192.168.1.10 -u root -p --no-data business_db > schema.sql` |

## 验证方法

```bash
# 1. 命令就位
which mysql mysqldump mysqladmin
# 期望：三行 /usr/bin/...

# 2. 版本输出
mysql --version
# 期望：mysql  Ver 8.0.46-... for Linux on x86_64 ((Ubuntu))

# 3. 实际连通（用脚本交互式测试，或手敲）
sudo bash scripts/install-mysql-client.sh verify   # 脚本版校验
bash    scripts/install-mysql-client.sh connect    # 交互式连远端
```

## 脚本用法

```bash
bash scripts/install-mysql-client.sh help        # 查看所有子命令

sudo bash scripts/install-mysql-client.sh install  # 仅 apt 安装（需 sudo）
bash    scripts/install-mysql-client.sh verify     # 仅校验
bash    scripts/install-mysql-client.sh connect    # 交互式连接远端测试
sudo bash scripts/install-mysql-client.sh remove   # 卸载
sudo bash scripts/install-mysql-client.sh          # 一键 install → verify（推荐）
```

## 常见问题

**Q1：连远端报错 `ERROR 1045 (28000): Access denied for user 'xxx'`**

用户名/密码/主机三要素之一不对。逐个排查：

```bash
# 1. 确认用户在服务端存在且允许从你的 IP 连
#    （在服务端执行：SELECT user, host FROM mysql.user WHERE user='xxx';）
# 2. host 字段常见值：'%' = 任意主机、'192.168.8.%' = 网段、'localhost' = 仅本机
# 3. -p 后不要直接跟密码（会进 shell history），留空回车输
mysql -h <IP> -u xxx -p
```

**Q2：连远端报错 `ERROR 2059 (HY000): Authentication plugin ... cannot be loaded`**

MySQL 8.0 服务端默认用 `caching_sha2_password` 认证，老客户端（5.7 以前）不认。本篇装的是 **8.0 客户端，原生支持**，正常不会遇到。

如果是从老机器连 8.0 服务端报这个错，两种解法（任选）：

```bash
# 方法 A：客户端升级到 8.0（推荐，本篇已满足）
sudo apt install mysql-client

# 方法 B：把服务端该用户降级回 mysql_native_password
# （在服务端执行，需要 root）
ALTER USER 'xxx'@'%' IDENTIFIED WITH mysql_native_password BY '你的密码';
FLUSH PRIVILEGES;
```

**Q3：`mysqldump` 报 `Warning: A partial dump from a server that has GTIDs`**

远端开了 GTID，dump 默认会带 GTID 信息。导入到非 GTID 实例时加 `--set-gtid-purged=OFF`：

```bash
mysqldump -h <IP> -u root -p --set-gtid-purged=OFF business_db > biz.sql
```

**Q4：怎么把密码固化下来，不用每次输？**

**不建议写进 `~/.my.cnf` 或仓库**——密码会随仓库扩散。两个安全的做法：

```bash
# 方法 A：用 MYSQL_PWD 环境变量（仅当前 shell，不落盘）
export MYSQL_PWD='你的密码'
mysql -h <IP> -u root business_db      # 这次不再提示输密码
unset MYSQL_PWD                         # 用完立即清

# 方法 B：登录后用 mysql_config_editor 加密存（生成 ~/.mylogin.cnf，二进制不可读）
mysql_config_editor set --login-path=remote \
    --host=<IP> --user=root --password   # 提示输密码，加密保存
mysql --login-path=remote business_db    # 之后直接这样连，无需密码
```

**Q5：怎么彻底卸载？**

```bash
# 脚本版（会询问是否一并清 mariadb-client，本机没装则跳过）
sudo bash scripts/install-mysql-client.sh remove

# 手动彻底清（连实际包一起）
sudo apt remove --purge -y mysql-client mysql-client-8.0 mysql-client-core-8.0
sudo apt autoremove -y
```

## 影响范围 / 安全权衡

- 只装**客户端**，不在本机跑 MySQL 服务端，不开放任何端口
- 安装路径 `/usr/bin/mysql` 等，约 62MB 磁盘
- 不改 `/etc/mysql/`、不写 `~/.my.cnf`、不动 `~/.bashrc`（命令已在默认 PATH）
- 不与 Docker 里的 MySQL 服务端（docs/13）冲突——客户端只是个发起连接的工具
- DBeaver（docs/12）自带 JDBC 驱动独立工作，不依赖本客户端；两者并存互不干扰

