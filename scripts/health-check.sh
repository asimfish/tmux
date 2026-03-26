#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# health-check.sh — 服务器健康检查 + 告警
#
# 用法：
#   bash health-check.sh              # 检查所有服务器
#   bash health-check.sh <别名>       # 检查指定服务器
#   bash health-check.sh --watch      # 持续监控，异常时告警
#   bash health-check.sh --json       # JSON 输出（供其他工具调用）
#
# 检查项：
#   - SSH 连通性
#   - GPU 温度是否过高（>85°C 警告，>90°C 危险）
#   - 内存使用率（>90% 警告）
#   - 磁盘使用率（>85% 警告，>95% 危险）
#   - GPU 显存是否接近满载
#   - 训练进程是否还在运行

set +e

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
SSH_TIMEOUT=5
JSON_MODE=false
WATCH_MODE=false
WATCH_INTERVAL=60
FILTER_ALIAS=""

# ── 阈值配置 ─────────────────────────────────────────────────────
GPU_TEMP_WARN=85
GPU_TEMP_CRIT=90
MEM_WARN=90
DISK_WARN=85
DISK_CRIT=95
GPU_MEM_WARN=95

# ── 参数解析 ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)       JSON_MODE=true; shift ;;
    --watch)      WATCH_MODE=true; shift ;;
    --interval)   WATCH_INTERVAL="$2"; shift 2 ;;
    -h|--help)
      echo "用法: health-check.sh [--json] [--watch] [--interval N] [别名]"
      exit 0
      ;;
    *)            FILTER_ALIAS="$1"; shift ;;
  esac
done

# ── 检查配置 ──────────────────────────────────────────────────────
if [[ ! -f "$CONF_FILE" ]]; then
  echo -e "${RED}[✗]${NC} 找不到配置文件：$CONF_FILE"
  exit 1
fi

# ── 读取服务器列表（使用 common.sh）──────────────────────────────
source "$SCRIPT_DIR/common.sh"
load_servers "$FILTER_ALIAS"


