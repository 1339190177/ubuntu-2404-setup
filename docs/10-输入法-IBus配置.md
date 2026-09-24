# 10 · 输入法 · IBus libpinyin（GNOME 原生）

> 最终方案：IBus + libpinyin。GNOME 原生支持，X11/Wayland 都稳定。
> 本文含 fcitx5 折腾历程的完整教训（避免重复踩坑）。

---

## 当前方案：IBus + libpinyin

| 项目 | 内容 |
|------|------|
| 输入法框架 | **IBus**（GNOME 原生）|
| 中文引擎 | **libpinyin**（智能拼音）|
| 切换键 | Super+Space（GNOME 默认）|
| 适合 | X11 + Wayland 都稳定 |
| 配置位置 | `~/.xprofile` + `im-config ibus` + gsettings |

## 为什么放弃 fcitx5 用 IBus（重要教训）

### 背景

最初用 IBus（系统自带），后为解决微信打不出字**切到 fcitx5**。在 **Wayland** 下 fcitx5 工作正常。但**为解决 RustDesk 被控切到 X11** 后，fcitx5 出现一系列问题。

### fcitx5 在 X11 下的问题（折腾了 2 小时）

| 问题 | 修复尝试 | 结果 |
|------|------------|------|
| 失活打不出字 | 重启 fcitx5 | 治标，反复失活 |
| 怀疑 inotify 耗尽 | 提高 watch 到 524288 | 不是根因 |
| 怀疑锁屏脚本干扰 | 加 fcitx5-watch 监听 | 雪上加霜 |
| 怀疑缺 ~/.xprofile | 创建 xprofile | 和 environment.d 冲突 |
| 怀疑 IBus 抢占 | 杀 IBus + 禁 autostart | 破坏 GNOME 平衡 |

**越修越乱**——每加一层"修复"就多一个干扰源。

### 根本原因

fcitx5 在 X11 下不稳定是已知问题（社区报告多），**不是配置问题**：
- fcitx5 设计倾向 Wayland
- X11 下 DBus frontend + XIM frontend 切换容易出问题
- GNOME 对 IBus 有原生集成，对 fcitx5 没有

### 最终决策

**放弃 fcitx5，换回 IBus + libpinyin**（GNOME 原生，最稳）。X11 下微信等 QT 应用 IBus 能正常工作。

## IBus 完整配置（重装可复用）

### 1. 安装

```bash
# libpinyin 引擎（系统自带 ibus）
sudo apt install -y ibus ibus-libpinyin
```

### 2. 设为默认输入法

```bash
im-config -n ibus
```

### 3. 创建 ~/.xprofile（X11 会话启动时读取）

```bash
cat > ~/.xprofile <<'EOF'
# 输入法环境变量（X11 会话启动时读取）
# 用 IBus（GNOME 原生，X11/Wayland 都稳定）
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export SDL_IM_MODULE=ibus
EOF
```

### 4. 配置 GNOME input-sources

```bash
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'cn'), ('ibus', 'libpinyin')]"
```

### 5. 注销重新登录（让配置生效）

**必须做这一步**——当前会话环境变量无法实时切换。

## 使用方法

### 切换中英文

- **Super+Space**（Win+Space）——GNOME 默认切换键
- 也可在 GNOME 设置 → 键盘 → 查看和自定义快捷键

### IBus 配置（图形界面）

```bash
ibus-setup    # 打开 IBus 偏好设置
```

能调：候选词数、皮肤、快捷键、输入法顺序等。

### 添加其他输入法

```bash
ibus-setup    # 输入法标签页 → 添加 → 选五笔/双拼/其他
```

## 智能调优（越用越顺手）

> 2026-08-19 决策：决策：**不切 fcitx5**（X11 下有过失败史，见下文），
> 在 IBus 上调优。云源枚举实测确认：`cloud-input-source` **0 = Baidu（国内可用）**，
> 1 = Google 国际（上游 `enum CloudInputSource{ BAIDU=0, GOOGLE }`）。

### 调优项（`scripts/tune-ibus-libpinyin.sh apply` 一键固化）

| gsettings 键（schema：`com.github.libpinyin.ibus-libpinyin.libpinyin`） | 默认 | 调成 | 说明 |
|---|---|---|---|
| `lookup-table-page-size` | 5 | **9** | 每页候选 5→9，减少翻页 |
| `suggestion-candidate` | false | **false（强制）** | 联想：上屏后弹"下一个词推荐"框，必须 Esc/选词才能继续，打断输入流。试用后关闭 |
| `enable-cloud-input` | false | **false（强制）** | 云输入实测难用：停键 ~0.6s 后异步插入云候选、列表重排，快打快选时首选错位。试用后关闭 |

### 已实测有效、保持开启

`correct-pinyin`（拼音纠错 gn/ng 等）、`incomplete-pinyin`（简拼/首字母）、
`english-candidate` / `emoji-candidate`（英文/emoji 候选，候选窗实测可见 🕐）。

