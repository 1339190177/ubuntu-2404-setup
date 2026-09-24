# 13 · 开发 · Docker 部署迁移（Windows → Ubuntu）

> 从 Windows 把 Docker Compose 工程迁移到 Ubuntu，含磁盘规划、镜像加速、
> 容器与宿主机权限统一（UID 1000）等完整踩坑记录。重装系统后可按本文复现。

---

## 背景

Windows 上用 Docker Desktop 跑了一套业务（MySQL + Redis + frp + Java 服务），
迁移到 Ubuntu 时遇到几个 Windows 上不存在的坑：

1. **NTFS 分区不能跑容器数据**——MySQL/Redis 数据放在 NTFS（`win_d`）会权限错乱、socket 失效
2. **磁盘规划**——系统盘 `/` 只有 83G，Docker 默认装这里很快满
3. **镜像加速**——国内拉 Docker Hub 直连超时，`openjdk:8-jdk-alpine` 已被官方下架
4. **域名解析**——应用配置里用 `dev.private.com`，Windows 的 hosts 有映射，Ubuntu 没有
5. **UID 不一致**——容器内 mysql/redis 是 UID 999，宿主机 UID 999 是 `dnsmasq`，导致文件属主混乱、宿主机读不了日志

本文记录每个问题的解决方案，重装可复现。

## 目标 / 现状

| 项目 | 内容 |
|------|------|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| Docker | CE 29.7.2（阿里云 apt 源安装）|
| Compose | v5.4.0（docker-compose-plugin）|
| 数据根目录 | `~/docker/data`（ext4，703G 可用）|
| 工程目录 | `~/project/`（ext4）|
| 运行用户 | $USER（uid=1000），容器统一以 `1000:1000` 运行 |
| 迁移来源 | `~/win_d/project/`（NTFS，仅作备份）|
| 部署日期 | 2026-08-10 |

### 磁盘布局回顾

```
nvme1n1p3  140G  /      (ext4)  ← 系统盘，只放系统，不放 Docker 数据
nvme1n1p5  783G  /home  (ext4)  ← Docker 数据 + 工程目录都放这里
nvme0n1p5  315G  win_d  (NTFS)  ← 原始工程备份，不在此跑容器
```

> 关键决策：Docker 数据和工程目录**必须放在 ext4**，不能放 NTFS。

### 服务清单

| 服务 | 镜像 | 端口 | 内存限制 | 数据 |
|------|------|------|----------|------|
| MySQL | `mysql:5.7` | `23306:3306` | 512M | 12 个数据库（含 demo_db 等）|
| Redis | `redis:7.4.6` | `63379:6379` | 128M | DB15: 1270 keys |
| frpc | `gists/frp` | host 网络 | 64M | 内网穿透 4 条代理 |
| demo 业务 | `eclipse-temurin:8-jdk` | `8088`（host）| 768M | Spring Boot 应用 |

## 解决方案

### 第一步：安装 Docker（阿里云源 + 镜像加速）

```bash
# 1. 卸载旧版本（如有）
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# 2. 配置阿里云 Docker apt 源
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

# 3. 安装 Docker CE + Compose 插件
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# 4. 当前用户加入 docker 组（重新登录后免 sudo）
sudo usermod -aG docker $USER
```

### 第二步：配置 data-root + 镜像加速

```bash
# 创建数据目录（放在 /home，703G 空间）
sudo mkdir -p ~/docker/data
sudo chown $USER:$USER ~/docker/data

# 写入 daemon.json
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "~/docker/data",
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

# 重启 Docker 生效
sudo systemctl daemon-reload
sudo systemctl restart docker
```

**验证**：

```bash
sudo docker info | grep -iE 'docker root dir|registry mirrors' -A1
# Docker Root Dir: ~/docker/data
# Registry Mirrors: https://docker.1ms.run/
```

### 第三步：迁移工程到 ext4

```bash
# 从 NTFS 复制到 ext4（cp -a 保留属性）
cp -a ~/win_d/project/base ~/project/base
cp -a ~/win_d/project/service/demo-app ~/project/service/demo-app

# 修正属主（NTFS 上全是 root）
sudo chown -R $USER:$USER ~/project/
```

> MySQL 数据目录有 5.8G，复制约需 1-2 分钟。

### 第四步：配置 hosts 域名解析

应用配置里用了 `dev.private.com`（指向本机）和 `dev.example.com`，Windows 的 hosts 有映射，Ubuntu 需补上：

