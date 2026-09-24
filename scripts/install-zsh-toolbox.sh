#!/bin/bash
# ======================================================================
# install-zsh-toolbox.sh — 终端 zsh 增强工具链一键安装
#
# 功能（7 步）：
#   1) apt 安装 zsh + 三件套插件 + 现代化命令
#      （zsh-autosuggestions / zsh-syntax-highlighting / fzf / zoxide / bat / eza）
#   2) 下载 starship 提示符到 /usr/local/bin（GitHub 直连 → ghfast/ghproxy 镜像）
#   3) 安装 JetBrainsMono Nerd Font 到 ~/.local/share/fonts（图标显示用）
#   4) 生成 ~/.zshrc + ~/.zprofile（继承 .bashrc 尾部的 JAVA_HOME/nvm/XQAPI，
#      已存在则先备份到 ~/.config/zsh-toolbox/backup-时间戳/）
#   5) chsh 把默认 shell 切到 zsh（原 shell 记录在 state.env，uninstall 可还原）
#   6) GNOME Terminal 默认配置字体切到 Nerd Font（旧值记录，可还原）
#   7) 输出验证清单
#
# 设计原则：不动 ~/.bashrc / ~/.profile 一根手指头，全部新增文件可整体回滚。
#
# 适用：Ubuntu 24.04
# 对应文档：docs/22-工具-终端zsh增强.md
# ======================================================================

set -u

# ---------- 颜色与基础工具（风格与 install-java-maven.sh 一致） ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo; echo -e "${CYAN}==== $* ====${NC}"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "本脚本需要 root 权限（apt/chsh//usr/local/bin）。请用 sudo 运行："
        echo "    sudo bash $0 [install|uninstall|status]"
        exit 1
    fi
}

# sudo 下还原真实用户
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")

# 以真实用户身份跑桌面会话命令（gsettings 需要 user 级 dbus）
run_as_user() {
    runuser -u "$REAL_USER" -- \
        env XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
            "$@"
}

# ---------- 常量 ----------
APT_PKGS="zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide bat eza fontconfig"
STATE_DIR="$REAL_HOME/.config/zsh-toolbox"
STATE_FILE="$STATE_DIR/state.env"
FONT_DIR="$REAL_HOME/.local/share/fonts/JetBrainsMono-Nerd-Font"
MANAGED_MARKER="ZSH-TOOLBOX-MANAGED"

# 直连 → 镜像，依次尝试（镜像前缀直接拼在 GitHub 完整 URL 前，同 install-bbdown.sh）
MIRRORS=(
    ""
    "https://ghfast.top/"
    "https://ghproxy.net/"
)
STARSHIP_URL="https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"

# ---------- 多源下载（验证 gzip/xz 压缩格式才算成功） ----------
download() {
    local dest="$1" url="$2" kind="$3" prefix
    for prefix in "${MIRRORS[@]}"; do
        if [ -z "$prefix" ]; then
            info "尝试直连：$url"
        else
            info "尝试镜像：$prefix"
        fi
        if curl -fsSL --connect-timeout 10 --max-time 300 -o "$dest" "${prefix}${url}" \
           && [ -s "$dest" ] && file -b "$dest" | grep -qi "$kind"; then
            return 0
        fi
        warn "该源下载失败，换下一个..."
        rm -f "$dest"
    done
    return 1
}

# ---------- 步骤 1：apt 安装 ----------
do_apt() {
    title "步骤 1/7 · apt 安装 zsh + 插件 + 现代化命令"
    apt update
    apt install -y $APT_PKGS
    ok "已安装："
    dpkg -l zsh zsh-autosuggestions zsh-syntax-highlighting fzf zoxide bat eza 2>/dev/null \
        | grep '^ii' | awk '{printf "    %s %s\n", $2, $3}'
}

