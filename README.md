# ubuntu-setup · Ubuntu 24.04 环境配置手册

> 装完 Ubuntu 24.04 之后要做的一切：**可复现的脚本 + 中文踩坑文档**。
> 每篇文档都来自真机实测，记录参数为什么这么选、坑在哪里、怎么验证。
> 重装系统/换机后，按索引逐项恢复即可。

## 适用环境

- Ubuntu 24.04 LTS（GNOME 桌面 / Wayland，x86_64）
- 所有脚本在真机（双系统、AMD 双显卡环境）实测通过
- 不适用于服务器版/其他发行版（部分脚本可参考改造）

## 🚀 快速开始（人类读者）

1. 在下方「📚 文档索引」按主题找到你要的配置
2. 打开对应文档，按「一键执行」或「手工步骤」操作
3. 脚本统一约定：`bash scripts/install-xxx.sh` 无参数进交互菜单，`help` 看用法；需要 sudo 的脚本在文档里标注

```bash
git clone <本仓库地址>
cd ubuntu-setup
bash scripts/install-java-maven.sh help   # 先看用法再跑
```

## 🤖 给 AI agent 的话

- 工作规约见 [AGENTS.md](AGENTS.md)：文档编号规则、脚本风格、提交边界——按它干活
- 查经验：先按索引找文档，每篇都有「常见问题」章节，**先查再试错**
- 文档/脚本中的服务器地址、账号、密码均为**示例占位**（`db-server.example.com`、`198.51.100.x` 等 RFC 5737 文档段），使用前替换为你自己的
- 踩到新坑修好后，欢迎按 AGENTS.md 规约补文档

## 📚 文档索引

