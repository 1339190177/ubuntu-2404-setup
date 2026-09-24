# 01 · 双系统 · Windows 分区挂载

> 解决 Ubuntu 24.04 + Windows 11 双系统下，读写 Windows NTFS 数据盘时的权限问题。
> 方案：弃用 udisks2 自动挂载，改用 `/etc/fstab` 固定挂载 + `ntfs-3g` 驱动 + 明确的权限参数。

---

## 背景：为什么会出权限问题？

GNOME 文件管理器默认用 `udisks2` 临时挂载 NTFS 分区，特点：

- 用内核 `ntfs3` 驱动 + `acl` 选项，权限由 ACL 控制
- 挂载点带用户名（`/media/$USER/<UUID>`），每次重启可能变化
- 挂载选项不固定，权限行为"时灵时不灵"

**根治思路**：用 `/etc/fstab` 固定挂载，明确指定所有者（uid/gid）和权限掩码（dmask/fmask），开机即按规则挂好。

## 目标分区（本机实测）

| 设备 | UUID | 大小 | 用途 | 挂载点 |
|------|------|------|------|--------|
| `/dev/nvme0n1p5` | `<D盘UUID>` | 315G | 数据盘 D | `~/win_d` (即 `~/win_d`) |
| `/dev/nvme0n1p6` | `<E盘UUID>` | 312G | 数据盘 E | `~/win_e` (即 `~/win_e`) |

> **挂载点说明**：选择挂在主文件夹（`~/win_d`）而不是系统目录（`~/win_d`），是为了在主文件夹直接可见，任何应用的"打开文件"对话框里也能直接访问。文件管理器侧边栏也加了书签（见「访问方式」）。

> Windows 系统盘 `/dev/nvme0n1p4`（Windows 系统盘）**故意不挂载**，避免与 Windows 运行冲突。

## 解决方案

### 一键执行（推荐）

使用本项目脚本 [`scripts/mount-windows.sh`](../scripts/mount-windows.sh)：

```bash
sudo bash scripts/mount-windows.sh install
```

脚本会自动：卸载现有挂载 → 建挂载点 → 测试挂载 + 写测试文件验证可写 → 备份并写 fstab → 用 `mount -a` 二次校验。任一步失败都会中止并提示。

### 手工步骤（理解原理用）

```bash
# 1. 创建挂载点（放在主文件夹，便于应用访问）
mkdir -p ~/win_d ~/win_e

# 2. 卸载 udisks2 自动挂载
sudo umount /dev/nvme0n1p5 /dev/nvme0n1p6 2>/dev/null

# 3. 挂载（用 UUID，uid/gid 设为当前用户）
sudo mount -t ntfs-3g -o uid=1000,gid=1000,dmask=022,fmask=022,big_writes,windows_names,nofail \
  UUID=<D盘UUID> ~/win_d
sudo mount -t ntfs-3g -o uid=1000,gid=1000,dmask=022,fmask=022,big_writes,windows_names,nofail \
  UUID=<E盘UUID> ~/win_e

# 4. 写入 /etc/fstab（开机自动挂载）
# 备份
sudo cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d_%H%M%S)
# 追加（两行）
echo 'UUID=<D盘UUID> ~/win_d ntfs-3g uid=1000,gid=1000,dmask=022,fmask=022,big_writes,windows_names,nofail,defaults 0 0' | sudo tee -a /etc/fstab
echo 'UUID=<E盘UUID> ~/win_e ntfs-3g uid=1000,gid=1000,dmask=022,fmask=022,big_writes,windows_names,nofail,defaults 0 0' | sudo tee -a /etc/fstab

# 5. 校验配置（先卸载再用 mount -a 重挂，能成功才说明 fstab 正确）
sudo umount ~/win_d ~/win_e
sudo mount -a
```

## 挂载参数详解

```
UUID=...    ~/win_d   ntfs-3g   uid=1000,gid=1000,dmask=022,fmask=022,big_writes,windows_names,nofail,defaults   0 0
└──┬──┘     └──┬──┘      └──┬──┘   └────────────────────────────┬────────────────────────────────────────────┘ └┬┘
   │           │             │                                   挂载选项                                         │
   │           │             │                                                                                    │
设备(UUID)   挂载点        文件系统                                                                          dump/pass（备份/检查，都填 0）
```

| 参数 | 含义 | 为什么这么设 |
|------|------|------|
| `UUID=...` | 用文件系统 UUID 标识分区 | 比设备名 `/dev/nvme0n1p5` 稳定——加盘、换接口都不会错挂 |
| `ntfs-3g` | 用户态 FUSE 驱动 | 比 `ntfs3` 内核驱动更成熟稳定，权限模型清晰 |
| `uid=1000,gid=1000` | 所有文件归属当前用户 | **核心**：让 $USER 成为文件所有者，不再有权限报错 |
| `dmask=022` | 目录权限掩码 → 目录为 755 | 目录可进、组/其他可读 |
| `fmask=022` | 文件权限掩码 → 文件为 755 | 文件可读写**可执行**（改自 133：NTFS 上跑 npm/uni-app 等 Linux 构建工具需要执行位，见 Q6） |
| `big_writes` | 允许大块写入 | 提升 1MB+ 大文件写入性能 |
| `windows_names` | 禁止 Windows 不兼容的文件名 | 防止生成 `:`、`?` 等字符，回 Windows 后乱码 |
| `nofail` | 分区不存在时不阻止开机 | 即使某次分区不可用，系统也能正常启动 |
| `defaults` | 启用默认选项（rw、suid、dev、exec 等）| 标准基线 |