```bash
# 追加到 /etc/hosts（与 Windows 保持一致）
echo '127.0.0.1 dev.private.com' | sudo tee -a /etc/hosts
echo '172.20.0.4 dev.example.com' | sudo tee -a /etc/hosts

# 验证
getent hosts dev.private.com   # 应输出 127.0.0.1
```

> ⚠️ 如果不配这一步，`dev.private.com` 会被 DNS 解析到公网 IP，MySQL 连接超时。

### 第五步：统一容器与宿主机 UID（权限治理）

这是最关键的一步。详见下方「踩坑记录」第 4 条。

```bash
# 1. 停止服务
cd ~/project/base && sudo docker compose stop

# 2. 删除 mysql.sock 残留符号链接（UID 1000 无法操作它）
sudo rm -f mysql57/data/mysql.sock

# 3. 数据目录属主全部改为 $USER
sudo chown -R $USER:$USER mysql57/data redis/data logs
sudo chown -R $USER:$USER ~/project/service/demo-app/logs

# 4. 修改 compose，给 mysql/redis 加 user 字段（见下方完整配置）
# 5. 重启
sudo docker compose up -d
```

### 第六步：修复内核参数（Redis 告警）

```bash
# 临时生效
sudo sysctl vm.overcommit_memory=1

# 持久化
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

> 不修这个参数，Redis 日志会持续报 WARNING，极端情况影响 RDB 后台保存。

## 最终 compose 配置

关键改动点已用 `← 标注`：

> 内存限制原则：实际占用 × 1.5~2 倍余量。用 `docker stats` 观察实际占用后设定，
> 既能防止内存泄漏失控，又留足业务波动空间。限额过小会被 OOM Killer 杀进程。

```yaml
# ~/project/base/docker-compose.yml
version: '2'

services:
  frpc:
    image: gists/frp
    network_mode: "host"
    restart: always
    mem_limit: 64m                     # ← 实际 18M，留余量
    volumes:
      - ./frp/frpc/frpc.ini:/etc/frpc.ini
      - ./logs/frp:/logs
    command: frpc -c /etc/frpc.ini
    ports:
      - "7003:7000"
    healthcheck:
      test: ["CMD-SHELL", "pgrep -x frpc || exit 1"]   # ← 查进程，不用日志
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: "none"

  mysql:
    image: mysql:5.7
    container_name: mysql5
    restart: always
    user: "1000:1000"                    # ← 统一以宿主机用户运行
    mem_limit: 512m                      # ← 实际 204M
    volumes:
      - "/etc/localtime:/etc/localtime:ro"
      - "./mysql57/my.cnf:/etc/mysql/my.cnf"
      - "./mysql57/data:/var/lib/mysql"
      - "./mysql57/conf.d:/etc/mysql/conf.d"
      - "./logs/mysql:/logs"
      - "mysql-run:/var/run/mysqld"      # ← 非root运行需独立可写的run目录
    environment:
      TZ: Asia/Shanghai
      LANG: en_US.UTF-8
      MYSQL_ROOT_PASSWORD: root   # 示例值，生产必改
    ports:
      - "23306:3306"
    logging:
      driver: "none"

  redis:
    image: redis:7.4.6
    container_name: redis
    restart: always
    user: "1000:1000"                    # ← 统一以宿主机用户运行
    mem_limit: 128m                      # ← 实际 15M
    environment:
      TZ: Asia/Shanghai
    ports:
      - "63379:6379"
    volumes:
      - "./redis/data:/data"
      - "./redis/redis.conf:/etc/redis/redis.conf"
      - "./logs/redis:/logs"
    command: redis-server /etc/redis/redis.conf --appendonly yes
    logging:
      driver: "none"

volumes:                                 # ← mysql-run 命名卷声明
  mysql-run:
```

> demo 业务同理：`mem_limit: 768m`（实际约 538M，含 JVM 堆 350m + 非堆）。
> JVM 堆已通过 `-Xms350m -Xmx350m` 固定，768M 限额给非堆内存和波动留了余量。

## 验证方法

```bash
# 容器状态
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'

# 容器运行 UID（应全部 1000）
for c in mysql5 redis; do
  echo "$c: $(sudo docker exec $c cat /proc/1/status | grep '^Uid:' | awk '{print $2}')"
done

