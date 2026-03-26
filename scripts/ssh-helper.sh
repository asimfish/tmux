#!/usr/bin/env bash
# ssh-helper.sh — 密码感知 SSH 的辅助脚本
# 供 fzf preview 等不能 source common.sh 的子进程使用
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

if [[ -n "$pass" ]]; then
  exec sshpass -p "$pass" ssh "$host" "$@"
else
  exec ssh "$host" "$@"
fi
