# 20 · 工具 · TDengine 客户端（taos CLI）

> 一句话：用官方 Docker 镜像提供 TDengine 3.3.4.3 客户端（`taos` 命令行），在宿主机敲 `taos` 即进容器连远端 `db-server.example.com`，无需 dpkg 装 deb。

---

## 背景

示例业务用 TDengine 存储时序数据。**服务端在远程 `db-server.example.com`**（docs/15 已说明这些基础设施都在远端），本地只需要命令行客户端连过去，用于：

- 终端查超级表/子表数据
- 跑 SQL 调试、验证表结构
- `taosdump` 导出远端库

## 为什么用 Docker 镜像，不用 deb 包

TDengine 官方分发机制有几个坑，直接 deb 安装不顺：

| 问题 | 说明 |
|------|------|
| 官方下载中心无稳定直链 | 下载页需交互式选架构/可能登录，脚本无法自动构造 URL |
| GitHub releases 只发源码 | tag `ver-3.3.4.3` 只有源码，**没有 deb 二进制资产**（API 已确认） |
| apt 仓库拉 key 失败 | `repos.taosdata.com/tdengine.key` 在本机 SSL 校验失败；且 apt 装的 `tdengine-tsdb` 是服务端+客户端全套，不符"只要客户端"需求 |

**Docker 方案**绕开所有这些：官方镜像 `tdengine/tdengine:3.3.4.3` 自带 `taos`/`taosdump`/`taosBenchmark`，宿主机只需一个 wrapper 把命令转进容器。已实测可连内网服务器。

## 目标 / 现状（实测 2026-08-12）

| 项目 | 内容 |
|------|------|
| 客户端来源 | Docker 镜像 `tdengine/tdengine:3.3.4.3` |
| 客户端版本 | **3.3.4.3**（与服务端 `tdengine:3.3.4.3` 对齐） |
| 远端服务端 | `db-server.example.com` (10.0.0.78):6030，版本 `3.3.4.3` |
| 宿主机命令 | `~/bin/taos`、`~/bin/taosdump`、`~/bin/taosBenchmark`（wrapper） |
| 命令用法 | 与原生 `taos` 完全一致；不带 `-h` 时默认连 内网服务器 |
| 依赖 | Docker（docs/13 已装） |

## 解决方案

### 一键执行（推荐）

```bash
cd <本仓库目录>

# 一键：拉镜像 + 生成 wrapper + 校验连远端
bash scripts/install-tdengine-client.sh
```

脚本会：

1. `docker pull tdengine/tdengine:3.3.4.3`（已存在则跳过）
2. 生成 `~/bin/taos`、`~/bin/taosdump`、`~/bin/taosBenchmark` wrapper
3. 校验镜像 + wrapper + 实连远端 `select server_version()`

装完直接用：

```bash
taos                              # 进交互式 shell（默认连 内网服务器）
taos -s 'show databases;'         # 执行一条 SQL
taos -h 其它主机 -u root -p        # 连其它 TDengine
```

### wrapper 工作原理

`~/bin/taos` 是个 bash 脚本，把命令转进容器跑，关键做了三件事：

```bash
# 1) 用 --entrypoint 覆盖（避免镜像默认起 taosd 服务端）
docker run --rm -i --network host --entrypoint bash \
    tdengine/tdengine:3.3.4.3 \
    -c "...
        # 2) 修 /etc/taos/taos.cfg 的 fqdn（绕过 FQDN 自检，见下文坑）
        sed -i 's/^fqdn .*/fqdn localhost/' /etc/taos/taos.cfg
        # 3) 跑真正的客户端
        exec /usr/bin/taos \"\$@\"
    "
```

如果命令没带 `-h`，wrapper 自动补 `-h db-server.example.com`（连默认远端）。

## 两个必须处理的坑（实测踩过）

### 坑 1：entrypoint 劫持

官方镜像 entrypoint 是**起 `taosd` 服务端**的，直接 `docker run ... taos` 会被服务端初始化流程劫持，输出一堆 `unavailable`。

**解法**：`--entrypoint bash`（或 `/usr/bin/taos`）覆盖，跳过服务端启动。

### 坑 2：FQDN 自检失败

镜像构建时 `/etc/taos/taos.cfg` 的 `fqdn` 被写死成 `buildkitsandbox`（构建环境的主机名）。客户端启动会反解这个 fqdn 做自检，解析不了就报：

```
failed to init cfg at 1890 since Unable to resolve FQDN
```

**解法**：启动时 `sed` 把 `fqdn` 改成 `localhost`（客户端连远端不依赖本地 fqdn）。

> 这两个坑都已内置在 wrapper 里，开箱即用，无需手动处理。

## 验证方法

