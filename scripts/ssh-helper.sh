#!/usr/bin/env bash
# ssh-helper.sh — 密码感知 SSH 的辅助脚本
# 供 fzf preview 等不能 source common.sh 的子进程使用
# 自动检测并启动 frp（如需要）
#
# 用法：
#   bash ssh-helper.sh <别名> <ssh参数...>
#   bash ssh-helper.sh liyufeng_4090 -o ConnectTimeout=3 "echo ok"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"

alias_name="$1"
shift

if [[ ! -f "$CONF_FILE" || -z "$alias_name" ]]; then
  exit 1
fi

line=$(grep -v '^\s*#' "$CONF_FILE" | grep -v '^\s*$' | awk -v a="$alias_name" '$1 == a {print; exit}')
[[ -z "$line" ]] && exit 1

host=$(echo "$line" | awk '{print $2}')
pass=$(echo "$line" | awk '{print $4}')
[[ "$pass" == "-" ]] && pass=""

# 如果目标是 127.0.0.1（frp 隧道），确保 frpc 在运行
if ssh -G "$host" 2>/dev/null | grep -qi "^hostname 127.0.0.1"; then
  FRP_DIR="${FRP_DIR:-$HOME/Desktop/agent/frp/psi_frp_config}"
  FRP_CONF="${FRP_CONF:-visitors.toml}"
  if ! pgrep -f "frpc.*${FRP_CONF}" &>/dev/null; then
    if [[ -x "${FRP_DIR}/frpc" && -f "${FRP_DIR}/${FRP_CONF}" ]]; then
      cd "$FRP_DIR" && nohup "./frpc" -c "$FRP_CONF" >> /tmp/frpc.log 2>&1 &
      sleep 3
    fi
  fi
fi

if [[ -n "$pass" ]]; then
  exec sshpass -p "$pass" ssh "$host" "$@"
else
  exec ssh "$host" "$@"
fi
