#!/usr/bin/env bash
# setup-workspace.sh — 一键搭建 tmux 工作区
#
# 用法：
#   bash setup-workspace.sh                  # 交互式选择模板
#   bash setup-workspace.sh dev              # 开发模板
#   bash setup-workspace.sh train <服务器>   # 训练模板 + 远程登录
#   bash setup-workspace.sh multi            # 多服务器管理模板
#   bash setup-workspace.sh custom <yaml>    # 自定义布局
#
# 模板说明：
#   dev    — 本地开发：代码 + Claude + 日志
#   train  — 远程训练：SSH + 监控
#   multi  — 多服务器并行管理
#   claude — Claude Code 专用工作区

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"

log()  { echo -e "${BLUE}[workspace]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# ── dev 模板：标准三格开发布局 ────────────────────────────────────
setup_dev() {
  local session="${1:-dev}"
  local workdir="${2:-$(pwd)}"

  log "搭建开发工作区：$session"

  tmux new-session -d -s "$session" -c "$workdir" -n "code"

  # 主 pane = 代码编辑
  # 右侧 pane = Claude Code
  tmux split-window -h -t "$session:1" -c "$workdir"
  tmux send-keys -t "$session:1.2" "claude" Enter

  # 底部 pane = 日志/测试
  tmux split-window -v -t "$session:1.1" -c "$workdir" -l 30%

  # 聚焦到代码区
  tmux select-pane -t "$session:1.1"

  # 可选：额外 window 跑 git
  tmux new-window -t "$session" -n "git" -c "$workdir"
  tmux send-keys -t "$session:git" "lazygit 2>/dev/null || git status" Enter

  ok "开发工作区就绪"
  echo -e "  ${DIM}布局：左上=代码  右=Claude  左下=日志${NC}"

  if [[ -z "${TMUX:-}" ]]; then
    tmux attach -t "$session"
  else
    tmux switch-client -t "$session"
  fi
}

# ── train 模板：远程训练布局 ──────────────────────────────────────
setup_train() {
  local server_alias="${1:-}"
  local session="train"

  if [[ -z "$server_alias" ]]; then
    # fzf 选服务器
    if command -v fzf &>/dev/null && [[ -f "$CONF_FILE" ]]; then
      local entries=""
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        local a=$(echo "$line" | awk '{print $1}')
        local d=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i}')
        entries+="$a  $d\n"
      done < "$CONF_FILE"

      server_alias=$(echo -e "$entries" | fzf --reverse --border --prompt="选择训练服务器: " | awk '{print $1}') || true
    fi

    if [[ -z "$server_alias" ]]; then
      warn "未选择服务器，创建本地训练工作区"
      setup_dev "train"
      return
    fi
  fi

  session="train-${server_alias}"
  log "搭建训练工作区：$session → $server_alias"

  tmux new-session -d -s "$session" -n "ssh"

  # window 1: SSH 到服务器
  tmux send-keys -t "$session:ssh" "bash '$SCRIPT_DIR/login.sh' '$server_alias'" Enter

  # window 2: 监控面板
  tmux new-window -t "$session" -n "monitor"
  tmux send-keys -t "$session:monitor" "bash '$SCRIPT_DIR/server-monitor.sh' '$server_alias'" Enter

  # window 3: 本地 Claude（如果有 bind-server）
  tmux new-window -t "$session" -n "claude"
  tmux send-keys -t "$session:claude" "bash '$SCRIPT_DIR/bind-server.sh' '$server_alias' 2>/dev/null || echo '提示：配置 sshfs 后可用 bind-server 挂载远程目录'" Enter

  tmux select-window -t "$session:ssh"

  ok "训练工作区就绪"
  echo -e "  ${DIM}Window 1=SSH  2=监控  3=Claude${NC}"

  if [[ -z "${TMUX:-}" ]]; then
    tmux attach -t "$session"
  else
    tmux switch-client -t "$session"
  fi
}

