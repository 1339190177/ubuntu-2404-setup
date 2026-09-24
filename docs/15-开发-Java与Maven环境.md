# 15 · 开发 · Java 17 与 Maven 环境

> 为 RuoYi-Vue-Plus 系列 Spring Boot 项目（示例业务后端）准备本地开发环境：apt 装 OpenJDK 17 + Maven，配阿里云镜像加速，动态 JAVA_HOME 升级免改。

---

## 背景：为什么是这两样？

示例业务后端 `demo-business-server` 是基于 **RuoYi-Vue-Plus 5.2.3** 的多模块 Maven 项目，`pom.xml` 锁定：

| 锁定项 | 值 | 含义 |
|--------|-----|------|
| `java.version` | `17` | 必须用 JDK 17 编译运行 |
| `spring-boot.version` | `3.2.11` | Spring Boot 3.x 要求 JDK 17+ |
| `<packaging>pom</packaging>` + `<modules>` | - | 多模块 Maven 聚合工程 |

本机最初是干净的：有 Node 18、Git、Docker，但 **没有 Java、没有 Maven**，项目根本无法编译。这两样是 Java 后端开发的最低门槛。

> **关于 MySQL / Redis / RocketMQ / EMQX / TDengine**：这些基础设施都部署在远程 `db-server.example.com`，本地代码通过 YAML 配置连接即可，**不需要本地安装**。只有当你要断网调试或压测时才需要本地起一套，那是另外的事。

## 目标 / 现状

本机实测（2026-08-10）：

| 组件 | 安装方式 | 版本 | 路径 |
|------|---------|------|------|
| OpenJDK | `apt` | `17.0.19+10-1~24.04.2` | `/usr/lib/jvm/java-17-openjdk-amd64` |
| Maven | `apt` | `3.8.7` | `/usr/share/maven` |
| 本地仓库 | 默认 | - | `~/.m2/repository` |
| 用户配置 | 手写 | - | `~/.m2/settings.xml`（阿里云镜像） |

选 apt 的理由：系统包管理统一、卸载干净、与 Ubuntu 24.04 体系一致；项目没强制 Maven 版本，apt 的 3.8.7 完全够用。

## 解决方案

### 一键执行（推荐）

配套脚本 `scripts/install-java-maven.sh` 把四步全部串起来：

```bash
cd <本仓库目录>
sudo bash scripts/install-java-maven.sh           # 一键全套：装包→镜像→JAVA_HOME→编译验证
sudo bash scripts/install-java-maven.sh install   # 也可以分步执行
```

### 手工步骤（理解原理用）

#### 1. apt 安装 OpenJDK 17 与 Maven

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk maven
```

验证：

```bash
java -version
# openjdk version "17.0.19" 2026-04-21

mvn -version
# Apache Maven 3.8.7
# Maven home: /usr/share/maven
# Java version: 17.0.19, vendor: Ubuntu, runtime: /usr/lib/jvm/java-17-openjdk-amd64
```

`mvn -version` 末尾的 `Java version` 必须是 17，否则后面编译会报 `invalid target release: 17`。

#### 2. 配置阿里云 Maven 镜像

这个项目依赖极多（Spring Boot / Flowable 7.0.1 / MyBatis-Plus / AWS SDK 2.28 / Sa-Token / Redisson ……），走默认 Maven Central 拉取又慢又容易超时。把 central 镜像到阿里云：

```bash
mkdir -p ~/.m2
nano ~/.m2/settings.xml
```

写入（完整内容也可由脚本一键生成）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <localRepository>${user.home}/.m2/repository</localRepository>
  <mirrors>
    <!-- 阿里云公共仓库：镜像 central -->
    <mirror>
      <id>aliyun-public</id>
      <name>Aliyun Public</name>
      <url>https://maven.aliyun.com/repository/public</url>
      <mirrorOf>central</mirrorOf>
    </mirror>
    <!-- 阿里云 central（含 snapshots），作为兜底镜像所有仓库 -->
    <mirror>
      <id>aliyun-central</id>
      <name>Aliyun Central</name>
      <url>https://maven.aliyun.com/repository/central</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
    <!-- 其余按需：spring / spring-plugin / gradle-plugin / google -->
  </mirrors>
  <profiles>
    <profile>
      <id>jdk-17</id>
      <activation>
        <activeByDefault>true</activeByDefault>
        <jdk>17</jdk>
      </activation>
      <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <maven.compiler.compilerVersion>17</maven.compiler.compilerVersion>
      </properties>
    </profile>
  </profiles>
</settings>
```

