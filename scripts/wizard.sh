#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# wizard.sh — 交互式服务器配置向导
#
# 用法：
#   bash wizard.sh              # 启动向导
#   bash wizard.sh add          # 添加服务器
#   bash wizard.sh remove       # 移除服务器
#   bash wizard.sh test         # 测试所有服务器连通性
#   bash wizard.sh ssh-setup    # 引导 SSH 免密配置

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

log()  { echo -e "${BLUE}[wizard]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

# ── 确保 servers.conf 存在 ───────────────────────────────────────
ensure_conf() {
  if [[ ! -f "$CONF_FILE" ]]; then
    cp "$REPO_DIR/servers.conf.example" "$CONF_FILE" 2>/dev/null || {
      cat > "$CONF_FILE" << 'CONF'
# servers.conf — 服务器配置文件
# 格式：别名  SSH地址  远程工作目录  描述
CONF
    }
    ok "已创建 $CONF_FILE"
  fi
}

# ── 添加服务器 ────────────────────────────────────────────────────
add_server() {
  ensure_conf

  echo -e "\n${BOLD}  添加新服务器${NC}\n"

  # 别名
  read -r -p "  服务器别名 (如 liyufeng_4090): " alias_name
  [[ -z "$alias_name" ]] && { err "别名不能为空"; return; }

  # 检查重复
  if grep -v '^\s*#' "$CONF_FILE" 2>/dev/null | grep -v '^\s*$' | awk -v a="$alias_name" '$1 == a {found=1} END{exit !found}' 2>/dev/null; then
    warn "别名 '$alias_name' 已存在"
    read -r -p "  覆盖？(y/N) " confirm
    [[ ! "$confirm" =~ ^[yY]$ ]] && return
    # 删除旧条目
    local tmp=$(mktemp)
    awk -v a="$alias_name" '$1 != a || /^[[:space:]]*#/ || /^[[:space:]]*$/' "$CONF_FILE" > "$tmp"
    mv "$tmp" "$CONF_FILE"
  fi

  # SSH 地址
  echo ""
  echo -e "  ${DIM}SSH 地址可以是：${NC}"
  echo -e "  ${DIM}  - ~/.ssh/config 中的 Host 名称（推荐）${NC}"
  echo -e "  ${DIM}  - user@ip 格式${NC}"
  echo -e "  ${DIM}  - user@ip:port 格式${NC}"
  read -r -p "  SSH 地址: " ssh_host
  [[ -z "$ssh_host" ]] && { err "SSH 地址不能为空"; return; }

  # 远程目录
  read -r -p "  远程工作目录 [~/]: " remote_dir
  [[ -z "$remote_dir" ]] && remote_dir="~"

  # 密码
  echo ""
  echo -e "  ${DIM}认证方式：公钥登录留空，密码登录输入密码${NC}"
  read -r -s -p "  SSH 密码 (公钥则直接回车): " password
  echo ""
  [[ -z "$password" ]] && password="-"

  # 描述
  read -r -p "  描述 (可选): " desc

  # 测试连通性
  echo ""
  log "测试 SSH 连通性..."
  local test_ok=false
  if [[ "$password" != "-" ]]; then
    if sshpass -p "$password" ssh -o ConnectTimeout=5 "$ssh_host" "echo ok" &>/dev/null; then
      test_ok=true
    fi
  else
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_host" "echo ok" &>/dev/null; then
      test_ok=true
    fi
  fi

  if $test_ok; then
    ok "连接成功"

    local ssh_test_cmd="ssh"
    [[ "$password" != "-" ]] && ssh_test_cmd="sshpass -p $password ssh"

    local gpu_info
    gpu_info=$($ssh_test_cmd -o ConnectTimeout=5 "$ssh_host" \
      "nvidia-smi --query-gpu=count,name --format=csv,noheader 2>/dev/null | head -1" 2>/dev/null)
    if [[ -n "$gpu_info" ]]; then
      ok "检测到 GPU：$gpu_info"
    fi

    if $ssh_test_cmd -o ConnectTimeout=5 "$ssh_host" "command -v tmux" &>/dev/null; then
      ok "tmux 已安装"
    else
      warn "服务器未安装 tmux（login 功能将降级为普通 SSH）"
    fi
  else
    warn "SSH 连接失败（可能需要配置免密登录或检查密码）"
    read -r -p "  仍然添加？(y/N) " confirm
    [[ ! "$confirm" =~ ^[yY]$ ]] && return
  fi

  # 写入配置（新格式：别名  SSH地址  目录  密码  描述）
  echo "${alias_name}    ${ssh_host}    ${remote_dir}    ${password}    ${desc}" >> "$CONF_FILE"
  ok "已添加：$alias_name → $ssh_host:$remote_dir"
  [[ "$password" != "-" ]] && ok "密码已保存（自动登录）"
  echo ""
}

# ── 移除服务器 ────────────────────────────────────────────────────
remove_server() {
  if [[ ! -f "$CONF_FILE" ]]; then
    err "没有配置文件"
    return
  fi

  local entries=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    local a=$(echo "$line" | awk '{print $1}')
    local h=$(echo "$line" | awk '{print $2}')
    local d=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i}')
    entries+="$a  $h  $d\n"
  done < "$CONF_FILE"

  if [[ -z "$entries" ]]; then
    warn "没有配置任何服务器"
    return
  fi

  local selected
  if command -v fzf &>/dev/null; then
    selected=$(echo -e "$entries" | fzf --reverse --border \
      --header="选择要移除的服务器" \
      --prompt="  ❯ ") || return
  else
    echo -e "\n$entries"
    read -r -p "输入要移除的别名: " selected
  fi

  local alias_name=$(echo "$selected" | awk '{print $1}')
  [[ -z "$alias_name" ]] && return

  read -r -p "确认移除 $alias_name？(y/N) " confirm
  [[ ! "$confirm" =~ ^[yY]$ ]] && return

  local tmp=$(mktemp)
  awk -v a="$alias_name" '($1 != a) || /^[[:space:]]*#/ || /^[[:space:]]*$/' "$CONF_FILE" > "$tmp"
  mv "$tmp" "$CONF_FILE"
  ok "已移除 $alias_name"
}

