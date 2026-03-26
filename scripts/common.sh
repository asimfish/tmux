#!/usr/bin/env bash
# common.sh — 所有脚本共用的函数库
# 用法：source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# 提供：
#   load_servers     — 读取 servers.conf 到 ALIASES/HOSTS/PASSWORDS/DESCS 数组
#   run_ssh <alias> <args...> — 直接运行 SSH 命令
#   get_ssh_prefix <alias>   — 返回 ssh 命令前缀字符串

# bash 4+ 才支持 declare -A（在 source 时由调用方负责版本检查）

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_REPO_DIR="$(dirname "$COMMON_SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$COMMON_REPO_DIR/servers.conf}"

declare -a ALIASES=() 2>/dev/null || ALIASES=()
declare -A HOSTS=() 2>/dev/null || true
declare -A PASSWORDS=() 2>/dev/null || true
declare -A DESCS=() 2>/dev/null || true
declare -A REMOTEDIRS=() 2>/dev/null || true

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
