#!/usr/bin/env bash
# common.sh — 所有脚本共用的函数库
# 用法：source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# 提供：
#   load_servers     — 读取 servers.conf 到 ALIASES/HOSTS/PASSWORDS/DESCS 数组
#   run_ssh <alias> <args...> — 直接运行 SSH 命令
#   get_ssh_prefix <alias>   — 返回 ssh 命令前缀字符串
#   ensure_frp       — 检测并自动启动 frp 客户端（如需要）

# bash 4+ 才支持 declare -A（在 source 时由调用方负责版本检查）

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_REPO_DIR="$(dirname "$COMMON_SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$COMMON_REPO_DIR/servers.conf}"

# frp 配置（可通过环境变量覆盖）
FRP_DIR="${FRP_DIR:-$HOME/Desktop/agent/frp/psi_frp_config}"
FRP_CONF="${FRP_CONF:-visitors.toml}"

declare -a ALIASES=() 2>/dev/null || ALIASES=()
declare -A HOSTS=() 2>/dev/null || true
declare -A PASSWORDS=() 2>/dev/null || true
declare -A DESCS=() 2>/dev/null || true
declare -A REMOTEDIRS=() 2>/dev/null || true

# 检测 frp 是否在运行，没有则自动后台启动
ensure_frp() {
  # 如果 frpc 已经在跑，直接返回
  if pgrep -f "frpc.*${FRP_CONF}" &>/dev/null; then
    return 0
  fi

  # 检查 frpc 可执行文件
  local frpc_bin="${FRP_DIR}/frpc"
  if [[ ! -x "$frpc_bin" ]]; then
    echo -e "\033[0;33m⚠ frpc 未找到: ${frpc_bin}\033[0m" >&2
    return 1
  fi

  # 检查配置文件
  local frpc_conf="${FRP_DIR}/${FRP_CONF}"
  if [[ ! -f "$frpc_conf" ]]; then
    echo -e "\033[0;33m⚠ frp 配置未找到: ${frpc_conf}\033[0m" >&2
    return 1
  fi

  echo -e "\033[0;36m🔗 frpc 未运行，正在自动启动...\033[0m" >&2
  cd "$FRP_DIR" && nohup "$frpc_bin" -c "$FRP_CONF" >> /tmp/frpc.log 2>&1 &
  local frpc_pid=$!

  # 等待 frpc 启动并建立连接（最多 8 秒）
  local waited=0
  while [[ $waited -lt 8 ]]; do
    sleep 1
    waited=$((waited + 1))
    # 检查进程还在
    if ! kill -0 "$frpc_pid" 2>/dev/null; then
      echo -e "\033[0;31m✗ frpc 启动失败，查看 /tmp/frpc.log\033[0m" >&2
      return 1
    fi
    # 检查端口是否已监听（6000 或 6100）
    if lsof -i :6000 -sTCP:LISTEN &>/dev/null || lsof -i :6100 -sTCP:LISTEN &>/dev/null; then
      echo -e "\033[0;32m✓ frpc 已启动 (PID ${frpc_pid})，隧道就绪\033[0m" >&2
      return 0
    fi
  done

  echo -e "\033[0;33m⚠ frpc 已启动 (PID ${frpc_pid})，但隧道可能还在建立中\033[0m" >&2
  return 0
}

# 读取 servers.conf：别名  SSH地址  远程工作目录  密码(-表示无)  描述...
load_servers() {
  local filter="${1:-}"
  ALIASES=()
  HOSTS=()
  PASSWORDS=()
  DESCS=()
  REMOTEDIRS=()

  if [[ ! -f "$CONF_FILE" ]]; then
    return 1
  fi

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local a h d p rd
    a=$(echo "$line" | awk '{print $1}')
    h=$(echo "$line" | awk '{print $2}')
    rd=$(echo "$line" | awk '{print $3}')
    p=$(echo "$line" | awk '{print $4}')
    d=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

    if [[ -n "$filter" && "$a" != "$filter" ]]; then
      continue
    fi

    [[ "$p" == "-" || -z "$p" ]] && p=""

    ALIASES+=("$a")
    HOSTS["$a"]="$h"
    PASSWORDS["$a"]="$p"
    DESCS["$a"]="$d"
    REMOTEDIRS["$a"]="${rd:-~}"
  done < "$CONF_FILE"

  # 如果配置中包含需要 frp 隧道的服务器，自动确保 frpc 在运行
  # 检测方式：看 SSH config 里是否有指向 127.0.0.1 的端口转发
  local need_frp=false
  for a in "${ALIASES[@]}"; do
    local h="${HOSTS[$a]}"
    if ssh -G "$h" 2>/dev/null | grep -qi "^hostname 127.0.0.1"; then
      need_frp=true
      break
    fi
  done
  if $need_frp; then
    ensure_frp
  fi
}

# 运行 SSH 命令，自动处理密码
# run_ssh <alias> [ssh_options...] [-- remote_command]
run_ssh() {
  local alias_name="$1"
  shift
  local host="${HOSTS[$alias_name]}"
  local pass="${PASSWORDS[$alias_name]:-}"

  if [[ -n "$pass" ]]; then
    sshpass -p "$pass" ssh "$host" "$@"
  else
    ssh "$host" "$@"
  fi
}

# 为需要后台/并行执行的场景，构造完整命令前缀
# 返回：ssh 命令数组
get_ssh_prefix() {
  local alias_name="$1"
  local pass="${PASSWORDS[$alias_name]:-}"

  if [[ -n "$pass" ]]; then
    echo "sshpass -p $pass ssh"
  else
    echo "ssh"
  fi
}
