#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# tmux-server-status.sh — tmux 状态栏服务器指示器
# 在 tmux 状态栏中显示服务器连接状态摘要
# 用法：在 .tmux.conf 中引用：
#   set -g status-right "#(bash ~/tmux-ai/scripts/tmux-server-status.sh) ..."
#
# 输出格式示例：
#   ● 3/3   (3 台全部在线)
#   ● 2/3   (2 台在线，1 台离线)
#   ○ 0/3   (全部离线)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"
CACHE_FILE="/tmp/tmux_server_status_cache.txt"
CACHE_TTL=30

# 缓存机制：每 30 秒才真正检查一次
if [[ -f "$CACHE_FILE" ]]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo ""
  exit 0
fi

source "$SCRIPT_DIR/common.sh"
load_servers

total=${#ALIASES[@]}
online=0

for alias_name in "${ALIASES[@]}"; do
  if run_ssh "$alias_name" -o ConnectTimeout=2 "echo ok" &>/dev/null; then
    online=$((online + 1))
  fi
done

if [[ $total -eq 0 ]]; then
  result=""
elif [[ $online -eq $total ]]; then
  result="#[fg=#9ece6a]● ${online}/${total}#[default]"
elif [[ $online -eq 0 ]]; then
  result="#[fg=#f7768e]○ ${online}/${total}#[default]"
else
  result="#[fg=#e0af68]◐ ${online}/${total}#[default]"
fi

echo "$result" > "$CACHE_FILE"
echo "$result"