```bash
# 1. 命令就位
which taos                          # 期望：~/bin/taos
ls -la ~/bin/taos*                  # 期望：taos / taosdump / taosBenchmark

# 2. 客户端版本
taos --version                      # 期望：taos version: 3.3.4.3 ...

# 3. 连远端（最关键）
taos -u root -ptaosdata -s 'select server_version();'
# 期望输出：
#   server_version() |
#   ===================
#    3.3.4.3          |
#   Query OK, 1 row(s) in set (...)

# 4. 脚本一键校验
bash scripts/install-tdengine-client.sh verify
```

## 脚本用法

```bash
bash scripts/install-tdengine-client.sh help        # 所有子命令

bash scripts/install-tdengine-client.sh             # 一键 pull + wrapper + verify
bash scripts/install-tdengine-client.sh pull        # 仅拉镜像
bash scripts/install-tdengine-client.sh install     # 拉 + 写 wrapper（不验证连通）
bash scripts/install-tdengine-client.sh verify      # 校验
bash scripts/install-tdengine-client.sh connect     # 交互式连远端
bash scripts/install-tdengine-client.sh upgrade     # 切换版本（重拉镜像 + 重生成 wrapper）
bash scripts/install-tdengine-client.sh remove      # 删 wrapper（可选删镜像）

# 装其它版本（须与远端服务端对齐）
TDENGINE_VERSION=3.3.5.0 bash scripts/install-tdengine-client.sh
```

## 连接参数速查

```bash
taos -h <主机>  -P <端口>  -u <用户>  -p  [库名]
     │           │          │         │    └─ 进入后直接 use 这个库
     │           │          │         └─ -p 后留空 = 回车输密码
     │           │          └─ 用户名，默认 root
     │           └─ 端口，默认 6030（TDengine 原生协议，非 6041 REST）
     └─ 远端主机，wrapper 默认 db-server.example.com，可不传
```

| 场景 | 命令 |
|------|------|
| 进交互式 shell | `taos`（默认连 内网服务器） |
| 执行一条 SQL 就走 | `taos -s 'show databases;'` |
| 连其它 TDengine | `taos -h 192.168.1.50 -u root -p` |
| 导出远端库 | `taosdump -o /tmp/dump db_iot`（默认连 内网服务器） |
| 压测 | `taosBenchmark ...` |

> 端口区分：**6030** = TDengine 原生协议（`taos` CLI 走这个）；**6041** = REST API / taosAdapter（JDBC-RESTful 驱动走这个）。命令行用 6030。

## 常见问题

**Q1：`taos: command not found`**

`~/bin` 不在 PATH。检查：

```bash
echo $PATH | tr ':' '\n' | grep -E "HOME/bin|/home/$USER/bin"
# 若空，加到 bashrc：
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

**Q2：报 `Unable to resolve FQDN`**

wrapper 漏了 fqdn 修复。检查 `~/bin/taos` 内容是否含 `sed -i 's/^fqdn`。如缺失，重跑：

```bash
bash scripts/install-tdengine-client.sh install
```

**Q3：连远端报 `some vnode/qnode/mnode(s) out of service`**

这是**远端服务端集群状态问题**（某个 vnode 不健康），不是客户端或网络问题。`select server_version()` 这类只查 mnode 的命令能成功，说明连接本身没问题。联系服务端运维排查 vnode 状态：

```bash
# 只查 mnode（不依赖 vnode），能成功即连接正常
taos -s 'show dnodes;'
taos -s 'select server_version();'
```

**Q4：版本不匹配怎么办**

客户端与服务端**大版本必须一致**（`3.3.x` ↔ `3.3.x`）。查两边：

```bash
taos --version                                       # 本地客户端
taos -s 'select server_version();'                   # 远端服务端
```

升级用脚本：

```bash
bash scripts/install-tdengine-client.sh upgrade
# 输入新版本号，如 3.3.5.0（先确认远端服务端也升级了）
```

**Q5：怎么彻底卸载？**

```bash
bash scripts/install-tdengine-client.sh remove
# 会询问是否删 Docker 镜像（其它容器可能依赖，默认保留）
```

## 影响范围 / 安全权衡

- **不在宿主机装任何系统包**，不污染 `/usr/bin`、`/etc/taos`、`~/.bashrc` 的 PATH
- 只在 `~/bin/` 加 3 个 wrapper 脚本（纯文本，可读可删）
- 拉一个 Docker 镜像（约 200M 磁盘）
- 每次跑 `taos` 启动一个临时容器（`--rm`，跑完即删，不留容器残骸）
- 容器用 `--network host`，直通本机网络（内网服务器 在 `/etc/hosts` 解析为 10.0.0.78）
- 与 DBeaver（docs/12，JDBC-RESTful 走 6041）、MySQL 客户端（docs/19）独立共存