# ── 测试所有服务器 ────────────────────────────────────────────────
test_servers() {
  if [[ ! -f "$CONF_FILE" ]]; then
    err "没有配置文件"
    return
  fi

  echo -e "\n${BOLD}  测试服务器连通性${NC}\n"

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local alias_name host pass
    alias_name=$(echo "$line" | awk '{print $1}')
    host=$(echo "$line" | awk '{print $2}')
    pass=$(echo "$line" | awk '{print $4}')
    [[ "$pass" == "-" ]] && pass=""

    printf "  %-20s %-20s " "$alias_name" "$host"

    local ssh_pre="ssh"
    [[ -n "$pass" ]] && ssh_pre="sshpass -p $pass ssh"

    if $ssh_pre -o ConnectTimeout=5 "$host" "echo ok" &>/dev/null; then
      local extra=""
      local has_gpu
      has_gpu=$($ssh_pre -o ConnectTimeout=3 "$host" "command -v nvidia-smi &>/dev/null && echo yes || echo no" 2>/dev/null)
      local has_tmux
      has_tmux=$($ssh_pre -o ConnectTimeout=3 "$host" "command -v tmux &>/dev/null && echo yes || echo no" 2>/dev/null)

      [[ "$has_gpu" == "yes" ]] && extra+=" GPU"
      [[ "$has_tmux" == "yes" ]] && extra+=" tmux"

      echo -e "${GREEN}● 在线${NC}${DIM}$extra${NC}"
    else
      echo -e "${RED}● 离线${NC}"
    fi
  done < "$CONF_FILE"

  echo ""
}