# ── multi 模板：多服务器并行 ──────────────────────────────────────
setup_multi() {
  local session="servers"

  log "搭建多服务器管理工作区"

  if [[ ! -f "$CONF_FILE" ]]; then
    warn "找不到 servers.conf，创建基础工作区"
    tmux new-session -d -s "$session" -n "monitor"
    tmux send-keys -t "$session:monitor" "echo '请先配置 servers.conf'" Enter
    [[ -z "${TMUX:-}" ]] && tmux attach -t "$session" || tmux switch-client -t "$session"
    return
  fi

  tmux new-session -d -s "$session" -n "monitor"
  tmux send-keys -t "$session:monitor" "bash '$SCRIPT_DIR/server-monitor.sh'" Enter

  # 每台服务器一个 window
  local count=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local alias=$(echo "$line" | awk '{print $1}')

    tmux new-window -t "$session" -n "$alias"
    tmux send-keys -t "$session:${alias}" "bash '$SCRIPT_DIR/login.sh' '$alias'" Enter
    count=$((count + 1))
  done < "$CONF_FILE"

  tmux select-window -t "$session:monitor"

  ok "多服务器工作区就绪（${count} 台服务器 + 监控）"

  if [[ -z "${TMUX:-}" ]]; then
    tmux attach -t "$session"
  else
    tmux switch-client -t "$session"
  fi
}

# ── claude 模板：Claude Code 专用 ─────────────────────────────────
setup_claude() {
  local session="claude"
  local workdir="${1:-$(pwd)}"

  log "搭建 Claude Code 工作区"

  tmux new-session -d -s "$session" -c "$workdir" -n "main"

  # 全屏 Claude
  tmux send-keys -t "$session:main" "claude" Enter

  # 第二个 window: 终端
  tmux new-window -t "$session" -n "term" -c "$workdir"

  # 第三个 window: git
  tmux new-window -t "$session" -n "git" -c "$workdir"
  tmux send-keys -t "$session:git" "lazygit 2>/dev/null || git log --oneline -20" Enter

  tmux select-window -t "$session:main"

  ok "Claude 工作区就绪"

  if [[ -z "${TMUX:-}" ]]; then
    tmux attach -t "$session"
  else
    tmux switch-client -t "$session"
  fi
}

# ── fzf 交互选择模板 ──────────────────────────────────────────────
interactive_select() {
  if ! command -v fzf &>/dev/null; then
    echo -e "\n${BOLD}可用工作区模板：${NC}\n"
    echo "  dev      标准开发布局（代码 + Claude + 日志）"
    echo "  train    远程训练布局（SSH + 监控 + Claude）"
    echo "  multi    多服务器并行管理"
    echo "  claude   Claude Code 专用工作区"
    echo ""
    echo "用法：setup-workspace <模板名>"
    return
  fi

  local selected
  selected=$(cat << 'EOF' | fzf --ansi --reverse --border=rounded \
    --border-label=" 🏗 Workspace Templates " \
    --prompt="  ❯ " --pointer="▶" \
    --color="bg+:#2d2d2d,fg+:#e0e0e0,hl:#ff9e64,hl+:#ff9e64,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,border:#3b4261,label:#7aa2f7" \
    --preview="
      t=\$(echo {} | awk '{print \$1}')
      case \$t in
        dev)    echo '标准三格开发布局'; echo ''; echo '┌──────────┬──────────┐'; echo '│  代码    │  Claude  │'; echo '├──────────┤          │'; echo '│  日志    │          │'; echo '└──────────┴──────────┘'; echo ''; echo 'Windows: code, git' ;;
        train)  echo '远程训练工作区'; echo ''; echo 'Window 1: SSH 到服务器 + tmux'; echo 'Window 2: 服务器监控面板'; echo 'Window 3: Claude bind-server' ;;
        multi)  echo '多服务器并行管理'; echo ''; echo 'Window 1: 全局监控面板'; echo 'Window 2~N: 每台服务器一个 window'; echo ''; echo '从 servers.conf 读取服务器列表' ;;
        claude) echo 'Claude Code 专用'; echo ''; echo 'Window 1: Claude (全屏)'; echo 'Window 2: 终端'; echo 'Window 3: lazygit' ;;
      esac
    " \
    --preview-window="right:40%:wrap"
  ) || true

  dev      标准开发布局（代码 + Claude + 日志）
  train    远程训练布局（SSH + 监控 + Claude）
  multi    多服务器并行管理
  claude   Claude Code 专用工作区
EOF

  if [[ -n "$selected" ]]; then
    local template=$(echo "$selected" | awk '{print $1}')
    case "$template" in
      dev)    setup_dev ;;
      train)  setup_train ;;
      multi)  setup_multi ;;
      claude) setup_claude ;;
    esac
  fi
}

# ── 主入口 ────────────────────────────────────────────────────────
case "${1:-}" in
  ""|"-h"|"--help")
    interactive_select
    ;;
  dev)
    setup_dev "${2:-dev}" "${3:-}"
    ;;
  train)
    setup_train "${2:-}"
    ;;
  multi)
    setup_multi
    ;;
  claude)
    setup_claude "${2:-}"
    ;;
  *)
    warn "未知模板：$1"
    interactive_select
    ;;
esac
