#!/usr/bin/env bash
# login.sh — 快速 SSH 登录服务器并自动 attach/create tmux session
#
# 用法：
#   bash login.sh <服务器别名>
#   bash login.sh --list          # 列出所有已配置的服务器
#
# 示例：
#   bash login.sh liyufeng_4090   # SSH 到 4090 服务器，自动进入 tmux
#   bash login.sh --list          # 查看可用服务器列表

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${BLUE}[login]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"

# ── 解析配置文件 ──────────────────────────────────────────────────
# 格式：别名  SSH地址  远程工作目录  密码(-表示无)  描述...
parse_server() {
  local alias="$1"
  if [[ ! -f "$CONF_FILE" ]]; then
    err "找不到配置文件：$CONF_FILE\n  请复制 servers.conf.example 为 servers.conf 并配置你的服务器"
  fi

  local line
  line=$(grep -v '^\s*#' "$CONF_FILE" | grep -v '^\s*$' | awk -v a="$alias" '$1 == a {print; exit}')

  if [[ -z "$line" ]]; then
    err "未找到服务器 '$alias'\n  运行 login.sh --list 查看可用服务器"
  fi

  SSH_HOST=$(echo "$line" | awk '{print $2}')
  REMOTE_DIR=$(echo "$line" | awk '{print $3}')
  SERVER_PASS=$(echo "$line" | awk '{print $4}')
  SERVER_DESC=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

  [[ -z "$SSH_HOST" ]] && err "配置格式错误：缺少 SSH 地址"
  [[ -z "$REMOTE_DIR" ]] && REMOTE_DIR="~"
  [[ "$SERVER_PASS" == "-" ]] && SERVER_PASS=""
}

# ── 列出所有服务器 ────────────────────────────────────────────────
list_servers() {
  if [[ ! -f "$CONF_FILE" ]]; then
    err "找不到配置文件：$CONF_FILE\n  请复制 servers.conf.example 为 servers.conf 并配置你的服务器"
  fi

  echo -e "\n${BOLD}已配置的服务器：${NC}\n"
  printf "  ${DIM}%-18s %-22s %-15s %-8s %s${NC}\n" "别名" "SSH地址" "工作目录" "认证" "描述"
  printf "  ${DIM}%-18s %-22s %-15s %-8s %s${NC}\n" "──────────────────" "──────────────────────" "───────────────" "────────" "──────────"

  local count=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local alias ssh_host remote_dir pass desc auth_label
    alias=$(echo "$line" | awk '{print $1}')
    ssh_host=$(echo "$line" | awk '{print $2}')
    remote_dir=$(echo "$line" | awk '{print $3}')
    pass=$(echo "$line" | awk '{print $4}')
    desc=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

    if [[ "$pass" == "-" || -z "$pass" ]]; then
      auth_label="${GREEN}🔑 公钥${NC}"
    else
      auth_label="${YELLOW}🔒 密码${NC}"
    fi

    printf "  ${CYAN}%-18s${NC} %-22s %-15s " "$alias" "$ssh_host" "$remote_dir"
    echo -en "$auth_label"
    printf "  ${DIM}%s${NC}\n" "$desc"
    count=$((count + 1))
  done < "$CONF_FILE"

  if [[ $count -eq 0 ]]; then
    warn "未配置任何服务器，请编辑 $CONF_FILE"
  fi

  echo ""
  echo -e "  ${DIM}用法：login <别名>${NC}"
  echo ""
}

# ── 构建 SSH 命令（自动处理密码）──────────────────────────────────
build_ssh_cmd() {
  if [[ -n "$SERVER_PASS" ]]; then
    if ! command -v sshpass &>/dev/null; then
      err "需要 sshpass 来自动输入密码\n  安装：brew install sshpass 或 brew install esolitos/ipa/sshpass"
    fi
    SSH_CMD=(sshpass -p "$SERVER_PASS" ssh)
  else
    SSH_CMD=(ssh)
  fi
}