# MySQL 数据
sudo docker exec mysql5 mysql -uroot -proot -e "SHOW DATABASES;"

# Redis 数据
sudo docker exec redis redis-cli -a '密码' --no-auth-warning -n 15 DBSIZE

# 业务接口
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8088/

# 日志（权限治理后，宿主机用户可直接读）
tail -20 ~/project/service/demo-app/logs/demo-service.log
```

## 日常运维命令

```bash
# === 基础依赖（mysql/redis/frpc）===
cd ~/project/base
sudo docker compose ps              # 查看状态
sudo docker compose restart redis   # 重启单个服务
sudo docker compose up -d           # 启动全部
sudo docker compose down            # 停止全部

# === 业务服务（demo-app）===
cd ~/project/service/demo-app
sudo docker compose ps
sudo docker compose restart

# === 查看日志 ===
# 注意：compose 里 logging: none，用 docker logs 看不到
# 要看映射到宿主机的日志文件：
tail -f ~/project/service/demo-app/logs/demo-service.log   # demo 业务
tail -f ~/project/base/logs/redis/redis.log              # Redis
tail -f ~/project/base/logs/mysql/mysql-error.log        # MySQL
tail -f ~/project/base/logs/frp/frpc.log                 # frpc

# === Docker 系统级 ===
sudo docker images                  # 镜像列表
sudo docker system df               # 磁盘占用
sudo docker system prune            # 清理无用镜像/容器（谨慎）
```

## 踩坑记录

### 坑 1：NTFS 分区跑容器必崩

**现象**：MySQL 数据目录放在 NTFS（`win_d`），容器启动后权限错乱、socket 文件失效。

**原因**：NTFS 不支持 Linux 权限模型（uid/gid/权限位），bind mount 后所有文件显示为 root，容器进程无法正确读写。

**解决**：工程和数据**必须迁移到 ext4**（`/home` 分区）。NTFS 上的副本仅作备份。

### 坑 2：openjdk:8-jdk-alpine 镜像已下架

**现象**：`docker pull openjdk:8-jdk-alpine` 报 `manifest unknown`，所有加速器都找不到。

**原因**：Docker Hub 已归档 `openjdk` 官方镜像（OpenJDK 项目已迁移到 Adoptium）。

**解决**：改用官方继任者 `eclipse-temurin:8-jdk`（Spring Boot 官方推荐）：
```yaml
# stock/docker-compose.yml
image: eclipse-temurin:8-jdk   # 原来是 openjdk:8-jdk-alpine
```

### 坑 3：dev.private.com 域名解析到公网

**现象**：demo 业务启动报 `Communications link failure`，MySQL 连接超时。

**原因**：应用配置（`application-private.yml`）里 MySQL/Redis 都连 `dev.private.com`。
Windows 的 hosts 配了 `127.0.0.1 dev.private.com`，Ubuntu 没有，于是被 DNS 解析到公网 IP `203.0.113.30`。

**排查命令**：
```bash
getent hosts dev.private.com   # 看解析到哪个 IP
# 对比 Windows 的 C:\Windows\System32\drivers\etc\hosts
```

**解决**：在 Ubuntu 的 `/etc/hosts` 追加 `127.0.0.1 dev.private.com`。

### 坑 4：容器 UID 999 与宿主机 dnsmasq 冲突（权限治理）

**现象**：MySQL/Redis 容器产生的日志文件，宿主机用户读不了（`Permission denied`）。

**根因**：
```
容器内 mysql/redis 用户 → UID 999
宿主机 UID 999         → dnsmasq 用户（系统自带）
```
容器以 UID 999 写入的文件，在宿主机显示为 `dnsmasq` 属主，当前用户（uid=1000）无权读取 `-rw-r-----` / `-rw-------` 的文件。

**解决方案：统一容器以 UID 1000 运行**

| 步骤 | 命令 | 说明 |
|------|------|------|
| 停服 | `docker compose stop` | 必须先停 |
| 删 sock | `rm -f mysql57/data/mysql.sock` | 残留符号链接，UID 1000 无法操作 |
| 改属主 | `chown -R 1000:1000 mysql57/data redis/data logs` | 数据目录全改 $USER |
| 改 compose | `user: "1000:1000"` | mysql/redis 都加 |
| 挂 run 目录 | `mysql-run:/var/run/mysqld` | MySQL 非 root 运行需独立可写的 socket 目录 |
| 重启 | `docker compose up -d` | |

**为什么 Redis 简单 MySQL 复杂**：
- Redis 官方镜像 entrypoint 支持 `--user`，加 `user` 字段即可
- MySQL 5.7 的 mysqld 启动时需要写 `/var/run/mysqld`（socket/pid），非 root 运行时这个目录不可写，必须额外挂载一个命名卷

### 坑 5：compose 文件 CRLF 换行符导致解析错乱

**现象**：修改 compose 后 `docker compose up` 报 `volumes.redis additional properties not allowed`。

**原因**：从 Windows 复制来的 compose 文件是 CRLF 换行符（`\r\n`），导致 YAML 解析时顶层 `volumes:` 块与服务块错位，`redis:` 被错误归到 `volumes:` 下。

**解决**：
```bash
# 转 LF
sed -i 's/\r$//' docker-compose.yml
# 验证
file docker-compose.yml   # 应显示 "ASCII text"（不含 CRLF）
```

### 坑 6：Redis overcommit_memory 告警

**现象**：Redis 日志持续报 `WARNING Memory overcommit must be enabled!`

**解决**：
```bash
sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