# ── SSH 免密配置引导 ──────────────────────────────────────────────
ssh_setup() {
  echo -e "\n${BOLD}  SSH 免密登录配置向导${NC}\n"

  # 检查密钥
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]] && [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
    log "未找到 SSH 密钥，正在生成..."
    read -r -p "  邮箱（用于密钥注释，可回车跳过）: " email
    ssh-keygen -t ed25519 ${email:+-C "$email"} -f "$HOME/.ssh/id_ed25519"
    ok "密钥已生成"
  else
    ok "SSH 密钥已存在"
  fi

  # 创建 socket 目录
  mkdir -p "$HOME/.ssh/sockets"

  # 询问是否配置 ControlMaster
  local ssh_config="$HOME/.ssh/config"
  if ! grep -q "ControlMaster" "$ssh_config" 2>/dev/null; then
    echo ""
    read -r -p "  是否添加 SSH 连接复用配置？(Y/n) " confirm
    if [[ ! "$confirm" =~ ^[nN]$ ]]; then
      cat >> "$ssh_config" << 'SSHCONF'

# tmux-ai: SSH 连接复用
Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
    ServerAliveInterval 30
    ServerAliveCountMax 3
SSHCONF
      chmod 600 "$ssh_config"
      ok "SSH 连接复用已配置"
    fi
  else
    ok "SSH 连接复用已配置"
  fi

  # 配置服务器
  echo ""
  read -r -p "  是否现在添加服务器？(Y/n) " confirm
  if [[ ! "$confirm" =~ ^[nN]$ ]]; then
    while true; do
      echo ""
      read -r -p "  服务器 IP 或域名（回车结束）: " server_ip
      [[ -z "$server_ip" ]] && break

      read -r -p "  用户名 [$USER]: " username
      [[ -z "$username" ]] && username="$USER"

      read -r -p "  端口 [22]: " port
      [[ -z "$port" ]] && port="22"

      read -r -p "  Host 别名: " host_alias
      [[ -z "$host_alias" ]] && host_alias="$server_ip"

      # 复制公钥
      log "复制公钥到 ${username}@${server_ip}..."
      ssh-copy-id -p "$port" "${username}@${server_ip}" 2>/dev/null && ok "公钥已复制" || warn "复制失败，请手动操作"

      # 写入 ssh config
      if ! grep -q "^Host $host_alias$" "$ssh_config" 2>/dev/null; then
        cat >> "$ssh_config" << HOSTCONF

Host $host_alias
    HostName $server_ip
    User $username
    Port $port
HOSTCONF
        ok "已添加到 ~/.ssh/config: $host_alias"
      fi

      # 询问是否加入 servers.conf
      read -r -p "  添加到 servers.conf？(Y/n) " add_conf
      if [[ ! "$add_conf" =~ ^[nN]$ ]]; then
        read -r -p "  servers.conf 别名 [$host_alias]: " conf_alias
        [[ -z "$conf_alias" ]] && conf_alias="$host_alias"
        read -r -p "  远程工作目录 [~/]: " remote_dir
        [[ -z "$remote_dir" ]] && remote_dir="~"
        read -r -p "  描述: " desc

        ensure_conf
        echo "${conf_alias}    ${host_alias}    ${remote_dir}    -    ${desc}" >> "$CONF_FILE"
        ok "已添加到 servers.conf"
      fi
    done
  fi

  echo ""
  ok "SSH 配置完成！"
  echo -e "  ${DIM}现在可以使用：login --list 查看服务器${NC}"
  echo ""
}

# ── 主菜单 ────────────────────────────────────────────────────────
main_menu() {
  echo -e "\n${BOLD}  ╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}  ║      ⚙️  服务器配置向导  Wizard           ║${NC}"
  echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}\n"

  if command -v fzf &>/dev/null; then
    local selected
    selected=$(cat << 'EOF' | fzf --ansi --reverse --border=rounded --prompt="  ❯ " \
      --border-label=" ⚙️ Wizard " \
      --color="bg+:#2d2d2d,fg+:#e0e0e0,border:#3b4261,label:#7aa2f7"
add         添加新服务器
remove      移除服务器
test        测试所有服务器连通性
ssh-setup   SSH 免密登录配置向导
EOF
    ) || return

    local action=$(echo "$selected" | awk '{print $1}')
  else
    echo "  1) 添加新服务器"
    echo "  2) 移除服务器"
    echo "  3) 测试连通性"
    echo "  4) SSH 免密配置"
    echo ""
    read -r -p "  选择 (1-4): " choice
    case "$choice" in
      1) action="add" ;;
      2) action="remove" ;;
      3) action="test" ;;
      4) action="ssh-setup" ;;
      *) return ;;
    esac
  fi

  case "$action" in
    add)       add_server ;;
    remove)    remove_server ;;
    test)      test_servers ;;
    ssh-setup) ssh_setup ;;
  esac
}

# ── 入口 ──────────────────────────────────────────────────────────
case "${1:-}" in
  "")         main_menu ;;
  add)        add_server ;;
  remove)     remove_server ;;
  test)       test_servers ;;
  ssh-setup)  ssh_setup ;;
  -h|--help)
    echo -e "${BOLD}wizard.sh${NC} — 交互式服务器配置向导\n"
    echo "用法："
    echo "  wizard              主菜单"
    echo "  wizard add          添加服务器"
    echo "  wizard remove       移除服务器"
    echo "  wizard test         测试连通性"
    echo "  wizard ssh-setup    SSH 免密配置"
    ;;
  *)
    main_menu
    ;;
esac
