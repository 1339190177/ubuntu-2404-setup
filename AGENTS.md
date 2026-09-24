# AGENTS.md — AI 在本仓库的工作规约

本仓库是 Ubuntu 24.04 环境配置的脚本 + 文档归档，人类与 AI agent 双读者。
agent 在本仓库工作时遵守以下规约。

## 读者分工（为什么有两份入口文件）

- **人类读者**从 [README.md](README.md) 进入：项目定位、快速开始、文档索引
- **AI agent**以本文件为规约入口：怎么找文档、怎么加文档、脚本风格、提交边界
- 内容**单树共享**（同一份 docs/ 服务两类读者），刻意不做两套文档——双内容树必然失同步。
  人类关心"哪篇讲我的问题"（索引+常见问题章节），agent 额外关心"改动要守什么规矩"（本文件）

## 文档规范（强约束，docs/99 已定义）

- **文档命名**：`docs/序号-主题-标题.md`，序号两位、唯一、递增
  → **分配新序号前必须 `ls docs/ | grep -oE "^[0-9]+" | sort -n | tail`**，
  不要只看 git status（已提交文档可能不在工作区差异里，导致序号误判）。
  发布集编号保持连续；如发现断号，先查是否误删文档，而不是补号。
- **新增文档必做 3 件事**（缺一不可）：
  1. 写 `docs/NN-主题-标题.md`（按 docs/99 章节结构：背景/目标现状/一键执行/手工步骤/参数详解/验证方法/常见问题/影响范围/变更记录）
  2. 写配套 `scripts/xxx.sh`
  3. 更新 README.md「📚 文档索引」表（追加一行，不动既有行）

## 脚本风格统一

参考 `scripts/install-java-maven.sh` / `scripts/install-mysql-client.sh`：

- shebang + `set -u` + 颜色函数 `info/ok/warn/err` + 子命令分发 + `help`
- 涉及 sudo 的脚本用 `need_root` 校验 + `REAL_USER`/`REAL_HOME`（sudo 下还原真实用户）
- 卸载/回滚路径必须提供（`remove` 子命令或等效）

## git 提交边界

- 一个需求 = 一个独立 commit；`feat: ` / `fix: ` / `docs: ` 前缀
- 不裹挟无关文件

## 安全纪律

- **文档与脚本中禁止出现真实凭据/内网地址/个人路径**：服务器用 `*.example.com`，
  IP 用 RFC 5737 文档段（`192.0.2.x`/`198.51.100.x`/`203.0.113.x`）或通用私网段，
  用户路径用 `~`/`$USER`，账号密码一律 `<placeholder>`
- 本仓库历史经过净化，**不要尝试恢复或询问真实值**

## 通用经验（实测提炼）

- Ubuntu 24.04 的 `mysql-client` 装 MySQL 8.0（不是 MariaDB）；22.04 才是 MariaDB——按发行版实测，别预设
- 官方无稳定直链的客户端（如 TDengine）用 **Docker 镜像 + ~/bin wrapper** 方案，宿主机零污染；
  TDengine 镜像两坑：entrypoint 是服务端（须 `--entrypoint bash` 覆盖）、taos.cfg 的 fqdn 写死（启动时 sed）
- 判断装法先查官方分发方式（apt/deb/直链/仅源码），别预设