### 坑 7：frpc 健康检查依赖日志字符串，运行久了误报 unhealthy

**现象**：frpc 运行约 20 小时后，`docker ps` 显示 `Up 21 hours (unhealthy)`，但穿透隧道实际正常（经公网反向访问 Redis 能拿到 PONG）。

**根因**：健康检查用 `grep 'start proxy success' /logs/frpc.log` 判断。frpc 自身有日志轮转机制（`log_max_days = 7`），运行一段时间后启动日志被清掉，grep 匹配不到字符串 → `exit 1` → unhealthy。

**验证隧道是否真活**（不是误报）：
```bash
# 经 frps 公网 IP 反向访问本地 Redis，能拿到 PONG 说明隧道正常
docker exec redis redis-cli -h <frps公网IP> -p <穿透端口> -a <密码> PING
```

**解决**：健康检查改用进程存活检测，不依赖日志内容：
```yaml
healthcheck:
  test: ["CMD-SHELL", "pgrep -x frpc || exit 1"]
  interval: 30s
  timeout: 5s
```
> `pgrep -x frpc` 精确匹配进程名。frpc 进程在 = 容器在 = 会自动断线重连。
> 隧道是否真的通，需要时用上面的反向访问命令验证，不靠健康检查。

## 目录结构

```
~/
├── docker/data/              # Docker 数据根（data-root，约 2G）
├── project/
│   ├── base/                 # 基础依赖工程（5.9G）
│   │   ├── docker-compose.yml
│   │   ├── mysql57/
│   │   │   ├── my.cnf
│   │   │   ├── data/         # MySQL 数据（UID 1000）
│   │   │   └── conf.d/
│   │   ├── redis/
│   │   │   ├── redis.conf
│   │   │   └── data/         # Redis AOF/RDB（UID 1000）
│   │   ├── frp/frpc/frpc.ini
│   │   └── logs/             # 各服务日志（UID 1000，可读）
│   └── service/demo-app/        # 业务服务（139M）
│       ├── docker-compose.yml
│       ├── bin/demo-service.jar
│       └── logs/
└── win_d/project/...         # NTFS 原始备份（可删）
```

## 常见问题

**Q1：重装系统后如何快速恢复？**

执行 `scripts/docker-deploy.sh`（见配套脚本），或按本文 6 个步骤依次执行。前提：
- 工程数据已备份（NTFS 副本或外接硬盘）
- 网络可达阿里云 Docker 源

**Q2：frpc 日志报 `connection refused` 是故障吗？**

不是。frpc 把外网请求转发到本地端口，如果本地没起对应服务（如 8000、8800），
就会报 refused。这是预期现象，不影响在用的代理（63379/Redis）。

**Q3：为什么 compose 里都配了 `logging: driver: "none"`？**

业务历史原因：Java 应用日志含特殊字符，曾导致 json-file 驱动解析失败。
日志改为通过 volume 映射到宿主机文件查看。副作用是 `docker logs` 命令读不到日志。

**Q4：MySQL 改 UID 1000 后，那个 `/var/run/mysqld` Warning 还有吗？**

有，但无害：`Warning: Insecure configuration for --pid-file`。
这是 MySQL 检测到 pid 目录全局可读的提示，因容器以非 root 运行所致，不影响功能。

