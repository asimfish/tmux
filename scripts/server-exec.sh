#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# server-exec.sh — 在多台服务器上并行执行命令
#
# 用法：
#   bash server-exec.sh "nvidia-smi"                 # 所有服务器执行
#   bash server-exec.sh -s liyufeng_4090 "nvidia-smi" # 指定服务器
#   bash server-exec.sh --all "df -h"                # 显式所有服务器
#   bash server-exec.sh -i                           # 交互模式
#
# 内置快捷命令：
#   bash server-exec.sh gpu          # nvidia-smi
#   bash server-exec.sh mem          # free -h
#   bash server-exec.sh disk         # df -h
#   bash server-exec.sh procs        # 查看 python 进程
#   bash server-exec.sh who          # 查看登录用户
#   bash server-exec.sh tmux-ls      # 远程 tmux sessions

set +e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"
SSH_TIMEOUT=10
TARGET_SERVERS=()
COMMAND=""
INTERACTIVE=false
PARALLEL=true

# ── 内置快捷命令 ──────────────────────────────────────────────────
declare -A SHORTCUTS=(
  [gpu]="nvidia-smi"
  [mem]="free -h 2>/dev/null || vm_stat 2>/dev/null"
  [disk]="df -h ~"
  [procs]="ps aux | grep -E 'python|train|torch' | grep -v grep | head -20"
  [who]="who"
  [tmux-ls]="tmux list-sessions 2>/dev/null || echo 'no tmux sessions'"
  [uptime]="uptime"
  [top5]="ps aux --sort=-%mem 2>/dev/null | head -6 || ps aux | head -6"
  [gpu-procs]="nvidia-smi --query-compute-apps=pid,used_memory,name --format=csv,noheader 2>/dev/null || echo 'no GPU or no processes'"
  [conda]="conda env list 2>/dev/null || echo 'no conda'"
)

# ── 参数解析 ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--server)   TARGET_SERVERS+=("$2"); shift 2 ;;
    --all)         shift ;;
    -i|--interactive) INTERACTIVE=true; shift ;;
    --seq)         PARALLEL=false; shift ;;
    -h|--help)
      echo -e "${BOLD}server-exec.sh${NC} — 在多台服务器上并行执行命令\n"
      echo "用法："
      echo "  server-exec \"<命令>\"                    所有服务器执行"
      echo "  server-exec -s <别名> \"<命令>\"          指定服务器"
      echo "  server-exec -i                           交互模式"
      echo ""
      echo "快捷命令："
      for key in $(echo "${!SHORTCUTS[@]}" | tr ' ' '\n' | sort); do
        printf "  %-12s %s\n" "$key" "${SHORTCUTS[$key]}"
      done
      exit 0
      ;;
    *)
      # 检查是否是快捷命令
      if [[ -n "${SHORTCUTS[$1]:-}" ]]; then
        COMMAND="${SHORTCUTS[$1]}"
      else
        COMMAND="$1"
      fi
      shift
      ;;
  esac
done

# ── 检查配置 ──────────────────────────────────────────────────────
if [[ ! -f "$CONF_FILE" ]]; then
  echo -e "${RED}[✗]${NC} 找不到配置文件：$CONF_FILE"
  exit 1
fi

# ── 读取服务器列表（使用 common.sh）──────────────────────────────
source "$SCRIPT_DIR/common.sh"
load_servers
ALL_ALIASES=("${ALIASES[@]}")

# 如果没指定服务器，默认全部
if [[ ${#TARGET_SERVERS[@]} -eq 0 ]]; then
  TARGET_SERVERS=("${ALL_ALIASES[@]}")
fi

# ── 交互模式 ──────────────────────────────────────────────────────
if $INTERACTIVE; then
  echo -e "\n${BOLD}  服务器命令执行器${NC}\n"

  # 选服务器
  if command -v fzf &>/dev/null; then
    entries=""
    for a in "${ALL_ALIASES[@]}"; do
      entries+="$a  ${HOSTS[$a]}  ${DESCS[$a]}\n"
    done

    selected=$(echo -e "$entries" | fzf --multi --reverse --border \
      --header="选择服务器（Tab 多选，Enter 确认）" \
      --prompt="  ❯ " \
      --color="bg+:#2d2d2d,fg+:#e0e0e0,border:#3b4261") || exit 0

    TARGET_SERVERS=()
    while IFS= read -r line; do
      TARGET_SERVERS+=($(echo "$line" | awk '{print $1}'))
    done <<< "$selected"
  fi

  echo -e "  ${DIM}已选择 ${#TARGET_SERVERS[@]} 台服务器${NC}\n"

  # 选命令
  echo -e "  ${BOLD}快捷命令：${NC}"
  for key in $(echo "${!SHORTCUTS[@]}" | tr ' ' '\n' | sort); do
    printf "    ${CYAN}%-12s${NC} %s\n" "$key" "${SHORTCUTS[$key]}"
  done
  echo ""
  read -r -p "  输入命令（或快捷名）: " input

  if [[ -n "${SHORTCUTS[$input]:-}" ]]; then
    COMMAND="${SHORTCUTS[$input]}"
  else
    COMMAND="$input"
  fi
fi

# ── 检查命令 ──────────────────────────────────────────────────────
if [[ -z "$COMMAND" ]]; then
  echo -e "${RED}[✗]${NC} 请指定要执行的命令"
  echo "  用法：server-exec \"<命令>\""
  exit 1
fi

# ── 执行 ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}命令：${NC}${CYAN}$COMMAND${NC}"
echo -e "  ${BOLD}目标：${NC}${#TARGET_SERVERS[@]} 台服务器"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

exec_on_server() {
  local alias_name="$1"
  local host="${HOSTS[$alias_name]}"
  local tmpfile="/tmp/server_exec_${alias_name}_$$.txt"

  local result ssh_pre
  ssh_pre=$(get_ssh_prefix "$alias_name")
  result=$($ssh_pre -o ConnectTimeout=$SSH_TIMEOUT "$host" "$COMMAND" 2>&1) || true

  if [[ -z "$result" ]]; then
    result="(no output)"
  fi

  echo "$result" > "$tmpfile"
}

if $PARALLEL; then
  pids=()
  for alias_name in "${TARGET_SERVERS[@]}"; do
    exec_on_server "$alias_name" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
fi

# 输出结果
for alias_name in "${TARGET_SERVERS[@]}"; do
  host="${HOSTS[$alias_name]}"
  tmpfile="/tmp/server_exec_${alias_name}_$$.txt"

  if ! $PARALLEL; then
    exec_on_server "$alias_name"
  fi

  echo -e "${MAGENTA}┌─${NC} ${BOLD}$alias_name${NC} ${DIM}($host)${NC}"

  if [[ -f "$tmpfile" ]]; then
    while IFS= read -r line; do
      echo -e "${MAGENTA}│${NC} $line"
    done < "$tmpfile"
    rm -f "$tmpfile"
  else
    echo -e "${MAGENTA}│${NC} ${RED}执行失败或超时${NC}"
  fi

  echo -e "${MAGENTA}└─${NC}"
  echo ""
done