# ---------- 步骤 2：starship ----------
do_starship() {
    title "步骤 2/7 · 安装 starship 提示符 → /usr/local/bin"
    if command -v starship >/dev/null 2>&1; then
        ok "已存在 $(starship --version | head -1)，跳过"
        return 0
    fi
    local tmp="/tmp/starship-$$.tar.gz"
    if ! download "$tmp" "$STARSHIP_URL" gzip; then
        warn "starship 下载全部失败（不影响其他功能，.zshrc 会自动跳过）。"
        warn "网络恢复后重跑 sudo bash $0 install 即可补装"
        return 0
    fi
    tar -xzf "$tmp" -C /usr/local/bin starship && rm -f "$tmp"
    chmod 755 /usr/local/bin/starship
    ok "已安装 $(starship --version | head -1)"
}

# ---------- 步骤 3：Nerd Font ----------
do_font() {
    title "步骤 3/7 · 安装 JetBrainsMono Nerd Font → $FONT_DIR"
    if [ -d "$FONT_DIR" ]; then
        ok "字体目录已存在，跳过下载"
    else
        local tmp="/tmp/nerd-font-$$.tar.xz"
        if ! download "$tmp" "$FONT_URL" 'xz compressed'; then
            warn "字体下载全部失败（eza/starship 图标会显示为方块，功能不受影响）。"
            warn "网络恢复后重跑 sudo bash $0 install 即可补装"
            return 0
        fi
        mkdir -p "$FONT_DIR"
        tar -xJf "$tmp" -C "$FONT_DIR" && rm -f "$tmp"
        chown -R "$REAL_USER":"$(id -g "$REAL_USER")" "$REAL_HOME/.local/share/fonts"
    fi
    run_as_user fc-cache -f "$REAL_HOME/.local/share/fonts" >/dev/null 2>&1
    local families
    families=$(run_as_user fc-list --format='%{family}\n' 2>/dev/null | grep -i 'JetBrainsMono Nerd Font Mono' | head -1)
    if [ -n "$families" ]; then
        ok "字体已注册，family = $families"
    else
        warn "fc-list 未查到字体，图标可能异常（不影响命令功能）"
    fi
}

