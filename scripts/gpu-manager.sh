#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# gpu-manager.sh — 多服务器 GPU 进程管理器
#
# 用法：
#   bash gpu-manager.sh                  # fzf 交互式查看所有 GPU 进程
#   bash gpu-manager.sh --list           # 列出所有服务器的 GPU 进程
#   bash gpu-manager.sh --free           # 找到空闲 GPU
#   bash gpu-manager.sh --kill <服务器> <PID>  # 远程 kill 进程

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
SSH_TIMEOUT=8

# ── 读取服务器列表（使用 common.sh）──────────────────────────────
source "$SCRIPT_DIR/common.sh"

if [[ ! -f "$CONF_FILE" ]]; then
  echo -e "${RED}[✗]${NC} 找不到配置文件：$CONF_FILE"
  exit 1
fi

load_servers

# ── 采集 GPU 信息 ────────────────────────────────────────────────
collect_gpu_info() {
  local alias_name="$1"
  local host="${HOSTS[$alias_name]}"
  local tmpfile="/tmp/gpu_manager_${alias_name}.txt"

  local ssh_pre
  ssh_pre=$(get_ssh_prefix "$alias_name")
  $ssh_pre -o ConnectTimeout=$SSH_TIMEOUT "$host" bash -s 2>/dev/null << 'GPU_SCRIPT' > "$tmpfile" || echo "OFFLINE" > "$tmpfile"
if ! command -v nvidia-smi &>/dev/null; then
  echo "NO_GPU"
  exit 0
fi

# GPU 卡信息
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu \
  --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r idx name util mu mt temp; do
  idx=$(echo "$idx" | xargs); name=$(echo "$name" | xargs)
  util=$(echo "$util" | xargs); mu=$(echo "$mu" | xargs)
  mt=$(echo "$mt" | xargs); temp=$(echo "$temp" | xargs)
  echo "CARD|$idx|$name|$util|$mu|$mt|$temp"
done

# GPU 进程
nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory,name \
  --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r uuid pid mem pname; do
  uuid=$(echo "$uuid" | xargs); pid=$(echo "$pid" | xargs)
  mem=$(echo "$mem" | xargs); pname=$(echo "$pname" | xargs)
  gpu_idx=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader 2>/dev/null | grep "$uuid" | cut -d',' -f1 | xargs)
  # 进程详情
  user=$(ps -o user= -p "$pid" 2>/dev/null | xargs)
  runtime=$(ps -o etime= -p "$pid" 2>/dev/null | xargs)
  echo "PROC|${gpu_idx:-?}|$pid|$mem|$pname|${user:-?}|${runtime:-?}"
done
GPU_SCRIPT
}

