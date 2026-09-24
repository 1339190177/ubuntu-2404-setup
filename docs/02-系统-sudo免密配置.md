# 02 · 系统 · sudo 免密配置

> 给当前用户（$USER）配置 sudo 免密，免去频繁输入密码。
> 方案：在 `/etc/sudoers.d/` 下新增独立文件，**不改动主 `/etc/sudoers`**。

---

## 背景：为什么要免密？

Linux 出于安全考虑，每次 sudo 都要求密码。但在**个人桌面机、单用户**场景下：

- 反复输密码影响体验
- 跑自动化脚本（如本项目的 `mount-windows.sh`）会被密码中断
- 风险可控（详见下方「安全权衡」）

## 解决方案

### 一行命令搞定

```bash
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER-nopasswd
sudo chmod 440 /etc/sudoers.d/$USER-nopasswd
```

### 验证生效

```bash
# 1. 测试免密（成功无输出，失败会提示要密码）
sudo -n true && echo "✅ 免密生效" || echo "❌ 仍需密码"

# 2. 校验整个 sudoers 语法（关键！语法错会让 sudo 彻底报废）
sudo visudo -c
# 应看到所有文件都「解析正确」

# 3. 看文件权限
ls -l /etc/sudoers.d/$USER-nopasswd
# 应为 -r--r----- 1 root root
```

## 命令详解

```
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER-nopasswd
       └──┬──┘ └─┬─┘ └─┬─┘ └────┬─────┘   └────────────┬────────────┘
          │      │     │         │                       │
        用户名  主机  可切换为  选项：NOPASSWD 免密码   写入独立文件（不动主配置）
```

| 字段 | 含义 |
|------|------|
| `$USER` | 规则适用的用户名 |
| `ALL=` | 适用于所有主机 |
| `(ALL)` | 可切换到任何用户 |
| `NOPASSWD:` | 后面的命令免密 |
| `ALL` | 所有命令都免密 |
| `tee` 而非 `>` | `>` 重定向在 sudo 时不生效（重定向由 shell 执行，没提权），用 `tee` 才能写入 root 拥有的目录 |
| `chmod 440` | sudoers 文件必须的权限，否则 sudo 拒绝加载 |

## 为什么这个方案好

1. **不动主 `/etc/sudoers`**：主文件是系统核心，改坏了 sudo 直接报废。独立文件出问题最多被忽略。
2. **可撤销**：删一个文件就恢复原状（见下）。
3. **粒度可控**：只针对 $USER，不影响其他用户。
4. **语法保护**：sudo 加载时若语法错会直接忽略该文件，不会让 sudo 崩溃。

## 撤销方法

```bash
sudo rm /etc/sudoers.d/$USER-nopasswd
```
删除后立即恢复要密码。

## 安全权衡 ⚠️

### 适用场景 ✅

- 个人桌面电脑
- 单用户使用
- 不对外提供服务（非服务器）
- 防火墙开启、不随便装来路不明软件

### 不适用场景 ❌

- 公开服务器
- 多人共用机器
- 存放高敏感数据（如密钥、密码库）
- 经常运行不可信代码

### 免密后的真实风险

免密 = 任何能以你身份跑命令的东西，都能直接拿到 root。具体：

- 恶意网页脚本（理论上可通过浏览器漏洞）→ root
- 来路不明的软件包 → root
- 被攻陷的 snap/flatpak 应用 → root

**缓解措施**：
- 浏览器保持更新（Ubuntu 的 Firefox 通过 snap 自动更新）
- 只从可信来源装软件（apt 官方源、snap 官方商店）
- 不跑来路不明的脚本（执行前看一眼内容）
- 启用防火墙：`sudo ufw enable`

## 进阶：只对特定命令免密（更安全）

如果不想全部免密，只让特定命令免密（例如只让 `mount-windows.sh` 免密），可以写：

```
$USER ALL=(ALL) NOPASSWD: <本仓库目录>/scripts/mount-windows.sh
```

这样只有这个脚本免密，其他 sudo 操作仍然要密码。一般选"全部免密"即可，如有更高安全需求可改成这种。

## 常见问题

### Q1：执行命令后 sudo 用不了了（提示语法错误）

**说明**：可能写入了非法字符（如多余空格、引号）。

**解决**：进 Recovery Mode → root shell → 删除该文件：
```bash
rm /etc/sudoers.d/$USER-nopasswd
```
然后正常重启。

### Q2：改完没生效，还是要密码

**排查**：
```bash
ls -l /etc/sudoers.d/$USER-nopasswd   # 权限必须是 440
sudo visudo -c                            # 看是否「解析正确」
```
权限不是 440 或语法错，sudo 会忽略该文件。

### Q3：能不能给整个 sudo 组免密？

可以，但**不推荐**——影响范围扩大到所有管理员账户。如确需：
```bash
echo "%sudo ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/sudo-nopasswd
sudo chmod 440 /etc/sudoers.d/sudo-nopasswd
```
（`%sudo` 表示 sudo 用户组）