# ---------- 步骤 4：生成 .zshrc / .zprofile ----------
write_zshrc() {
    title "步骤 4/7 · 生成 ~/.zshrc + ~/.zprofile"

    mkdir -p "$STATE_DIR"
    local ts backup_dir
    ts=$(date +%Y%m%d%H%M%S)
    backup_dir="$STATE_DIR/backup-$ts"
    local zshrc_bak="NONE" zprofile_bak="NONE"

    # 备份既有文件：带管理标记的（本脚本生成的）不备份；用户自己的才备份
    if [ -f "$REAL_HOME/.zshrc" ] && ! grep -q "$MANAGED_MARKER" "$REAL_HOME/.zshrc"; then
        mkdir -p "$backup_dir"
        cp -v "$REAL_HOME/.zshrc" "$backup_dir/.zshrc"
        zshrc_bak="$backup_dir/.zshrc"
        warn "检测到用户已有 .zshrc，已备份到 $zshrc_bak"
    elif [ -f "$REAL_HOME/.zshrc" ]; then
        zshrc_bak="MANAGED_OVERWRITE"
    fi
    if [ -f "$REAL_HOME/.zprofile" ] && ! grep -q "$MANAGED_MARKER" "$REAL_HOME/.zprofile"; then
        mkdir -p "$backup_dir"
        cp -v "$REAL_HOME/.zprofile" "$backup_dir/.zprofile"
        zprofile_bak="$backup_dir/.zprofile"
        warn "检测到用户已有 .zprofile，已备份到 $zprofile_bak"
    elif [ -f "$REAL_HOME/.zprofile" ]; then
        zprofile_bak="MANAGED_OVERWRITE"
    fi

    cat > "$REAL_HOME/.zshrc" << 'ZSHRC_EOF'
# ~/.zshrc — 由 环境安装/scripts/install-zsh-toolbox.sh 生成并管理
# 管理标记：ZSH-TOOLBOX-MANAGED（uninstall 据此清理/还原）
# 重新运行 install 会覆盖本文件；个人自定义请加到「用户自定义」段之后

# ===== 历史 =====
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY            # 多个终端实时共享历史
setopt HIST_IGNORE_ALL_DUPS     # 完全重复的命令只留一条
setopt HIST_REDUCE_BLANKS       # 记录前压缩多余空格
setopt HIST_IGNORE_SPACE        # 空格开头的命令不进历史（输密码用）
setopt AUTO_CD                  # 直接敲目录名即 cd

# ===== 补全 =====
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select                        # 补全菜单方向键可选
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # 补全忽略大小写

# ===== 环境继承（原在 ~/.bashrc 尾部，bash 专用，切 zsh 后须在此重复一份）=====
# 1) ~/bin、~/.local/bin（taos/BBDown wrapper 所在，docs/20/22）
for _d in "$HOME/bin" "$HOME/.local/bin"; do
    [[ -d "$_d" ]] && [[ ":$PATH:" != *":$_d:"* ]] && PATH="$_d:$PATH"
done
unset _d
# 2) JAVA_HOME 动态解析（docs/15，与 .bashrc 保持一致）
if command -v java >/dev/null 2>&1; then
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
    [[ ":$PATH:" != *":$JAVA_HOME/bin:"* ]] && export PATH="$JAVA_HOME/bin:$PATH"
fi
# 3) nvm + dsh 的 Node（docs/21，nvm.sh 原生支持 zsh）
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# 4) XQAPI_API_KEY（codex CLI 依赖，来自 dsh 凭据）
export XQAPI_API_KEY="$(python3 -c "import yaml; print(yaml.safe_load(open('$HOME/.dsh/.credentials.yaml'))['XQAPI_API_KEY'])" 2>/dev/null)"
# 5) DBeaver 中文界面别名
alias dbeaver-ce='dbeaver-ce -nl zh'

# ===== zsh-autosuggestions：灰色历史建议，按 → 采纳 =====
[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# ===== fzf：Ctrl+R 搜历史 / Ctrl+T 搜文件 / Alt+C 跳目录 =====
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && \
    source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && \
    source /usr/share/doc/fzf/examples/completion.zsh

# ===== zoxide：z 关键词 直接跳常去目录（自动学习 cd 习惯）=====
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ===== 现代化命令 =====
command -v batcat >/dev/null 2>&1 && alias bat='batcat --paging=never'
if command -v eza >/dev/null 2>&1; then
    _zt_icons=''
    [[ -d "$HOME/.local/share/fonts/JetBrainsMono-Nerd-Font" ]] && _zt_icons='--icons'
    alias ls="eza --group-directories-first $_zt_icons"
    alias ll="eza -lg --group-directories-first $_zt_icons"
    alias la="eza -lga --group-directories-first $_zt_icons"
    alias lt="eza -T --level=2 $_zt_icons"
    unset _zt_icons
fi

# ===== starship 提示符（git 分支/命令耗时/上次退出码）=====
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# ===== 语法高亮：命令正确绿色、错误红色（必须放最后）=====
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ===== 用户自定义区 =====
# 本文件重跑 install 时会被覆盖，个人配置请写进 ~/.zshrc.local（此行下方自动加载）
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
ZSHRC_EOF

    cat > "$REAL_HOME/.zprofile" << 'ZPROFILE_EOF'
# ~/.zprofile — 登录 shell 加载（由 install-zsh-toolbox.sh 生成管理）
# 管理标记：ZSH-TOOLBOX-MANAGED
# zsh 登录 shell 不读 ~/.profile，这里显式继承 bash 时代的 PATH 等配置
[ -f "$HOME/.profile" ] && emulate sh -c "source '$HOME/.profile'"
ZPROFILE_EOF

    chown "$REAL_USER":"$(id -g "$REAL_USER")" "$REAL_HOME/.zshrc" "$REAL_HOME/.zprofile"
    ok "已生成 $REAL_HOME/.zshrc（$(wc -l < "$REAL_HOME/.zshrc") 行）"
    ok "已生成 $REAL_HOME/.zprofile"

    # 记录状态供 uninstall 回滚
    cat > "$STATE_FILE" << EOF
# install-zsh-toolbox.sh 状态文件（uninstall 用）
PREV_SHELL=$(getent passwd "$REAL_USER" | cut -d: -f7)
ZSHRC_BACKUP=$zshrc_bak
ZPROFILE_BACKUP=$zprofile_bak
EOF
    chown -R "$REAL_USER":"$(id -g "$REAL_USER")" "$STATE_DIR"
    ok "已记录原 shell 与备份位置 → $STATE_FILE"
}

# ---------- 步骤 5：切换默认 shell ----------
do_chsh() {
    title "步骤 5/7 · 默认 shell 切换为 zsh"
    local current
    current=$(getent passwd "$REAL_USER" | cut -d: -f7)
    if [ "$current" = "/usr/bin/zsh" ] || [ "$current" = "/bin/zsh" ]; then
        ok "当前已是 zsh，跳过"
        return 0
    fi
    if ! grep -qE '^/usr/bin/zsh$' /etc/shells; then
        err "/etc/shells 中无 /usr/bin/zsh（apt 安装异常），中止切换"
        return 1
    fi
    chsh -s /usr/bin/zsh "$REAL_USER"
    ok "已切换：$current → /usr/bin/zsh（新开终端生效，当前已开的终端不受影响）"
}

# ---------- 步骤 6：GNOME Terminal 字体 ----------
do_terminal_font() {
    title "步骤 6/7 · GNOME Terminal 字体切换（best-effort）"
    if [ ! -d "$FONT_DIR" ]; then
        info "字体未安装成功，跳过终端字体设置"
        return 0
    fi
    local profile old_font old_use_sys size new_font
    profile=$(run_as_user gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
    if [ -z "$profile" ]; then
        warn "读不到 GNOME Terminal 默认 profile（无桌面会话？），请手动设字体："
        echo "    GNOME Terminal → 偏好设置 → 你的配置 → 外观 → 字体 → JetBrainsMono Nerd Font Mono"
        return 0
    fi
    local schema_path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile}/"
    old_font=$(run_as_user gsettings get "$schema_path" font 2>/dev/null)
    old_use_sys=$(run_as_user gsettings get "$schema_path" use-system-font 2>/dev/null)

    # 从旧字体名提取字号（如 'Ubuntu Mono 13' → 13），保不住就 12
    size=$(echo "$old_font" | grep -oE '[0-9]+[^0-9]*$' | tr -dc '0-9')
    [ -z "$size" ] && size=12
    new_font="JetBrainsMono Nerd Font Mono $size"

    if run_as_user gsettings set "$schema_path" font "$new_font" \
       && run_as_user gsettings set "$schema_path" use-system-font false; then
        ok "终端字体：$old_font → '$new_font'"
        # 记录旧值供 uninstall 还原
        {
            echo "GT_PROFILE=$profile"
            echo "GT_FONT_OLD=$old_font"
            echo "GT_USE_SYS_OLD=${old_use_sys:-true}"
        } >> "$STATE_FILE"
    else
        warn "gsettings 设置失败，请手动改：偏好设置 → 配置 → 外观 → 字体 → JetBrainsMono Nerd Font Mono"
    fi
}

# ---------- 步骤 7：验证 ----------
do_verify() {
    title "步骤 7/7 · 验证"
    local fail=0

    # zsh 内部检查：$1=描述 $2=zsh 表达式（以真实用户身份跑交互 zsh，读用户的 .zshrc）
    zsh_check() {
        if run_as_user zsh -ic "$2" >/dev/null 2>&1; then
            ok "$1"
        else
            warn "$1 —— 未通过"
            fail=$((fail+1))
        fi
    }
    # 系统级检查：$1=描述 $2=bash 命令
    sys_check() {
        if eval "$2" >/dev/null 2>&1; then
            ok "$1"
        else
            warn "$1 —— 未通过"
            fail=$((fail+1))
        fi
    }

    sys_check "zsh 已安装"             'command -v zsh'
    zsh_check "autosuggestions 已加载" '(( $+functions[_zsh_autosuggest_start] ))'
    zsh_check "语法高亮已加载"          '(( $+functions[_zsh_highlight] ))'
    zsh_check "fzf Ctrl+R 已绑定"       'bindkey "^R" | grep -qi fzf'
    zsh_check "zoxide 可用"             'command -v zoxide'
    sys_check "starship 可用"           'starship --version'
    sys_check "Nerd 字体已注册"         'run_as_user fc-list | grep -qi "JetBrainsMono Nerd Font Mono"'
    zsh_check "JAVA_HOME 继承"          '[[ -n $JAVA_HOME ]]'
    zsh_check "nvm/node 继承"           'command -v node'
    zsh_check "XQAPI_API_KEY 继承"      '[[ -n $XQAPI_API_KEY ]]'
    sys_check "默认 shell 已是 zsh"      '[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" = "/usr/bin/zsh" ]'

    echo
    info "zsh 启动耗时（应 < 0.5s）："
    run_as_user zsh -ic exit >/dev/null 2>&1   # 预热，首次会编译 compdump 不计入
    TIMEFORMAT='    zsh 启动: %Rs'
    time run_as_user zsh -ic exit >/dev/null 2>&1

    echo
    if [ "$fail" -eq 0 ]; then
        ok "全部通过 ✅  新开一个终端窗口即可体验（灰色建议→采纳 / Ctrl+R 搜历史 / z 跳目录）"
    else
        warn "$fail 项未通过，常见原因：网络下载失败（重跑 install 补装）或无桌面会话（字体项）"
    fi
}

# ---------- 卸载（完整回滚） ----------
do_uninstall() {
    need_root
    title "卸载 · 回滚所有改动"

    # 读取状态（可能不存在）
    local prev_shell="/bin/bash" zshrc_bak="NONE" zprofile_bak="NONE"
    local gt_profile="" gt_font_old="" gt_use_sys_old="true"
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        prev_shell="${PREV_SHELL:-/bin/bash}"
        zshrc_bak="${ZSHRC_BACKUP:-NONE}"
        zprofile_bak="${ZPROFILE_BACKUP:-NONE}"
        gt_profile="${GT_PROFILE:-}"
        gt_font_old="${GT_FONT_OLD:-}"
        gt_use_sys_old="${GT_USE_SYS_OLD:-true}"
    else
        warn "状态文件不存在，按默认值回滚（shell→/bin/bash，删除托管文件）"
    fi

    # 1) 还原默认 shell
    if getent passwd "$REAL_USER" | cut -d: -f7 | grep -q zsh; then
        if [ -x "$prev_shell" ]; then
            chsh -s "$prev_shell" "$REAL_USER"
            ok "默认 shell 已还原为 $prev_shell"
        else
            warn "原 shell $prev_shell 不可用，保持现状（请手动 chsh -s /bin/bash）"
        fi
    else
        ok "默认 shell 已不是 zsh，跳过"
    fi

    # 2) 还原/删除 .zshrc、.zprofile
    if [ "$zshrc_bak" != "NONE" ] && [ "$zshrc_bak" != "MANAGED_OVERWRITE" ] && [ -f "$zshrc_bak" ]; then
        cp -v "$zshrc_bak" "$REAL_HOME/.zshrc"
        chown "$REAL_USER":"$(id -g "$REAL_USER")" "$REAL_HOME/.zshrc"
        ok ".zshrc 已从备份还原"
    elif [ -f "$REAL_HOME/.zshrc" ] && grep -q "$MANAGED_MARKER" "$REAL_HOME/.zshrc"; then
        rm -v "$REAL_HOME/.zshrc"
        ok ".zshrc（本脚本生成）已删除"
    fi
    if [ "$zprofile_bak" != "NONE" ] && [ "$zprofile_bak" != "MANAGED_OVERWRITE" ] && [ -f "$zprofile_bak" ]; then
        cp -v "$zprofile_bak" "$REAL_HOME/.zprofile"
        chown "$REAL_USER":"$(id -g "$REAL_USER")" "$REAL_HOME/.zprofile"
        ok ".zprofile 已从备份还原"
    elif [ -f "$REAL_HOME/.zprofile" ] && grep -q "$MANAGED_MARKER" "$REAL_HOME/.zprofile"; then
        rm -v "$REAL_HOME/.zprofile"
        ok ".zprofile（本脚本生成）已删除"
    fi

    # 3) 还原 GNOME Terminal 字体
    if [ -n "$gt_profile" ]; then
        local schema_path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${gt_profile}/"
        run_as_user gsettings set "$schema_path" font "$gt_font_old" 2>/dev/null \
            && run_as_user gsettings set "$schema_path" use-system-font "$gt_use_sys_old" 2>/dev/null \
            && ok "GNOME Terminal 字体已还原为 $gt_font_old（use-system-font=$gt_use_sys_old）" \
            || warn "终端字体还原失败，请到 GNOME Terminal 偏好设置手动改回"
    fi

    # 4) 删 starship 与字体
    rm -fv /usr/local/bin/starship
    if [ -d "$FONT_DIR" ]; then
        rm -rfv "$FONT_DIR"
        run_as_user fc-cache -f "$REAL_HOME/.local/share/fonts" >/dev/null 2>&1
        ok "Nerd Font 已删除并刷新缓存"
    fi

    # 5) 卸载 apt 包
    apt remove -y $APT_PKGS
    ok "apt 包已卸载"

    # 6) 清理状态目录（备份目录一并删除，先提示）
    if [ -d "$STATE_DIR" ]; then
        rm -rf "$STATE_DIR"
        ok "状态目录 $STATE_DIR 已删除"
    fi

    echo
    ok "卸载完成。全程未动过 ~/.bashrc / ~/.profile，它们保持原样。"
    info "保留物：~/.zsh_history（命令历史，如不需要可手删）"
}

# ---------- 状态查看（无需 root） ----------
do_status() {
    title "zsh-toolbox 状态"
    local current
    current=$(getent passwd "$REAL_USER" | cut -d: -f7)
    echo "默认 shell      : $current"
    echo "zsh             : $(dpkg -l zsh 2>/dev/null | grep '^ii' | awk '{print $3}' || echo 未安装)"
    echo "autosuggestions : $([ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && echo 已装 || echo 未装)"
    echo "syntax-highlight: $([ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && echo 已装 || echo 未装)"
    echo "fzf             : $(command -v fzf >/dev/null && fzf --version | awk '{print $1}' || echo 未装)"
    echo "zoxide          : $(command -v zoxide >/dev/null && echo 已装 || echo 未装)"
    echo "bat             : $(command -v batcat >/dev/null && batcat --version || echo 未装)"
    echo "eza             : $(command -v eza >/dev/null && eza --version | head -1 || echo 未装)"
    echo "starship        : $(command -v starship >/dev/null && starship --version | head -1 || echo 未装)"
    echo "Nerd Font       : $([ -d "$FONT_DIR" ] && echo 已装 || echo 未装)"
    echo ".zshrc          : $([ -f "$REAL_HOME/.zshrc" ] && grep -q "$MANAGED_MARKER" "$REAL_HOME/.zshrc" && echo 本脚本托管 || ([ -f "$REAL_HOME/.zshrc" ] && echo 用户自有 || echo 不存在))"
    echo "状态文件        : $([ -f "$STATE_FILE" ] && echo 存在 || echo 无)"
}

# ---------- 帮助 ----------
show_help() {
    cat << EOF
用法：sudo bash $0 [子命令]

子命令（缺省 = install）：
  install    一键安装：apt 包 + starship + Nerd Font + .zshrc/.zprofile + chsh + 终端字体
  uninstall  完整回滚：还原 shell/配置文件/终端字体，删 starship/字体/包（.bashrc 从未被动过）
  status     查看各组件安装状态（无需 sudo）
  help       显示本帮助

安全设计：
  - 全程不修改 ~/.bashrc / ~/.profile，bash 环境保持原样
  - 已存在的 .zshrc/.zprofile 若非本脚本生成，先备份到 ~/.config/zsh-toolbox/backup-*/
  - starship/字体下载失败只 warn 跳过，不中断；重跑 install 可补装
  - 个人 zsh 自定义放 ~/.zshrc.local（重跑 install 不会丢）

示例：
  sudo bash $0              # 一键安装
  sudo bash $0 status       # 查看状态
  sudo bash $0 uninstall    # 完整回滚
EOF
}

# ---------- 入口 ----------
main() {
    local cmd="${1:-install}"
    case "$cmd" in
        install)
            need_root
            do_apt
            do_starship
            do_font
            write_zshrc
            do_chsh
            do_terminal_font
            do_verify
            ;;
        uninstall) do_uninstall ;;
        status)     do_status ;;
        help|-h|--help) show_help ;;
        *) err "未知子命令：$cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