# ── 列出所有 GPU 进程 ────────────────────────────────────────────
list_all() {
  echo -e "\n${BOLD}  ╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}  ║      🎮  GPU 进程管理器  GPU Manager              ║${NC}"
  echo -e "${BOLD}  ╚═══════════════════════════════════════════════════╝${NC}"
  echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}\n"

  # 并行采集
  local pids=()
  for alias_name in "${ALIASES[@]}"; do
    collect_gpu_info "$alias_name" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  for alias_name in "${ALIASES[@]}"; do
    local host="${HOSTS[$alias_name]}"
    local tmpfile="/tmp/gpu_manager_${alias_name}.txt"

    if grep -q "OFFLINE" "$tmpfile" 2>/dev/null; then
      echo -e "  ${RED}●${NC} ${BOLD}$alias_name${NC} ${DIM}($host)${NC} — ${RED}OFFLINE${NC}"
      echo ""
      continue
    fi

    if grep -q "NO_GPU" "$tmpfile" 2>/dev/null; then
      echo -e "  ${DIM}○${NC} ${BOLD}$alias_name${NC} ${DIM}($host)${NC} — ${DIM}no GPU${NC}"
      echo ""
      continue
    fi

    echo -e "  ${GREEN}●${NC} ${BOLD}$alias_name${NC} ${DIM}($host)${NC}"

    # GPU 卡总览
    grep "^CARD|" "$tmpfile" 2>/dev/null | while IFS='|' read -r _ idx name util mu mt temp; do
      name=$(echo "$name" | xargs)
      util=$(echo "${util:-0}" | tr -cd '0-9'); util=${util:-0}
      mu=$(echo "${mu:-0}" | tr -cd '0-9'); mu=${mu:-0}
      mt=$(echo "${mt:-1}" | tr -cd '0-9'); mt=${mt:-1}
      local mem_pct=0
      [[ $mt -gt 0 ]] && mem_pct=$((mu * 100 / mt))
      local mu_g=$(echo "scale=1; $mu / 1024" | bc 2>/dev/null || echo "$mu")
      local mt_g=$(echo "scale=1; $mt / 1024" | bc 2>/dev/null || echo "$mt")

      local util_color="$GREEN"
      [[ ${util:-0} -ge 50 ]] && util_color="$YELLOW"
      [[ ${util:-0} -ge 80 ]] && util_color="$RED"

      echo -e "    [${idx}] ${CYAN}${name}${NC}  ${util_color}${util:-0}%${NC}  ${mu_g}/${mt_g}G (${mem_pct}%)  ${temp:-?}°C"
    done

    # 进程列表
    local procs
    procs=$(grep "^PROC|" "$tmpfile" 2>/dev/null)
    if [[ -n "$procs" ]]; then
      echo ""
      printf "    ${DIM}%-5s %-8s %-8s %-10s %-30s %-10s %s${NC}\n" "GPU" "PID" "User" "Memory" "Process" "Runtime" ""
      printf "    ${DIM}%-5s %-8s %-8s %-10s %-30s %-10s %s${NC}\n" "───" "────────" "────────" "──────────" "──────────────────────────────" "──────────" ""
      while IFS='|' read -r _ gpu_idx pid mem pname user runtime; do
        local mem_display="${mem} MiB"
        printf "    [%-2s] %-8s %-8s %-10s %-30s %s\n" "$gpu_idx" "$pid" "$user" "$mem_display" "${pname:0:30}" "$runtime"
      done <<< "$procs"
    else
      echo -e "    ${DIM}(无 GPU 进程)${NC}"
    fi

    echo ""
  done
}