#### 3. 配置动态 JAVA_HOME

apt 装的 OpenJDK **不会**自动设置 `JAVA_HOME`，但很多工具（Tomcat、IDEA 命令行、某些 Maven 插件）依赖它。在 `~/.bashrc` 末尾追加：

```bash
# Java / Maven 环境（OpenJDK 17 via apt）
# 动态解析 JAVA_HOME：apt 装的 java 是 /usr/lib/jvm/java-17-openjdk-amd64/bin/java
# 用 readlink 反解出真实路径，升级 JDK 小版本后自动跟随，无需手改
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH=$JAVA_HOME/bin:$PATH
```

让新配置在当前终端立即生效：

```bash
source ~/.bashrc
echo $JAVA_HOME
# /usr/lib/jvm/java-17-openjdk-amd64
```

#### 4. 编译验证项目

```bash
cd <你的项目目录>/demo-business-server

# 只编译不打包不跑测试，用项目默认 profile remote
mvn clean compile -DskipTests -P dev
```

首次会下载几百个依赖，约 5–15 分钟（取决于网速）。看到末尾 `BUILD SUCCESS` 即环境就绪。

## 参数 / 配置详解

### 为什么 JAVA_HOME 用 `readlink -f` 动态解析？

apt 装的 `java` 实际是经 `update-alternatives` 软链过去的：

```
/usr/bin/java → /etc/alternatives/java → /usr/lib/jvm/java-17-openjdk-amd64/bin/java
```

- `which java` → `/usr/bin/java`
- `readlink -f /usr/bin/java` → 跟完所有软链，得到真实文件 `/usr/lib/jvm/java-17-openjdk-amd64/bin/java`
- 套两层 `dirname` → `/usr/lib/jvm/java-17-openjdk-amd64`（正是 `JAVA_HOME`）

好处：将来 `apt upgrade openjdk-17-jdk` 升级到 17.0.20 之类的小版本，alternatives 指针会跟着变，这个表达式自动跟随，**永远不用手改 `.bashrc`**。

> ❌ 反面写法：`export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` 硬编码。能用，但升级路径变了就失效。

### 阿里云镜像 `mirrorOf` 怎么选？

| 写法 | 含义 | 适用 |
|------|------|------|
| `<mirrorOf>central</mirrorOf>` | 只镜像默认中央仓库 | 最安全，不动其他仓库 |
| `<mirrorOf>*</mirrorOf>` | 镜像**所有**仓库 | 最激进，包括第三方私服也走阿里云 |
| `<mirrorOf>*,!my-private</mirrorOf>` | 镜像所有，但排除指定仓库 | 既有私服又想加速中央仓库时 |

本配置同时给了 `central`（精确）和 `*`（兜底）两个 mirror，Maven 会按顺序匹配。日常开发这样最省心；如果将来接了公司私服，记得改成 `*,!company-nexus`。

### Maven Profile：`dev` / `remote` / `cf`

项目的 `pom.xml` 定义了三个 profile，对应三套环境配置：

| Profile | 用途 | 默认？ |
|---------|------|--------|
| `dev` | 本地开发 | |
| `remote` | 远程服务器环境（开发主力） | ✅ `activeByDefault` |
| `cf` | 生产/正式环境 | |

日常开发直接 `mvn compile` 即可（默认走 remote）；要显式指定用 `-P dev`。

## 验证方法

环境装好后的三连验证（任开一个新终端执行）：