# ── 连接服务器 ────────────────────────────────────────────────────
connect_server() {
  local alias="$1"
  parse_server "$alias"
  build_ssh_cmd

  local tmux_session="$alias"

  log "连接到 ${BOLD}$alias${NC} (${SSH_HOST})..."
  [[ -n "$SERVER_DESC" ]] && log "描述：$SERVER_DESC"
  [[ -n "$SERVER_PASS" ]] && log "认证方式：${YELLOW}自动密码${NC}"

  local remote_path="$REMOTE_DIR"
  if [[ "$remote_path" == ~* ]]; then
    local remote_home
    remote_home=$("${SSH_CMD[@]}" -o ConnectTimeout=10 "$SSH_HOST" 'echo $HOME' 2>/dev/null) \
      || err "无法连接到 $SSH_HOST，请检查 SSH 配置"
    remote_path="${remote_path/#~/$remote_home}"
  fi

  log "远程工作目录：$remote_path"
  log "远程 tmux session：$tmux_session"

  "${SSH_CMD[@]}" -t "$SSH_HOST" "
    cd $remote_path 2>/dev/null || cd ~
    if command -v tmux &>/dev/null; then
      if tmux has-session -t '$tmux_session' 2>/dev/null; then
        echo '[login] 恢复已有 tmux session: $tmux_session'
        exec tmux attach-session -t '$tmux_session'
      else
        echo '[login] 创建新 tmux session: $tmux_session'
        exec tmux new-session -s '$tmux_session'
      fi
    else
      echo '[login] 服务器未安装 tmux，进入普通 shell'
      exec \$SHELL
    fi
  "
}

# ── fzf 交互选择 ──────────────────────────────────────────────────
fzf_select() {
  if ! command -v fzf &>/dev/null; then
    err "需要 fzf，请先安装：brew install fzf"
  fi

  if [[ ! -f "$CONF_FILE" ]]; then
    err "找不到配置文件：$CONF_FILE"
  fi

  local entries=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local alias ssh_host remote_dir pass desc
    alias=$(echo "$line" | awk '{print $1}')
    ssh_host=$(echo "$line" | awk '{print $2}')
    remote_dir=$(echo "$line" | awk '{print $3}')
    pass=$(echo "$line" | awk '{print $4}')
    desc=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

    local auth_mark=""
    [[ "$pass" != "-" && -n "$pass" ]] && auth_mark="🔒"

    entries+="$(printf "%-18s  %-20s  %-15s  %s %s" "$alias" "$ssh_host" "$remote_dir" "$auth_mark" "$desc")\n"
  done < "$CONF_FILE"

  if [[ -z "$entries" ]]; then
    err "没有配置任何服务器"
  fi

  local helper="$SCRIPT_DIR/ssh-helper.sh"

  local selected
  selected=$(echo -e "$entries" | fzf \
    --ansi \
    --reverse \
    --border=rounded \
    --border-label=" 🔗 Quick Login " \
    --border-label-pos=3 \
    --header="  选择服务器  →  SSH + tmux (🔒=密码自动)" \
    --prompt="  ❯ " \
    --pointer="▶" \
    --color="bg+:#2d2d2d,fg+:#e0e0e0,hl:#ff9e64,hl+:#ff9e64,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,border:#3b4261,label:#7aa2f7" \
    --preview="
      alias=\$(echo {} | awk '{print \$1}')
      echo -e '\033[1;35m═══ \$alias ═══\033[0m'
      echo ''
      echo -e '\033[2mProbing...\033[0m'
      if bash '$helper' \"\$alias\" -o ConnectTimeout=3 'echo ONLINE' 2>/dev/null | grep -q ONLINE; then
        echo -e '\033[32m● Online\033[0m'
        echo ''
        gpu=\$(bash '$helper' \"\$alias\" -o ConnectTimeout=3 'nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null' 2>/dev/null)
        if [ -n \"\$gpu\" ]; then
          echo -e '\033[1mGPU:\033[0m'
          echo \"\$gpu\"
          echo ''
        fi
        sess=\$(bash '$helper' \"\$alias\" -o ConnectTimeout=3 'tmux list-sessions 2>/dev/null' 2>/dev/null)
        if [ -n \"\$sess\" ]; then
          echo -e '\033[1mtmux sessions:\033[0m'
          echo \"\$sess\"
        fi
      else
        echo -e '\033[31m● Offline\033[0m'
      fi
    " \
    --preview-window="right:45%:wrap:border-left" \
  ) || true

  if [[ -n "$selected" ]]; then
    local chosen_alias
    chosen_alias=$(echo "$selected" | awk '{print $1}')
    connect_server "$chosen_alias"
  fi
}

# ── 主入口 ────────────────────────────────────────────────────────
case "${1:-}" in
  ""|"-h"|"--help")
    if command -v fzf &>/dev/null && [[ -f "$CONF_FILE" ]]; then
      fzf_select
    else
      echo -e "\n${BOLD}login.sh${NC} — 快速 SSH 登录服务器并自动进入 tmux\n"
      echo "用法："
      echo "  login <服务器别名>    SSH 登录并 attach/create tmux session"
      echo "  login --list         列出所有已配置的服务器"
      echo "  login --fzf          fzf 交互选择"
      echo ""
      echo "配置文件：$CONF_FILE"
      echo ""
    fi
    ;;
  "--fzf"|"-f")
    fzf_select
    ;;
  "--list"|"-l")
    list_servers
    ;;
  *)
    connect_server "$1"
    ;;
esac