# ── 查找空闲 GPU ─────────────────────────────────────────────────
find_free() {
  echo -e "\n${BOLD}  🔍 空闲 GPU 搜索${NC}\n"

  local pids=()
  for alias_name in "${ALIASES[@]}"; do
    collect_gpu_info "$alias_name" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  local found=false
  for alias_name in "${ALIASES[@]}"; do
    local host="${HOSTS[$alias_name]}"
    local tmpfile="/tmp/gpu_manager_${alias_name}.txt"

    [[ ! -f "$tmpfile" ]] && continue
    grep -q "OFFLINE\|NO_GPU" "$tmpfile" 2>/dev/null && continue

    grep "^CARD|" "$tmpfile" 2>/dev/null | while IFS='|' read -r _ idx name util mu mt temp; do
      util=${util// /}
      mu=${mu// /}
      local mem_pct=0
      [[ $mt -gt 0 ]] 2>/dev/null && mem_pct=$((mu * 100 / mt))

      # 空闲判断：使用率 < 10% 且显存占用 < 20%
      if [[ ${util:-0} -lt 10 ]] && [[ $mem_pct -lt 20 ]] 2>/dev/null; then
        name=$(echo "$name" | xargs)
        local mt_g=$(echo "scale=0; $mt / 1024" | bc 2>/dev/null || echo "$mt")
        echo -e "  ${GREEN}✓${NC} ${BOLD}$alias_name${NC}:GPU[$idx]  ${CYAN}${name}${NC}  ${mt_g}G  ${GREEN}空闲${NC}"
        echo -e "    ${DIM}登录：login $alias_name${NC}"
        found=true
      fi
    done
  done

  if ! $found; then
    echo -e "  ${YELLOW}没有找到空闲的 GPU${NC}"
  fi

  echo ""
}

# ── 远程 kill ────────────────────────────────────────────────────
remote_kill() {
  local alias_name="$1"
  local pid="$2"
  local host="${HOSTS[$alias_name]:-}"

  if [[ -z "$host" ]]; then
    echo -e "${RED}[✗]${NC} 未知服务器：$alias_name"
    exit 1
  fi

  echo -e "${YELLOW}[!]${NC} 将在 ${BOLD}$alias_name${NC} ($host) 上 kill 进程 $pid"
  read -r -p "确认？(y/N) " confirm
  if [[ "$confirm" =~ ^[yY]$ ]]; then
    run_ssh "$alias_name" -o ConnectTimeout=$SSH_TIMEOUT "kill $pid" 2>/dev/null \
      && echo -e "${GREEN}[✓]${NC} 已发送 kill 信号" \
      || echo -e "${RED}[✗]${NC} kill 失败"
  fi
}

# ── fzf 交互模式 ─────────────────────────────────────────────────
interactive_mode() {
  echo -e "${DIM}采集 GPU 信息...${NC}"

  local pids=()
  for alias_name in "${ALIASES[@]}"; do
    collect_gpu_info "$alias_name" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # 构建 fzf 条目
  local entries=""
  for alias_name in "${ALIASES[@]}"; do
    local tmpfile="/tmp/gpu_manager_${alias_name}.txt"
    [[ ! -f "$tmpfile" ]] && continue
    grep -q "OFFLINE\|NO_GPU" "$tmpfile" 2>/dev/null && continue

    local procs
    procs=$(grep "^PROC|" "$tmpfile" 2>/dev/null)
    if [[ -n "$procs" ]]; then
      while IFS='|' read -r _ gpu_idx pid mem pname user runtime; do
        entries+="$(printf "%-16s GPU[%-2s] PID:%-8s %6s MiB  %-8s %-30s %s" \
          "$alias_name" "$gpu_idx" "$pid" "$mem" "$user" "${pname:0:30}" "$runtime")\n"
      done <<< "$procs"
    fi
  done

  if [[ -z "$entries" ]]; then
    echo -e "${GREEN}[✓]${NC} 没有 GPU 进程在运行"
    return
  fi

  if ! command -v fzf &>/dev/null; then
    echo -e "$entries"
    return
  fi

  local selected
  selected=$(echo -e "$entries" | fzf \
    --ansi --reverse --border=rounded \
    --border-label=" 🎮 GPU Processes " \
    --header="Enter=kill  Esc=退出" \
    --prompt="  ❯ " \
    --color="bg+:#2d2d2d,fg+:#e0e0e0,border:#3b4261,label:#7aa2f7" \
  ) || return

  if [[ -n "$selected" ]]; then
    local sel_alias sel_pid
    sel_alias=$(echo "$selected" | awk '{print $1}')
    sel_pid=$(echo "$selected" | grep -o 'PID:[0-9]*' | cut -d: -f2)

    if [[ -n "$sel_alias" ]] && [[ -n "$sel_pid" ]]; then
      remote_kill "$sel_alias" "$sel_pid"
    fi
  fi
}

# ── 主入口 ────────────────────────────────────────────────────────
case "${1:-}" in
  "")
    if command -v fzf &>/dev/null; then
      interactive_mode
    else
      list_all
    fi
    ;;
  --list|-l)
    list_all
    ;;
  --free|-f)
    find_free
    ;;
  --kill|-k)
    [[ $# -lt 3 ]] && { echo "用法：gpu-manager --kill <服务器别名> <PID>"; exit 1; }
    remote_kill "$2" "$3"
    ;;
  -h|--help)
    echo -e "${BOLD}gpu-manager.sh${NC} — 多服务器 GPU 进程管理器\n"
    echo "用法："
    echo "  gpu-manager              fzf 交互式查看 + kill"
    echo "  gpu-manager --list       列出所有 GPU 进程"
    echo "  gpu-manager --free       查找空闲 GPU"
    echo "  gpu-manager --kill <服务器> <PID>"
    ;;
  *)
    list_all
    ;;
esac
