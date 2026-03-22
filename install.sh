#!/usr/bin/env bash
# tmux × AI 工作流 一键安装脚本
# https://github.com/asimfish/tmux

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${BLUE}[tmux-ai]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

log "开始安装 tmux × AI 工作流配置..."

# 1. 安装 tmux
if ! command -v tmux &>/dev/null; then
  log "安装 tmux..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install tmux
  elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y tmux
  elif command -v yum &>/dev/null; then
    sudo yum install -y tmux
  else
    warn "无法自动安装 tmux，请手动安装后重试"
    exit 1
  fi
else
  ok "tmux 已安装 ($(tmux -V))"
fi

# 2. 备份已有配置
if [[ -f "$HOME/.tmux.conf" ]]; then
  BACKUP="$HOME/.tmux.conf.bak.$(date +%Y%m%d%H%M%S)"
  warn "已有 .tmux.conf，备份到 $BACKUP"
  cp "$HOME/.tmux.conf" "$BACKUP"
fi

# 3. 安装配置文件
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"
ok "配置文件已安装到 ~/.tmux.conf"

# 4. 安装 TPM 插件管理器
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
  log "安装 TPM 插件管理器..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM 已安装"
else
  ok "TPM 已存在，跳过"
fi

# 5. 完成提示
echo ""
ok "安装完成！"
echo ""
echo -e "  ${BLUE}下一步：${NC}"
echo "  1. 启动 tmux：tmux"
echo "  2. 安装插件：按 Ctrl-w + I（大写 i）"
echo "  3. 查看教程：https://github.com/asimfish/tmux"
echo ""