```bash
# 1. Java 版本 = 17
java -version          # → openjdk version "17.0.x"

# 2. Maven 能跑且认得 17
mvn -version           # → Apache Maven 3.8.7 / Java version: 17.0.x

# 3. JAVA_HOME 已设置
echo $JAVA_HOME        # → /usr/lib/jvm/java-17-openjdk-amd64
```

项目级终极验证：

```bash
cd <你的项目目录>/demo-business-server
mvn clean compile -DskipTests -P dev
# 末尾出现 BUILD SUCCESS = 全部模块编译通过
```

## 脚本用法

```bash
# 一键全套（装包 → 镜像 → JAVA_HOME → 编译验证），需要 sudo
sudo bash scripts/install-java-maven.sh

# 分步执行
sudo bash scripts/install-java-maven.sh install     # 只装包
bash    scripts/install-java-maven.sh mirror        # 只重写镜像（不需 sudo）
bash    scripts/install-java-maven.sh java_home     # 只配 JAVA_HOME
bash    scripts/install-java-maven.sh verify        # 只编译验证

# 帮助
bash scripts/install-java-maven.sh help
```

> 脚本写入 `~/.m2/settings.xml` 和修改 `~/.bashrc` 时，会自动用 `$SUDO_USER` 还原真实用户，避免 sudo 把家目录文件 owner 改成 root。

## 常见问题

### Q1：`mvn -version` 报 `Java version: 1.8.0_xxx`，不是 17？

系统里有多个 JDK，`update-alternatives` 指向了老的。重新选：

```bash
sudo update-alternatives --config java     # 选 java-17-openjdk-amd64
sudo update-alternatives --config javac    # 同样选 17
```

再 `source ~/.bashrc` 让动态 JAVA_HOME 重算。

### Q2：编译报 `invalid target release: 17` / `unsupported class file version`？

Maven 在用 JDK 8 跑。检查：

```bash
echo $JAVA_HOME            # 应是 .../java-17-openjdk-amd64
mvn -version | grep Java   # 应是 17
```

不对就走 Q1 的 alternatives 切换，或临时 `export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` 再编译。

### Q3：依赖拉取还是慢 / 超时？

确认镜像真的生效：

```bash
mvn help:effective-settings | grep -A2 aliyun
```

看到 `aliyun` 域名说明镜像已激活。如果办公网络屏蔽了阿里云，换华为云：`https://mirrors.huaweicloud.com/repository/maven/`。

### Q4：IntelliJ IDEA 里 Maven 还是用的内嵌版本 / 报错？

IDEA 默认用自己的 Bundled Maven 和 Bundled JDK。手动指定：

- `File → Settings → Build → Build Tools → Maven` → `Maven home path` 改成 `/usr/share/maven`
- `User settings file` 勾选 Override，指向 `~/.m2/settings.xml`
- `File → Project Structure → SDK` 添加 `/usr/lib/jvm/java-17-openjdk-amd64` 为项目 SDK

### Q5：`source ~/.bashrc` 后 `JAVA_HOME` 还是空？

`~/.bashrc` 顶部有 `case $- in *i*) ;; *) return;; esac`，**非交互 shell 会提前 return**，后面的 export 不执行。两种验证方式：

```bash
# 方式 1：模拟交互登录 shell
bash -lic 'echo $JAVA_HOME'

# 方式 2：直接新开一个终端窗口（推荐）
```

日常使用都是新开终端，不影响。

## 影响范围 / 安全权衡

- **系统级**：`apt install openjdk-17-jdk maven` 是标准 Ubuntu 包，来源可信，卸载用 `sudo apt remove --purge openjdk-17-jdk maven`。
- **用户级**：`~/.m2/settings.xml` 是新建文件，删掉即恢复 Maven 默认中央源；`~/.bashrc` 追加的两行可手动删除，不影响系统。
- **网络**：镜像走 `maven.aliyun.com`（HTTPS），依赖下载流量较大（一个 RuoYi-Vue-Plus 全量项目本地仓库约 800MB–1.2GB）。
- **无外部服务**：本地只装编译工具链，不监听任何端口，不连数据库；实际业务运行所需的 MySQL/Redis 等仍在远程服务器。

