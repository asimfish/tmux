#!/usr/bin/env bash
# tmux × AI 工作流 一键安装脚本
# https://github.com/asimfish/tmux
#
# 安装内容：
#   - Ghostty 终端（macOS）
#   - tmux + TPM 插件管理器 + 全套插件
#   - 配套工具：starship / fzf / zoxide / eza / bat / lazygit 等
#   - 应用本仓库 .tmux.conf 配置

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${BLUE}[tmux-ai]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

echo -e "${BOLD}"
echo "  ████████╗███╗   ███╗██╗   ██╗██╗  ██╗  ×  █████╗ ██╗"
echo "     ██╔══╝████╗ ████║██║   ██║╚██╗██╔╝    ██╔══██╗██║"
echo "     ██║   ██╔████╔██║██║   ██║ ╚███╔╝     ███████║██║"
echo "     ██║   ██║╚██╔╝██║██║   ██║ ██╔██╗     ██╔══██║██║"
echo "     ██║   ██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗    ██║  ██║██║"
echo "     ╚═╝   ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝"
echo -e "${NC}"
echo -e "  ${BLUE}tmux × AI 工作流 一键安装脚本${NC}"
echo -e "  https://github.com/asimfish/tmux"
echo ""

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────
# 1. 检查 Homebrew（macOS 必须）
# ──────────────────────────────────────────
if $IS_MAC; then
  if ! command -v brew &>/dev/null; then
    log "安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "Homebrew 安装完成"
  else
    ok "Homebrew 已安装"
  fi
fi

# ──────────────────────────────────────────
# 2. 安装 Ghostty（仅 macOS）
# ──────────────────────────────────────────
if $IS_MAC; then
  if ! command -v ghostty &>/dev/null && [[ ! -d "/Applications/Ghostty.app" ]]; then
    log "安装 Ghostty 终端..."
    brew install --cask ghostty
    ok "Ghostty 安装完成"
  else
    ok "Ghostty 已安装，跳过"
  fi

  # JetBrains Mono Nerd Font
  if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono" && \
     ! ls ~/Library/Fonts/JetBrainsMonoNerd* &>/dev/null 2>&1; then
    log "安装 JetBrains Mono Nerd Font..."
    brew install --cask font-jetbrains-mono-nerd-font
    ok "字体安装完成"
  else
    ok "JetBrains Mono Nerd Font 已安装，跳过"
  fi
fi

# ──────────────────────────────────────────
# 3. 安装 tmux
# ──────────────────────────────────────────
if ! command -v tmux &>/dev/null; then
  log "安装 tmux..."
  if $IS_MAC; then
    brew install tmux
  elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y tmux
  elif command -v yum &>/dev/null; then
    sudo yum install -y tmux
  else
    err "无法自动安装 tmux，请手动安装后重试"
  fi
else
  ok "tmux 已安装 ($(tmux -V))"
fi

# ──────────────────────────────────────────
# 4. 安装配套工具
# ──────────────────────────────────────────
log "安装配套工具（starship / fzf / zoxide / eza / bat / lazygit 等）..."

if $IS_MAC; then
  TOOLS=(starship zsh-autosuggestions zsh-syntax-highlighting fzf zoxide eza bat \
         ripgrep fd git-delta lazygit tldr btop)
  for tool in "${TOOLS[@]}"; do
    if ! brew list "$tool" &>/dev/null; then
      brew install "$tool" && ok "$tool 安装完成"
    else
      ok "$tool 已安装，跳过"
    fi
  done
elif command -v apt &>/dev/null; then
  sudo apt install -y fzf ripgrep fd-find bat
  # zoxide
  if ! command -v zoxide &>/dev/null; then
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi
  # starship
  if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh
  fi
  ok "配套工具安装完成"
fi

# ──────────────────────────────────────────
# 5. 备份 + 安装 .tmux.conf
# ──────────────────────────────────────────
if [[ -f "$HOME/.tmux.conf" ]]; then
  BACKUP="$HOME/.tmux.conf.bak.$(date +%Y%m%d%H%M%S)"
  warn "已有 .tmux.conf，备份到 $BACKUP"
  cp "$HOME/.tmux.conf" "$BACKUP"
