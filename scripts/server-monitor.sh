#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# server-monitor.sh — 多服务器资源监控面板
#
# 用法：
#   bash server-monitor.sh              # 持续刷新监控所有服务器
#   bash server-monitor.sh --once       # 只查询一次
#   bash server-monitor.sh --interval 5 # 每 5 秒刷新
#   bash server-monitor.sh <别名>       # 只监控指定服务器
#
# 显示内容：GPU 使用率/显存、CPU、内存、磁盘、运行中的 tmux session

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
INTERVAL=10
ONCE=false
COMPACT=false
FILTER_ALIAS=""
SSH_TIMEOUT=8
SHOW_PROCS=false

# ── 参数解析 ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)       ONCE=true; shift ;;
    --interval)   INTERVAL="$2"; shift 2 ;;
    --compact)    COMPACT=true; shift ;;
    --procs)      SHOW_PROCS=true; shift ;;
    -h|--help)
      echo "用法: server-monitor.sh [--once] [--interval N] [--compact] [--procs] [别名]"
      echo ""
      echo "选项："
      echo "  --once       只查询一次"
      echo "  --interval N 刷新间隔（秒）"
      echo "  --compact    紧凑模式（单行每服务器）"
      echo "  --procs      显示 GPU 上的进程"
      exit 0
      ;;
    *)            FILTER_ALIAS="$1"; shift ;;
  esac
done

# ── 检查配置 ──────────────────────────────────────────────────────
if [[ ! -f "$CONF_FILE" ]]; then
  echo -e "${RED}[✗]${NC} 找不到配置文件：$CONF_FILE"
  echo "  请复制 servers.conf.example 为 servers.conf 并配置你的服务器"
  exit 1
fi

# ── 读取服务器列表（使用 common.sh）──────────────────────────────
source "$SCRIPT_DIR/common.sh"
load_servers "$FILTER_ALIAS"