# ── 单台服务器检查 ────────────────────────────────────────────────
check_server() {
  local alias_name="$1"
  local host="${HOSTS[$alias_name]}"
  local issues=()
  local warnings=()
  local status="healthy"

  # 连通性检查
  local ssh_pre
  ssh_pre=$(get_ssh_prefix "$alias_name")
  if ! $ssh_pre -o ConnectTimeout=$SSH_TIMEOUT "$host" "echo ok" &>/dev/null; then
    if $JSON_MODE; then
      echo "{\"server\":\"$alias_name\",\"host\":\"$host\",\"status\":\"offline\",\"issues\":[\"SSH unreachable\"]}"
    else
      echo -e "  ${RED}●${NC} ${BOLD}$alias_name${NC} ${DIM}($host)${NC} — ${RED}OFFLINE${NC}"
    fi
    return
  fi

  # 远程采集
  local data
  data=$($ssh_pre -o ConnectTimeout=$SSH_TIMEOUT "$host" bash -s 2>/dev/null << 'CHECK_SCRIPT'
# GPU 检查
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-gpu=index,temperature.gpu,memory.used,memory.total,utilization.gpu \
    --format=csv,noheader,nounits 2>/dev/null | while IFS=', ' read -r idx temp mu mt util; do
    echo "GPU|$idx|$temp|$mu|$mt|$util"
  done
  # GPU 进程数
  proc_count=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | wc -l)
  echo "GPU_PROCS|$proc_count"
fi

# 内存
if [[ -f /proc/meminfo ]]; then
  total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  used=$((total - avail))
  pct=$((used * 100 / total))
  echo "MEM|$pct|$used|$total"
fi

# 磁盘
df -BG / 2>/dev/null | tail -1 | awk '{gsub("%",""); print "DISK|"$5"|"$3"|"$2}'

# home 目录磁盘
df -BG ~ 2>/dev/null | tail -1 | awk '{gsub("%",""); print "HOME_DISK|"$5"|"$3"|"$2}'

# 关键进程
pgrep -c python 2>/dev/null | xargs -I{} echo "PYTHON_PROCS|{}" || echo "PYTHON_PROCS|0"

# zombie 进程
zombies=$(ps aux 2>/dev/null | awk '$8~/^Z/{count++} END{print count+0}')
echo "ZOMBIES|$zombies"
CHECK_SCRIPT
  ) || true

  if [[ -z "$data" ]]; then
    issues+=("无法采集数据")
    status="error"
  else
    # GPU 温度检查
    while IFS='|' read -r _ idx temp mu mt util; do
      temp=${temp// /}
      mu=${mu// /}
      mt=${mt// /}
      if [[ -n "$temp" ]] && [[ $temp -ge $GPU_TEMP_CRIT ]] 2>/dev/null; then
        issues+=("GPU[$idx] 温度过高: ${temp}°C (>$GPU_TEMP_CRIT)")
        status="critical"
      elif [[ -n "$temp" ]] && [[ $temp -ge $GPU_TEMP_WARN ]] 2>/dev/null; then
        warnings+=("GPU[$idx] 温度偏高: ${temp}°C")
        [[ "$status" == "healthy" ]] && status="warning"
      fi

      # GPU 显存
      if [[ -n "$mt" ]] && [[ $mt -gt 0 ]] 2>/dev/null; then
        local gpu_mem_pct=$((mu * 100 / mt))
        if [[ $gpu_mem_pct -ge $GPU_MEM_WARN ]]; then
          warnings+=("GPU[$idx] 显存接近满载: ${mu}/${mt} MiB ($gpu_mem_pct%)")
          [[ "$status" == "healthy" ]] && status="warning"
        fi
      fi
    done <<< "$(echo "$data" | grep "^GPU|")"

    # 内存检查
    local mem_line
    mem_line=$(echo "$data" | grep "^MEM|")
    if [[ -n "$mem_line" ]]; then
      local mem_pct
      mem_pct=$(echo "$mem_line" | cut -d'|' -f2)
      if [[ $mem_pct -ge $MEM_WARN ]] 2>/dev/null; then
        warnings+=("内存使用率: ${mem_pct}%")
        [[ "$status" == "healthy" ]] && status="warning"
      fi
    fi

    # 磁盘检查
    for disk_type in "DISK" "HOME_DISK"; do
      local disk_line
      disk_line=$(echo "$data" | grep "^${disk_type}|")
      if [[ -n "$disk_line" ]]; then
        local disk_pct
        disk_pct=$(echo "$disk_line" | cut -d'|' -f2)
        local label="根分区"
        [[ "$disk_type" == "HOME_DISK" ]] && label="Home"

        if [[ $disk_pct -ge $DISK_CRIT ]] 2>/dev/null; then
          issues+=("${label}磁盘严重不足: ${disk_pct}%")
          status="critical"
        elif [[ $disk_pct -ge $DISK_WARN ]] 2>/dev/null; then
          warnings+=("${label}磁盘偏高: ${disk_pct}%")
          [[ "$status" == "healthy" ]] && status="warning"
        fi
      fi
    done

    # zombie 进程
    local zombies
    zombies=$(echo "$data" | grep "^ZOMBIES|" | cut -d'|' -f2)
    if [[ -n "$zombies" ]] && [[ $zombies -gt 5 ]] 2>/dev/null; then
      warnings+=("${zombies} 个 zombie 进程")
      [[ "$status" == "healthy" ]] && status="warning"
    fi
  fi

  # 输出
  if $JSON_MODE; then
    local issues_json="["
    for i in "${issues[@]:-}"; do
      [[ -n "$i" ]] && issues_json+="\"$i\","
    done
    for w in "${warnings[@]:-}"; do
      [[ -n "$w" ]] && issues_json+="\"$w\","
    done
    issues_json="${issues_json%,}]"
    echo "{\"server\":\"$alias_name\",\"host\":\"$host\",\"status\":\"$status\",\"issues\":$issues_json}"
  else
    local icon
    case "$status" in
      healthy)  icon="${GREEN}●${NC}" ;;
      warning)  icon="${YELLOW}●${NC}" ;;
      critical) icon="${RED}●${NC}" ;;
      *)        icon="${RED}●${NC}" ;;
    esac

    local status_text
    case "$status" in
      healthy)  status_text="${GREEN}HEALTHY${NC}" ;;
      warning)  status_text="${YELLOW}WARNING${NC}" ;;
      critical) status_text="${RED}CRITICAL${NC}" ;;
      *)        status_text="${RED}ERROR${NC}" ;;
    esac

    echo -e "  ${icon} ${BOLD}$alias_name${NC} ${DIM}($host)${NC} — $status_text"

    for issue in "${issues[@]:-}"; do
      [[ -n "$issue" ]] && echo -e "    ${RED}✗${NC} $issue"
    done
    for warning in "${warnings[@]:-}"; do
      [[ -n "$warning" ]] && echo -e "    ${YELLOW}!${NC} $warning"
    done
  fi
}

# ── 全部检查 ──────────────────────────────────────────────────────
check_all() {
  if ! $JSON_MODE; then
    echo -e "\n${BOLD}  ╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║      🏥  服务器健康检查  Health Check          ║${NC}"
    echo -e "${BOLD}  ╚═══════════════════════════════════════════════╝${NC}"
    echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')  |  ${#ALIASES[@]} 台服务器${NC}\n"
  fi

  if $JSON_MODE; then
    echo "["
  fi

  local first=true
  local pids=()
  local tmpdir="/tmp/health_check_$$"
  mkdir -p "$tmpdir"

  for alias_name in "${ALIASES[@]}"; do
    (check_server "$alias_name" > "$tmpdir/$alias_name.txt") &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  for alias_name in "${ALIASES[@]}"; do
    if $JSON_MODE && ! $first; then
      echo ","
    fi
    first=false
    cat "$tmpdir/$alias_name.txt" 2>/dev/null
  done

  if $JSON_MODE; then
    echo "]"
  else
    echo ""
  fi

  rm -rf "$tmpdir"
}

# ── macOS 通知 ────────────────────────────────────────────────────
notify_macos() {
  local title="$1"
  local message="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Basso\"" 2>/dev/null || true
  fi
}

# ── 入口 ──────────────────────────────────────────────────────────
if $WATCH_MODE; then
  echo -e "${BLUE}[health]${NC} 进入持续监控模式（间隔 ${WATCH_INTERVAL}s）"
  trap 'echo -e "\n${DIM}监控已停止${NC}"; exit 0' INT

  while true; do
    output=$(check_all)
    echo "$output"

    if echo "$output" | grep -q "CRITICAL\|critical"; then
      notify_macos "服务器告警" "有服务器出现严重问题，请检查！"
    fi

    sleep "$WATCH_INTERVAL"
  done
else
  check_all
fi