> **dmask/fmask 小贴士**：它们是"掩码"，按位取反后才是实际权限。`dmask=022` → 目录权限 `~022 & 777 = 755`；`fmask=022` → 文件权限 `~022 & 777 = 755`。

## 验证方法

```bash
# 1. 看挂载状态
mount | grep -E "win_d|win_e"
# 应显示 type fuseblk，rw（可读写）

# 2. 看空间
df -h ~/win_d ~/win_e

# 3. 实测可写
echo "test" > ~/win_d/.test.txt && cat ~/win_d/.test.txt && rm ~/win_d/.test.txt
```

## 脚本用法

[`scripts/mount-windows.sh`](../scripts/mount-windows.sh) 提供完整生命周期管理：

```bash
# 交互式菜单（推荐）
sudo bash scripts/mount-windows.sh

# 或直接传参
sudo bash scripts/mount-windows.sh install   # 固定挂载 + 写 fstab
sudo bash scripts/mount-windows.sh test      # 临时挂载（不改 fstab）
sudo bash scripts/mount-windows.sh unmount   # 卸载
sudo bash scripts/mount-windows.sh status    # 查看状态
sudo bash scripts/mount-windows.sh restore   # 还原 fstab 备份
```

## 常见问题

### Q1：挂载后变成只读（Read-only file system）

**原因**：Windows 处于"休眠/快速启动"状态，NTFS 被标记为脏。

**解决**：去 Windows 关闭快速启动。以**管理员身份**打开 PowerShell 执行：
```powershell
powercfg /h off
```
然后**完全关机**（不是重启、不是休眠），再启动 Ubuntu 重新挂载。

### Q2：开机时卡在挂载这里进不去系统

**原因**：fstab 写错或分区 UUID 变了。

**解决**：
- 进 Recovery Mode → root shell → 改回 `/etc/fstab`
- 因为加了 `nofail`，正常情况下不会卡死；如果还是卡了，说明 `nofail` 没生效，检查拼写

### Q3：重装 Windows 后 UUID 变了怎么办

**解决**：重新跑一次脚本即可：
```bash
sudo bash scripts/mount-windows.sh restore   # 先清掉旧的 fstab 项
sudo bash scripts/mount-windows.sh install   # 用新 UUID 重新配置
```
脚本会重新探测 UUID。

### Q4：想加挂载点书签到文件管理器侧边栏

进入 `~/win_d` 后按 `Ctrl+D`，或在文件管理器里右键侧边栏 → 添加书签。

### Q5：ntfs-3g 没装

```bash
sudo apt-get install -y ntfs-3g
```

### Q6：NTFS 盘上的项目跑 npm install / 构建工具报 EACCES「权限不够」

**原因**：旧配置 `fmask=133` 剥掉所有文件的执行位（NTFS 上 chmod 无效，权限只由挂载 mask 决定）。npm 依赖带原生二进制的包（esbuild/sass/rollup 等）装不上、跑不了。

**解决**（改 fstab 为 fmask=022）：

```bash
# 已挂载状态下改 fstab 后需卸载重挂（ntfs-3g 不支持 remount 改选项）
sudo umount ~/win_e && sudo mount -a
# 有进程占用卸不下来时：关闭占用进程（IDE/文件管理器），或下次重启自动生效
```

**终局结论**：

- **NTFS 分区不适合放前端/小程序工程**——除了执行位坑（本 Q6），还有第二个坑：**IDE 编译器的文件监听（inotify）在 FUSE/ntfs-3g 上挂死**，微信开发者工具点编译完全无反应（详见 docs/30 Q7）
- 曾经的临时方案 node_modules bind mount（fstab 行）**已退役删除**：工程仓库整体迁移到 `~/项目/`（ext4）后不再需要
- **正确定位**：win_d/win_e 放文档、下载、Windows 侧资料；需要编译/watch/npm 的工程一律放 ext4 本地盘，双系统以 git 同步

## 影响范围

- ✅ **对 Windows 零影响**：只读不写系统盘、只建访问通道、不碰分区表
- ⚠️ **唯一前置条件**：Windows 必须关闭快速启动（见 Q1）
- 📌 **撤销方法**：`sudo bash scripts/mount-windows.sh restore` 或 `sudo rm /etc/fstab.bak.*` 还原后 `sudo umount ~/win_d ~/win_e`

## 访问方式

挂载点在主文件夹，多种方式都能直接访问：

**方式 1：文件管理器（侧边栏）**
左侧栏会出现「Windows-D盘」「Windows-E盘」书签，点一下直接进入。书签配置在 `~/.config/gtk-3.0/bookmarks`。

**方式 2：文件管理器（主文件夹）**
直接打开主文件夹，能看到 `win_d`、`win_e` 两个目录，点进去就是 Windows 盘。

**方式 3：应用「打开文件」对话框**
VSCode、WPS、GIMP 等任何应用的"打开"对话框，默认就在主文件夹，能直接看到并进入 `win_d`、`win_e`。

**方式 4：命令行**
```bash
cd ~/win_d      # 进入 D 盘
cd ~/win_e      # 进入 E 盘
```