if [[ ${#ALIASES[@]} -eq 0 ]]; then
  echo -e "${RED}[✗]${NC} 没有匹配的服务器"
  exit 1
fi

# ── 进度条渲染 ────────────────────────────────────────────────────
bar() {
  local pct=${1:-0}
  local width=${2:-20}
  local filled=$((pct * width / 100))
  local empty=$((width - filled))

  local color="$GREEN"
  [[ $pct -ge 50 ]] && color="$YELLOW"
  [[ $pct -ge 80 ]] && color="$RED"

  printf "${color}"
  printf '█%.0s' $(seq 1 $filled 2>/dev/null) || true
  printf "${DIM}"
  printf '░%.0s' $(seq 1 $empty 2>/dev/null) || true
  printf "${NC} %3d%%" "$pct"
}

# ── 采集单台服务器数据 ────────────────────────────────────────────
collect_server_info() {
  local alias="$1"
  local host="${HOSTS[$alias]}"
  local tmpfile="/tmp/server_monitor_${alias}.txt"

  # 远程执行采集脚本（自动处理密码）
  local ssh_pre
  ssh_pre=$(get_ssh_prefix "$alias")
  $ssh_pre -o ConnectTimeout=$SSH_TIMEOUT \
      -o StrictHostKeyChecking=no \
      "${HOSTS[$alias]}" bash -s 2>/dev/null << 'REMOTE_SCRIPT' > "$tmpfile" || echo "OFFLINE" > "$tmpfile"

# GPU 信息
if command -v nvidia-smi &>/dev/null; then
  echo "HAS_GPU=yes"
  nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r idx name util mem_used mem_total temp power; do
    idx=$(echo "$idx" | xargs)
    name=$(echo "$name" | xargs)
    util=$(echo "$util" | xargs)
    mem_used=$(echo "$mem_used" | xargs)
    mem_total=$(echo "$mem_total" | xargs)
    temp=$(echo "$temp" | xargs)
    power=$(echo "$power" | xargs)
    echo "GPU|${idx}|${name}|${util}|${mem_used}|${mem_total}|${temp}|${power}"
  done
else
  echo "HAS_GPU=no"
fi

# CPU 使用率（1 秒采样太慢，用 /proc/loadavg）
if [[ -f /proc/loadavg ]]; then
  load=$(awk '{print $1}' /proc/loadavg)
  cores=$(nproc 2>/dev/null || echo 1)
  echo "CPU|${load}|${cores}"
elif command -v sysctl &>/dev/null; then
  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  echo "CPU|${load}|${cores}"
fi

# 内存
if [[ -f /proc/meminfo ]]; then
  total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  used=$((total - avail))
  echo "MEM|${used}|${total}"
fi

# 磁盘（主目录）
df_line=$(df -BG ~ 2>/dev/null | tail -1)
if [[ -n "$df_line" ]]; then
  disk_used=$(echo "$df_line" | awk '{gsub("G",""); print $3}')
  disk_total=$(echo "$df_line" | awk '{gsub("G",""); print $2}')
  disk_pct=$(echo "$df_line" | awk '{gsub("%",""); print $5}')
  echo "DISK|${disk_used}|${disk_total}|${disk_pct}"
fi

# tmux session
if command -v tmux &>/dev/null; then
  sessions=$(tmux list-sessions 2>/dev/null | head -5)
  if [[ -n "$sessions" ]]; then
    while IFS= read -r s; do
      echo "TMUX|$s"
    done <<< "$sessions"
  fi
fi

# GPU 进程
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-compute-apps=pid,gpu_uuid,used_memory,name \
    --format=csv,noheader,nounits 2>/dev/null | head -20 | while IFS=',' read -r pid uuid mem pname; do
    pid=$(echo "$pid" | xargs); uuid=$(echo "$uuid" | xargs); mem=$(echo "$mem" | xargs); pname=$(echo "$pname" | xargs)
    gpu_idx=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader 2>/dev/null | grep "$uuid" | cut -d',' -f1 | xargs)
    echo "GPROC|${gpu_idx:-?}|${pid}|${mem}|${pname}"
  done
fi

# 用户数
users=$(who 2>/dev/null | wc -l | xargs)
echo "USERS|${users:-0}"

# uptime
up=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*//')
echo "UPTIME|$up"

REMOTE_SCRIPT
}

# ── 渲染单台服务器（卡片式） ─────────────────────────────────────────
render_server() {
  local alias="$1"
  local host="${HOSTS[$alias]}"
  local desc="${DESCS[$alias]}"
  local tmpfile="/tmp/server_monitor_${alias}.txt"

  # 离线
  if grep -q "OFFLINE" "$tmpfile" 2>/dev/null; then
    echo -e "  ${RED}╭─${NC} ${RED}●${NC} ${BOLD}${alias}${NC}  ${DIM}${desc}${NC}"
    echo -e "  ${RED}│${NC}  ${RED}⚠ 无法连接${NC}"
    echo -e "  ${RED}╰─────────────────────────────────────────────────────────────────${NC}"
    return
  fi

  # uptime — compact: "10w 1d 15h" instead of "10 weeks, 1 day, 15 hours, 30 minutes"
  local uptime_raw
  uptime_raw=$(grep "^UPTIME|" "$tmpfile" 2>/dev/null | cut -d'|' -f2 | sed 's/^up //')
  local uptime_short
  uptime_short=$(echo "$uptime_raw" | sed -E \
    -e 's/([0-9]+) weeks?/\1w/g' \
    -e 's/([0-9]+) days?/\1d/g' \
    -e 's/([0-9]+) hours?/\1h/g' \
    -e 's/([0-9]+) minutes?/\1m/g' \
    -e 's/,//g' -e 's/  */ /g')

  local L="${DIM}│${NC}"

  echo -e "  ${DIM}╭─${NC} ${GREEN}●${NC} ${BOLD}${alias}${NC}  ${DIM}${desc}${NC}  ${DIM}│ ${host} │ up ${uptime_short:-?}${NC}"
  echo -e "  ${L}"

  # === GPU 汇总（同型号合并） ===
  local has_gpu
  has_gpu=$(grep "^HAS_GPU=" "$tmpfile" 2>/dev/null | cut -d= -f2)
  if [[ "$has_gpu" == "yes" ]]; then
    local gpu_count=0 first_name="" gpu_total_util=0 gpu_total_mu=0 gpu_total_mt=0
    local temp_min=999 temp_max=0
    local per_gpu_info="" util_min=999 util_max=0 mu_min=999999 mu_max=0

    while IFS='|' read -r _ idx name util mem_used mem_total temp power; do
      name=$(echo "$name" | sed 's/^ *//')
      util=$(echo "${util:-0}" | tr -cd '0-9'); util=${util:-0}
      mem_used=$(echo "${mem_used:-0}" | tr -cd '0-9'); mem_used=${mem_used:-0}
      mem_total=$(echo "${mem_total:-1}" | tr -cd '0-9'); mem_total=${mem_total:-1}
      temp=$(echo "${temp:-0}" | tr -cd '0-9'); temp=${temp:-0}

      gpu_count=$((gpu_count + 1))
      [[ -z "$first_name" ]] && first_name="$name"
      gpu_total_util=$((gpu_total_util + util))
      gpu_total_mu=$((gpu_total_mu + mem_used))
      gpu_total_mt=$((gpu_total_mt + mem_total))
      [[ $temp -lt $temp_min ]] && temp_min=$temp
      [[ $temp -gt $temp_max ]] && temp_max=$temp
      [[ $util -lt $util_min ]] && util_min=$util
      [[ $util -gt $util_max ]] && util_max=$util
      [[ $mem_used -lt $mu_min ]] && mu_min=$mem_used
      [[ $mem_used -gt $mu_max ]] && mu_max=$mem_used

      local mu_g=$(echo "scale=1; $mem_used / 1024" | bc 2>/dev/null || echo "$mem_used")
      local mt_g=$(echo "scale=1; $mem_total / 1024" | bc 2>/dev/null || echo "$mem_total")
      local mem_pct=0
      [[ $mem_total -gt 0 ]] && mem_pct=$((mem_used * 100 / mem_total))

      local u_color="$GREEN"
      [[ $util -ge 50 ]] && u_color="$YELLOW"
      [[ $util -ge 80 ]] && u_color="$RED"
      local m_color="$GREEN"
      [[ $mem_pct -ge 50 ]] && m_color="$YELLOW"
      [[ $mem_pct -ge 80 ]] && m_color="$RED"

      per_gpu_info+="      ${DIM}[${idx}]${NC} ${u_color}$(printf '%3d' $util)%${NC}  ${m_color}${mu_g}${NC}/${mt_g}G  ${DIM}${temp}°C${NC}\n"
    done <<< "$(grep "^GPU|" "$tmpfile" 2>/dev/null)"

    local avg_util=0
    [[ $gpu_count -gt 0 ]] && avg_util=$((gpu_total_util / gpu_count))
    local total_mu_g=$(echo "scale=1; $gpu_total_mu / 1024" | bc 2>/dev/null || echo "?")
    local total_mt_g=$(echo "scale=0; $gpu_total_mt / 1024" | bc 2>/dev/null || echo "?")
    local total_mem_pct=0
    [[ $gpu_total_mt -gt 0 ]] && total_mem_pct=$((gpu_total_mu * 100 / gpu_total_mt))

    local gpu_color="$GREEN"
    [[ $avg_util -ge 50 ]] && gpu_color="$YELLOW"
    [[ $avg_util -ge 80 ]] && gpu_color="$RED"

    local temp_str="${temp_min}"
    [[ $gpu_count -gt 1 ]] && temp_str="${temp_min}-${temp_max}"

    echo -ne "  ${L}  ${MAGENTA}GPU${NC}  ${BOLD}${gpu_count}×${first_name}${NC}"
    echo -e "  ${DIM}avg${NC} ${gpu_color}${avg_util}%${NC}  ${DIM}vram${NC} ${total_mu_g}/${total_mt_g}G"
    echo -ne "  ${L}       "
    echo -ne "util "
    bar "$avg_util" 18
    echo -ne "   mem "
    bar "$total_mem_pct" 18
    echo -ne "   ${DIM}${temp_str}°C${NC}"
    echo ""

    # only show per-card when there's meaningful variance (>5% util or >2G mem)
    local util_spread=$((util_max - util_min))
    local mu_spread=$((mu_max - mu_min))
    if [[ $gpu_count -gt 1 && ($util_spread -gt 5 || $mu_spread -gt 2048) ]]; then
      echo -ne "$per_gpu_info" | while IFS= read -r line; do
        echo -e "  ${L}  $line"
      done
    fi
    echo -e "  ${L}"
  fi

  # === CPU / MEM / DISK 横排 ===
  local cpu_str="" mem_str="" disk_str=""

  local cpu_line
  cpu_line=$(grep "^CPU|" "$tmpfile" 2>/dev/null)
  if [[ -n "$cpu_line" ]]; then
    local load cores cpu_pct
    load=$(echo "$cpu_line" | cut -d'|' -f2)
    cores=$(echo "$cpu_line" | cut -d'|' -f3)
    cpu_pct=$(echo "scale=0; $load * 100 / $cores" | bc 2>/dev/null || echo "0")
    [[ $cpu_pct -gt 100 ]] && cpu_pct=100

    echo -ne "  ${L}  ${BLUE}CPU${NC}  "
    bar "$cpu_pct" 12
    echo -e "  ${load}/${cores} cores"
  fi

  local mem_line
  mem_line=$(grep "^MEM|" "$tmpfile" 2>/dev/null)
  if [[ -n "$mem_line" ]]; then
    local mem_used mem_total mem_pct
    mem_used=$(echo "$mem_line" | cut -d'|' -f2)
    mem_total=$(echo "$mem_line" | cut -d'|' -f3)
    [[ -z "$mem_total" || "$mem_total" -eq 0 ]] 2>/dev/null && mem_total=1
    mem_pct=$((mem_used * 100 / mem_total))
    local mem_used_g=$(echo "scale=1; $mem_used / 1048576" | bc 2>/dev/null || echo "?")
    local mem_total_g=$(echo "scale=1; $mem_total / 1048576" | bc 2>/dev/null || echo "?")

    echo -ne "  ${L}  ${GREEN}MEM${NC}  "
    bar "$mem_pct" 12
    echo -e "  ${mem_used_g}G / ${mem_total_g}G"
  fi

  local disk_line
  disk_line=$(grep "^DISK|" "$tmpfile" 2>/dev/null)
  if [[ -n "$disk_line" ]]; then
    local disk_used disk_total disk_pct
    disk_used=$(echo "$disk_line" | cut -d'|' -f2)
    disk_total=$(echo "$disk_line" | cut -d'|' -f3)
    disk_pct=$(echo "$disk_line" | cut -d'|' -f4)

    echo -ne "  ${L}  ${YELLOW}DSK${NC}  "
    bar "${disk_pct:-0}" 12
    echo -e "  ${disk_used}G / ${disk_total}G"
  fi

  # === tmux sessions（单行） ===
  local tmux_lines
  tmux_lines=$(grep "^TMUX|" "$tmpfile" 2>/dev/null)
  if [[ -n "$tmux_lines" ]]; then
    local tmux_count=$(echo "$tmux_lines" | wc -l | tr -cd '0-9')
    local sess_names=""
    while IFS='|' read -r _ session_info; do
      local sname=$(echo "$session_info" | cut -d: -f1 | xargs)
      if echo "$session_info" | grep -q "(attached)"; then
        sess_names+="${GREEN}${sname}*${NC} "
      else
        sess_names+="${DIM}${sname}${NC} "
      fi
    done <<< "$tmux_lines"
    echo -e "  ${L}  ${CYAN}TMX${NC}  ${tmux_count} sessions: ${sess_names}"
  fi

  # === GPU 进程（如果开启） ===
  if $SHOW_PROCS; then
    local proc_lines
    proc_lines=$(grep "^GPROC|" "$tmpfile" 2>/dev/null)
    if [[ -n "$proc_lines" ]]; then
      echo -e "  ${L}"
      echo -e "  ${L}  ${MAGENTA}进程${NC}  ${DIM}GPU   PID      显存       命令${NC}"
      while IFS='|' read -r _ gpu_idx pid mem pname; do
        local pshort=$(basename "$pname" 2>/dev/null || echo "$pname")
        printf "  ${L}        ${DIM}[%s]${NC}   %-8s %-8sM  %s\n" "$gpu_idx" "$pid" "$mem" "$pshort"
      done <<< "$proc_lines"
    fi
  fi

  echo -e "  ${DIM}╰─────────────────────────────────────────────────────────────────${NC}"
}

# ── 紧凑模式渲染 ─────────────────────────────────────────────────
render_server_compact() {
  local alias="$1"
  local host="${HOSTS[$alias]}"
  local desc="${DESCS[$alias]}"
  local tmpfile="/tmp/server_monitor_${alias}.txt"

  local status_icon="${GREEN}●${NC}"
  if grep -q "OFFLINE" "$tmpfile" 2>/dev/null; then
    printf "  ${RED}●${NC} %-18s ${DIM}%-15s${NC} ${RED}OFFLINE${NC}\n" "$alias" "$host"
    return
  fi

  # GPU 概要
  local gpu_summary=""
  local has_gpu
  has_gpu=$(grep "^HAS_GPU=" "$tmpfile" 2>/dev/null | cut -d= -f2)
  if [[ "$has_gpu" == "yes" ]]; then
    local gpu_count=0 gpu_total_util=0 gpu_total_mem=0 gpu_total_memcap=0
    while IFS='|' read -r _ idx name util mem_used mem_total temp power; do
      util=$(echo "${util:-0}" | tr -cd '0-9'); util=${util:-0}
      mem_used=$(echo "${mem_used:-0}" | tr -cd '0-9'); mem_used=${mem_used:-0}
      mem_total=$(echo "${mem_total:-1}" | tr -cd '0-9'); mem_total=${mem_total:-1}
      gpu_count=$((gpu_count + 1))
      gpu_total_util=$((gpu_total_util + util))
      gpu_total_mem=$((gpu_total_mem + mem_used))
      gpu_total_memcap=$((gpu_total_memcap + mem_total))
    done <<< "$(grep "^GPU|" "$tmpfile" 2>/dev/null)"

    local avg_util=0
    [[ $gpu_count -gt 0 ]] && avg_util=$((gpu_total_util / gpu_count))
    local mem_g=$(echo "scale=0; $gpu_total_mem / 1024" | bc 2>/dev/null || echo "?")
    local memcap_g=$(echo "scale=0; $gpu_total_memcap / 1024" | bc 2>/dev/null || echo "?")

    local gpu_color="$GREEN"
    [[ $avg_util -ge 50 ]] && gpu_color="$YELLOW"
    [[ $avg_util -ge 80 ]] && gpu_color="$RED"
    gpu_summary="${gpu_count}×GPU ${gpu_color}${avg_util}%${NC} ${mem_g}/${memcap_g}G"
  else
    gpu_summary="${DIM}no GPU${NC}"
  fi

  # CPU 概要
  local cpu_summary=""
  local cpu_line
  cpu_line=$(grep "^CPU|" "$tmpfile" 2>/dev/null)
  if [[ -n "$cpu_line" ]]; then
    local load cores
    load=$(echo "$cpu_line" | cut -d'|' -f2)
    cores=$(echo "$cpu_line" | cut -d'|' -f3)
    cpu_summary="CPU ${load}/${cores}"
  fi

  # 内存概要
  local mem_summary=""
  local mem_line
  mem_line=$(grep "^MEM|" "$tmpfile" 2>/dev/null)
  if [[ -n "$mem_line" ]]; then
    local mem_used mem_total mem_pct
    mem_used=$(echo "$mem_line" | cut -d'|' -f2)
    mem_total=$(echo "$mem_line" | cut -d'|' -f3)
    mem_pct=$((mem_used * 100 / mem_total))

    local mem_color="$GREEN"
    [[ $mem_pct -ge 50 ]] && mem_color="$YELLOW"
    [[ $mem_pct -ge 80 ]] && mem_color="$RED"
    mem_summary="MEM ${mem_color}${mem_pct}%${NC}"
  fi

  # tmux session 数
  local tmux_count
  tmux_count=$(grep -c "^TMUX|" "$tmpfile" 2>/dev/null || echo "0")
  tmux_count=$(echo "$tmux_count" | tr -cd '0-9')
  tmux_count=${tmux_count:-0}
  local tmux_summary=""
  [[ $tmux_count -gt 0 ]] && tmux_summary="${CYAN}${tmux_count} sess${NC}"

  printf "  ${status_icon} ${BOLD}%-18s${NC} ${DIM}%-12s${NC}  %-30b  %-14s  %-10b  %b\n" \
    "$alias" "$host" "$gpu_summary" "$cpu_summary" "$mem_summary" "$tmux_summary"
}

# ── 主渲染循环 ────────────────────────────────────────────────────
render_all() {
  clear

  local now=$(date '+%Y-%m-%d %H:%M:%S')
  local n=${#ALIASES[@]}
  local mode_str="详细"
  $COMPACT && mode_str="紧凑"
  local procs_str=""
  $SHOW_PROCS && procs_str=" +进程"

  echo ""
  echo -e "  ${BOLD}🖥  Server Monitor${NC}  ${DIM}${n} servers · ${INTERVAL}s · ${mode_str}${procs_str} · ${now}${NC}"
  echo -e "  ${DIM}────────────────────────────────────────────────────────────────────${NC}"
  echo ""

  # 并行采集所有服务器
  local pids=()
  for alias in "${ALIASES[@]}"; do
    collect_server_info "$alias" &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  if $COMPACT; then
    # 紧凑模式：表头 + 每服务器一行
    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${DIM}   %-18s %-12s  %-30s  %-14s  %-10s  %s${NC}\n" \
      "服务器" "地址" "GPU" "CPU" "内存" "tmux"
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    for alias in "${ALIASES[@]}"; do
      render_server_compact "$alias"
    done
    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  else
    # 详细模式：每服务器卡片
    for alias in "${ALIASES[@]}"; do
      render_server "$alias"
      echo ""
    done
  fi
  echo -e "  ${DIM}Ctrl+C 退出${NC}"
}

# ── 入口 ──────────────────────────────────────────────────────────
if $ONCE; then
  render_all
else
  trap 'echo -e "\n${DIM}监控已停止${NC}"; exit 0' INT
  while true; do
    render_all
    sleep "$INTERVAL"
  done
fi