| # | 文档 | 一句话主题 |
|---|------|-----------|
| 01 | [双系统-Windows分区挂载](docs/01-双系统-Windows分区挂载.md) | ntfs-3g + fstab 挂载 Windows 数据盘，权限一劳永逸 |
| 02 | [系统-sudo免密配置](docs/02-系统-sudo免密配置.md) | sudoers.d 单用户免密，含安全权衡 |
| 03 | [系统-隐藏危险分区](docs/03-系统-隐藏危险分区.md) | 隐藏 Windows 系统盘，防误操作 |
| 04 | [工具-aria2下载神器](docs/04-工具-aria2下载神器.md) | 多线程下载 + 常用命令速查 |
| 05 | [工具-浏览器与默认设置](docs/05-工具-浏览器与默认设置.md) | Edge 官方 deb 安装、默认浏览器（apm 版踩坑） |
| 06 | [硬件-AMD显卡监控](docs/06-硬件-AMD显卡监控.md) | rocm-smi + nvtop 监控 AMD 显卡 |
| 07 | [桌面-快捷启动器](docs/07-桌面-快捷启动器.md) | .desktop 桌面快捷方式模板 |
| 08 | [工具-视频播放VLC](docs/08-工具-视频播放VLC.md) | 装 VLC 解决视频打不开，设默认播放器 |
| 09 | [工具-RustDesk远程桌面](docs/09-工具-RustDesk远程桌面.md) | 开源远程桌面，Wayland 友好 |
| 10 | [输入法-IBus配置](docs/10-输入法-IBus配置.md) | IBus libpinyin，含 fcitx5 折腾教训 |
| 11 | [网络-OpenVPN](docs/11-网络-OpenVPN.md) | NetworkManager 图形 + 命令行双方案，NM 导入两坑 |
| 12 | [工具-DBeaver数据库管理](docs/12-工具-DBeaver数据库管理.md) | 免费 MySQL 可视化，含 Navicat 连接迁移 |
| 13 | [开发-Docker部署迁移](docs/13-开发-Docker部署迁移.md) | Windows→Ubuntu 迁移，磁盘规划+镜像加速+UID 统一，6 个踩坑 |
| 14 | [工具-远程SSH客户端](docs/14-工具-远程SSH客户端.md) | Tabby 替代 Xshell |
| 15 | [开发-Java与Maven环境](docs/15-开发-Java与Maven环境.md) | OpenJDK 17 + Maven，阿里云镜像，动态 JAVA_HOME |
| 16 | [网络-静态IP配置](docs/16-网络-静态IP配置.md) | nmcli 固定网卡 IP，依赖 IP 的配置不再失效 |
| 17 | [工具-ApiPost接口调试](docs/17-工具-ApiPost接口调试.md) | 官方 deb 安装 ApiPost，接口调试/Mock/压测 |
| 18 | [系统-默认文本编辑器](docs/18-系统-默认文本编辑器.md) | 13 种文本 MIME 默认改 VS Code |
| 19 | [工具-MySQL客户端](docs/19-工具-MySQL客户端.md) | apt 装 MySQL 8.0 客户端直连远端库 |
| 20 | [工具-TDengine客户端](docs/20-工具-TDengine客户端.md) | Docker 镜像 + wrapper 提供 taos CLI，绕过 entrypoint/fqdn 两坑 |
| 21 | [工具-B站视频下载](docs/21-工具-B站视频下载.md) | BBDown 装进 ~/bin，扫码登录，收藏夹批量 |
| 22 | [工具-终端zsh增强](docs/22-工具-终端zsh增强.md) | 插件全家桶 + fzf + starship，可整体回滚 |
| 23 | [工具-网文阅读器](docs/23-工具-网文阅读器.md) | 阅读3服务器版 Docker 自托管，免费无广告 |
| 24 | [工具-RustDesk自建中继](docs/24-工具-RustDesk自建中继.md) | hbbs/hbbr 本机 Docker + frp 穿透 |
| 25 | [工具-p7zip压缩解压](docs/25-工具-p7zip压缩解压.md) | apt 过渡包 → 官方 7-Zip，7z 命令速查 |
| 26 | [工具-Google-Antigravity](docs/26-工具-Google-Antigravity.md) | tar.gz 用户级安装，无需 sudo，代理兜底下载 |
| 27 | [工具-腾讯会议](docs/27-工具-腾讯会议.md) | 官方 deb，Next.js 动态页直链抓取法 |
| 28 | [工具-图片编辑GIMP](docs/28-工具-图片编辑GIMP.md) | apt 装 GIMP，Script-Fu 批处理坑 |
| 29 | [工具-一键水印](docs/29-工具-一键水印.md) | Nautilus 右键加水印 + watermark CLI |
| 30 | [工具-微信开发者工具](docs/30-工具-微信开发者工具.md) | 社区移植版 deb（原生 Electron 非 Wine） |
| 31 | [桌面-Windows化布局](docs/31-桌面-Windows化布局.md) | 底部常驻 Dock + 单击最小化，可逆 |
| 32 | [工具-飞书](docs/32-工具-飞书.md) | 官方 deb，接口取签名直链 + md5 校验，升级免改脚本 |
| 33 | [工具-MQTTX桌面客户端](docs/33-工具-MQTTX桌面客户端.md) | EMQ 国内 CDN 直链装 MQTTX，连远端 EMQX |
| 34 | [工具-Worktile](docs/34-工具-Worktile.md) | 官方无 Linux 客户端，Chrome --app 封装网页版 |
| 35 | [工具-安卓模拟器](docs/35-工具-安卓模拟器.md) | 官方 AVD + KVM + ARM 翻译层跑 ARM-only APK |

> 新增文档请遵循 [docs/99-文档编写规范.md](docs/99-文档编写规范.md)（编号连续递增，先 `ls docs/` 确认下一个号）

## 🛠️ 新增一项配置的工作流

1. **写脚本** → `scripts/`，英文短横线命名
2. **写文档** → `docs/`，编号 + 中文标题
3. **改索引** → 本 README「文档索引」表
4. **提交** → `feat: 新增 XXX 配置`

## ⚠️ 重要提醒

- 修改系统配置前脚本会自动备份，但重要数据请自行额外备份
- 双系统请关闭 Windows 快速启动，否则 NTFS 只读（docs/01）
- 免密 sudo 仅适合个人桌面机（docs/02）

## License

[MIT](LICENSE)