简拼实测（2026-08-19，剪贴板协议）：长缩写效果好（`jsjbg`→计算机报告、
`zhrmghg`→中*华人民共和*国）；短缩写排序糙（`nh` 前两页竟无"你好"）——
词库静态词频排序，无用户词频/云端排序加持，高频短词建议全拼。

### ⚠️ 自学习的真相（深度实测：学习正常，持久化缺失）

**结论（两阶段修正后的最终版）**：选词学习在引擎**内存**里正常累积（选择提频、
整词上屏都在记），坏的是**持久化**——正常打字和退出从不写盘，引擎重启即清零，
而引擎每天登录都会重启 → "感觉没生效"是准确感知。证据链（全部行为级验证）：

- 学习库 `~/.cache/ibus/libpinyin/` 正常使用下 10 天零增长（md5 冻结）
- strace 全程跟踪引擎：打字、退出、`ibus restart` 全过程**零文件写入**
- journal 佐证：引擎每天登录全新启动，学一点丢一点，净积累为零
- `remember-every-input=true` 无帮助（已回退 false）
- 破局口：`import-dictionary` / `export-dictionary` 动作键（见下节钩子）

**影响**：本引擎智能上限 = 静态词库 + ngram + 持久化钩子（已启用；
云输入与联想均试用后因打断输入流而关闭）。
想要真正"越用越聪明"：等上游修复后重测（社区现状见
[issue #50](https://github.com/libpinyin/ibus-libpinyin/issues/50)，维护者只承诺
设置界面手动导入词库），或届时重评 fcitx5（其自学习+云拼音+zhwiki 词库是完整闭环）。

### 刻意不开（防回归）

- `remember-every-input`：实测无效（引擎根本不写用户库），开了徒增困惑
- `fuzzy-pinyin`：模糊音改变输入习惯，确有需要再自开

### 方法论（下次验证输入法行为的可靠手段）

- 候选内容用**剪贴板协议**验证：打字→选词→`ctrl+a`+`ctrl+c`→`xclip -o`；
  截图读候选不可靠（视觉模型对候选窗细节经常幻觉）
- `ctrl+a` 留下的 selection 会被后续打字**替换**，测累积内容要最后一次性读取
- `pkill -f` 会匹配到自身 shell 的命令行导致自杀，用 `^/完整路径` 锚定
- **注入按键前必须校验 `xdotool getactivewindow` 是自己的测试窗口**——
  实际事故案例：省略校验导致按键注入到无关窗口（只波及了
  无关输入框，未损坏数据）。活跃使用时段禁用全局按键注入
- 测试工具：xdotool（合成按键）+ xclip（剪贴板）+ scrot（截图）已随本机安装

## 自学习持久化钩子（2026-08-19：把缺失的持久化层补在外面）

**发现**：自学习并非完全不工作——选择词频在引擎**内存**里正常累积（export 可见），
坏的是持久化：正常打字/退出从不落盘，重启清零。且 `import-dictionary` /
`export-dictionary` 两个 gsettings 动作键可以驱动引擎导入/导出明文词库。

**实测语义（四条，均行为级验证）**：

1. 动作键写入文件路径 → 运行中的引擎执行导入/导出（三列：`汉字 拼音 频率`，
   音节用 `'` 分隔）
2. **同值不触发**：写入相同路径引擎收不到信号 → 文件名必须每次轮转
3. **import 是加法**：对已存在词条累加频率（重复导入会翻倍）；且**引擎每次
   启动会重放 dconf 里残留的导入值**（不中和则每次重启加一遍）→ 收尾要把
   import-dictionary 指回空文件（"毒丸"）
4. **export 动作会顺带把内存词库刷进引擎缓存**（`~/.cache/ibus/libpinyin/`），
   引擎重启自动从缓存加载 → 「保存」= 触发一次 export，无需手动恢复

**钩子**：`scripts/ibus-pinyin-sync.sh`（systemd 用户定时器，每 5 分钟一轮）：

```bash
bash scripts/ibus-pinyin-sync.sh install    # 安装（开机 90s 首跑，每 5 分钟同步）
bash scripts/ibus-pinyin-sync.sh status     # 查看
bash scripts/ibus-pinyin-sync.sh uninstall  # 卸载
```

- 引擎活着 → 定时 export 攒学习（=保存）；种子表里的**新**词才导入（防加法翻倍）
- 引擎词库为空但状态备份非空 → 缓存被清过，自动从备份恢复
- 已知怪癖：引擎刚拉起的第一轮动作可能被丢（下一轮自愈，定时器场景无害）

**种子词表** `~/.config/ibus/libpinyin/phrases.txt`——想固定首选的词写这里
（每行一个词，可省拼音（pypinyin 自动生成）和频率（默认 500））：

```
进不去                     # 打 jinbuqu 稳居首选
座右铭 zuo'you'ming
阿里巴巴 ali'ba'ba 800
```

≤5 分钟生效（或手动 `bash scripts/ibus-pinyin-sync.sh sync`）。
注意：已导入过的词改频率不生效（加法语义）；词必须纯汉字。

**验证记录（2026-08-19）**：清场后连跑三轮 + 模拟注销重启，种子词频率恒为 500
不漂移；此前未加毒丸的版本每次重启 +500，加法语义实锤。

### 学习资产（"越用越轻松"的本体）

`~/.cache/ibus/libpinyin/` 下的 `user_bigram.db`、`user_pinyin_index.bin`、
`user_phrase_index.bin` 是持续增长的用户词频库，**重装系统前先备份**：

```bash
bash scripts/tune-ibus-libpinyin.sh backup           # 备份学习库
bash scripts/tune-ibus-libpinyin.sh restore 包.tar.gz # 恢复（建议注销后做）
```

设置通常即时生效；行为未变则注销重登（本仓库铁律）。

## ⚠️ 切换会话类型（X11 ↔ Wayland）后必须做的事

**关键教训**：切 X11/Wayland 后，输入法配置必须重新验证！

### 切换后检查清单

```bash
# 1. 确认会话类型
echo $XDG_SESSION_TYPE    # x11 或 wayland

# 2. 确认 IBus 在跑
pgrep -x ibus-daemon

# 3. 确认环境变量（应用靠这个找输入法）
echo $GTK_IM_MODULE       # 应该是 ibus
echo $QT_IM_MODULE        # 应该是 ibus

# 4. 如果不对 → 注销重登（让 ~/.xprofile 生效）
```

### 为什么切换后容易出问题

- 输入法 frontend 在 X11（XIM）和 Wayland（waylandim）不同
- 进程是旧会话启动的，frontend 没切换
- 环境变量（GTK_IM_MODULE 等）可能没传到新会话
- **解决：注销重登**，让一切从干净状态加载

## 常见问题

### Q1：打不出汉字

**第一步永远是注销重登**（让 ~/.xprofile 生效）。不要在当前会话瞎折腾。

```bash
# 注销前确认配置
cat ~/.xprofile           # 应该有 export GTK_IM_MODULE=ibus
cat ~/.xinputrc           # 应该是 run_im ibus
```

### Q2：微信/QT 应用打不出

确认 `~/.xprofile` 有 `QT_IM_MODULE=ibus`。注销重登。

### Q3：想改切换键（默认 Super+Space）

```bash
# GNOME 设置 → 键盘 → 输入源切换键
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space']"
# 改成 Ctrl+Space:
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Control>space']"
```

### Q4：ibus-engine-libpinyin 在哪

```bash
# 不在 /usr/lib/，在 /usr/libexec/
ls /usr/libexec/ibus-engine-libpinyin
```

### Q5：fcitx5 残留导致冲突

如果之前装过 fcitx5，彻底清理：
```bash
# 1. 停 fcitx5
pkill -x fcitx5

# 2. 移除 autostart
rm -f ~/.config/autostart/org.fcitx.Fcitx5.desktop
rm -f ~/.config/autostart/fcitx5-watch.desktop

# 3. 移除 environment.d
rm -f ~/.config/environment.d/fcitx5.conf

# 4. im-config 改回 ibus
im-config -n ibus

# 5. 注销重登
```

## 历史教训：不要在 X11 下用 fcitx5

### 时间线（真实踩坑记录）

```
Day 1 (Wayland): IBus → 切 fcitx5（为微信）→ 正常 ✅
Day 2 (X11):    切 X11（为 RustDesk 被控）
                → fcitx5 失活 ❌
                → 反复重启 fcitx5（治标）❌
                → 怀疑 inotify（错误方向）❌
                → 加 fcitx5-watch 监听（雪上加霜）❌
                → 杀 IBus（破坏平衡）❌
                → 折腾 2 小时
                → 换回 IBus（应该一开始就这么做）✅
```

### 核心教训

1. **GNOME 用 IBus 是最稳的**——原生集成，X11/Wayland 都支持
2. **切会话类型后，先注销重登**，不要在脏环境里折腾
3. **不要叠加"修复"**——每加一层脚本/监听就多一个故障源
4. **fcitx5 在 X11 下不稳定**是已知问题，不是配置问题
5. **微信等 QT 应用**在 X11 + IBus 下能正常工作（不需要 fcitx5）

### 什么情况下用 fcitx5

- 桌面是 **Wayland 且不切 X11**
- 需要 fcitx5 特有功能（特定皮肤/插件/双拼方案）
- 愿意接受偶尔折腾

**否则，GNOME 用户首选 IBus**。

## 相关脚本（项目备份）

- `scripts/restart-fcitx5.sh.example` —— fcitx5 重启脚本（已弃用，保留备查）
- `scripts/fix-fcitx5.sh.example` —— fcitx5 健康检查（已弃用）
- `scripts/fcitx5-watch.sh.example` —— 锁屏恢复监听（已弃用）
- `scripts/xprofile.example` —— ~/.xprofile 模板（IBus 版，当前使用）
- `scripts/tune-ibus-libpinyin.sh` —— **智能调优 + 学习库备份/恢复（当前使用）**
- `scripts/ibus-pinyin-sync.sh` —— **自学习持久化钩子（当前使用，定时器每 5 分钟）**

> fcitx5 相关脚本都已停用，保留只为记录历史。当前用 IBus，无需这些。