fi
cp "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
ok "tmux 配置文件已安装到 ~/.tmux.conf"

# ──────────────────────────────────────────
# 6. 安装 TPM 插件管理器
# ──────────────────────────────────────────
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
  log "安装 TPM 插件管理器..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM 安装完成"
else
  ok "TPM 已存在，跳过"
fi

# ──────────────────────────────────────────
# 7. 配置 servers.conf 模板
# ──────────────────────────────────────────
if [[ ! -f "$REPO_DIR/servers.conf" ]]; then
  cp "$REPO_DIR/servers.conf.example" "$REPO_DIR/servers.conf"
  ok "已创建 servers.conf（请编辑填入你的服务器信息）"
else
  ok "servers.conf 已存在，跳过"
fi

# ──────────────────────────────────────────
# 8. 设置 shell alias
# ──────────────────────────────────────────
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
  ALIAS_MARKER="# tmux-ai aliases"
  if ! grep -q "$ALIAS_MARKER" "$SHELL_RC" 2>/dev/null; then
    log "添加命令别名到 $SHELL_RC..."
    cat >> "$SHELL_RC" << ALIASEOF

$ALIAS_MARKER
alias login="bash $REPO_DIR/scripts/login.sh"
alias smon="bash $REPO_DIR/scripts/server-monitor.sh"
alias bind-server="bash $REPO_DIR/scripts/bind-server.sh"
alias supershell="bash $REPO_DIR/scripts/supershell.sh"
alias setup-workspace="bash $REPO_DIR/scripts/setup-workspace.sh"
alias health-check="bash $REPO_DIR/scripts/health-check.sh"
ALIASEOF
    ok "已添加 alias：login / smon / bind-server / supershell / setup-workspace / health-check"
  else
    ok "alias 已存在，跳过"
  fi
fi

# ──────────────────────────────────────────
# 9. 确保 SSH socket 目录存在
# ──────────────────────────────────────────
mkdir -p "$HOME/.ssh/sockets" 2>/dev/null
ok "SSH socket 目录就绪"

# ──────────────────────────────────────────
# 10. 安装 Ghostty 配置（macOS）
# ──────────────────────────────────────────
if $IS_MAC && [[ -f "$REPO_DIR/ghostty.config" ]]; then
  GHOSTTY_CFG_DIR="$HOME/.config/ghostty"
  mkdir -p "$GHOSTTY_CFG_DIR"
  if [[ -f "$GHOSTTY_CFG_DIR/config" ]]; then
    warn "已有 Ghostty 配置，备份到 $GHOSTTY_CFG_DIR/config.bak"
    cp "$GHOSTTY_CFG_DIR/config" "$GHOSTTY_CFG_DIR/config.bak"
  fi
  cp "$REPO_DIR/ghostty.config" "$GHOSTTY_CFG_DIR/config"
  ok "Ghostty 配置文件已安装到 ~/.config/ghostty/config"
fi

# ──────────────────────────────────────────
# 11. 完成
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ 安装完成！${NC}"
echo ""
echo -e "  ${BOLD}下一步：${NC}"
echo ""
if $IS_MAC; then
echo "  1. 启动 Ghostty（已安装在 /Applications/Ghostty.app）"
echo "  2. 在 Ghostty 中启动 tmux："
echo "       tmux"
else
echo "  1. 启动 tmux："
echo "       tmux"
fi
echo "  3. 安装 tmux 插件：按 Ctrl-w + I（大写 i）等待完成"
echo "  4. 重载配置：按 Ctrl-w + r"
echo ""
echo -e "  ${BOLD}配置服务器（可选）：${NC}"
echo ""
echo "  5. 编辑服务器配置：vim $REPO_DIR/servers.conf"
echo "  6. 测试快速登录：login --list"
echo "  7. 启动监控面板：smon"
echo ""
if [[ -n "$SHELL_RC" ]]; then
echo -e "  ${YELLOW}提示：请重新打开终端或执行 source $SHELL_RC 使 alias 生效${NC}"
echo ""
fi
echo -e "  ${BLUE}完整教程：${NC}https://github.com/asimfish/tmux"
echo ""
