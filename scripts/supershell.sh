#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# supershell.sh — fzf 交互式 tmux 会话 + 服务器管理器
#
# 功能：
#   - 列出所有本地 tmux session + 远程服务器
#   - fzf 模糊搜索，实时预览
#   - 快捷操作：SSH 登录、attach、新建 window/pane、监控等
#
# 用法：
#   bash supershell.sh          # 启动交互界面
#   Ctrl-w S                    # 在 tmux 中通过快捷键启动（需配置 .tmux.conf）

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"

# ── 颜色 ─────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── 检查依赖 ─────────────────────────────────────────────────────
if ! command -v fzf &>/dev/null; then
  echo -e "${RED}[✗]${NC} 需要 fzf，请先安装：brew install fzf"
  exit 1
fi

# ── 获取本地 tmux session 列表 ────────────────────────────────────
get_local_sessions() {
  if ! tmux list-sessions 2>/dev/null | while IFS=: read -r name rest; do
    local windows attached
    windows=$(echo "$rest" | grep -o '[0-9]* windows' | awk '{print $1}')
    if echo "$rest" | grep -q "attached"; then
      attached="✦"
    else
      attached=" "
    fi
    echo "session|${attached}|${name}|${windows:-0} windows|local"
  done; then
    true
  fi
}

# ── 加载 common.sh ──────────────────────────────────────────────
source "$SCRIPT_DIR/common.sh"

# ── 获取远程服务器列表 ────────────────────────────────────────────
get_remote_servers() {
  if [[ ! -f "$CONF_FILE" ]]; then
    return
  fi

  load_servers
  for a in "${ALIASES[@]}"; do
    local host="${HOSTS[$a]}"
    local dir="${REMOTEDIRS[$a]}"
    local desc="${DESCS[$a]}"
    echo "server| |${a}|${host}|${desc:-(${dir})}"
  done
}

# ── 获取动作列表 ──────────────────────────────────────────────────
get_actions() {
  echo "action|⚡|new-session|创建新的本地 tmux session|"
  echo "action|⚡|new-window|在当前 session 新建 window|"
  echo "action|⚡|vsplit|纵向分屏 (左右)|"
  echo "action|⚡|hsplit|横向分屏 (上下)|"
  echo "action|📊|monitor|启动多服务器监控面板|"
  echo "action|🔗|bind-all|挂载所有远程服务器|"
  echo "action|📋|mount-status|查看所有挂载状态|"
  echo "action|🔄|reconnect|重连所有断开的服务器|"
  echo "action|⚙️|reload|重载 tmux 配置|"
}

# ── 构建 fzf 输入 ────────────────────────────────────────────────
build_entries() {
  local sessions servers actions

  sessions=$(get_local_sessions)
  servers=$(get_remote_servers)
  actions=$(get_actions)

  local session_count=0 server_count=0

  if [[ -n "$sessions" ]]; then
    session_count=$(echo "$sessions" | wc -l | tr -d ' ')
  fi
  if [[ -n "$servers" ]]; then
    server_count=$(echo "$servers" | wc -l | tr -d ' ')
  fi

  # 标题行（fzf header）
  echo "HEADER|━━━━ 本地 Sessions ($session_count) ━━━━"

  if [[ -n "$sessions" ]]; then
    echo "$sessions"
  fi

  echo "HEADER|━━━━ 远程服务器 ($server_count) ━━━━"

  if [[ -n "$servers" ]]; then
    echo "$servers"
  fi

  echo "HEADER|━━━━ 快捷操作 ━━━━"
  echo "$actions"
}

# ── 预览内容生成 ──────────────────────────────────────────────────
# 这个函数会被 fzf --preview 调用
generate_preview() {
  local entry="$1"
  local type=$(echo "$entry" | cut -d'|' -f1)
  local name=$(echo "$entry" | cut -d'|' -f3)

  case "$type" in
    session)
      echo -e "\033[1;36m═══ Session: $name ═══\033[0m"
      echo ""
      if tmux has-session -t "$name" 2>/dev/null; then
        # windows 列表
        echo -e "\033[1mWindows:\033[0m"
        tmux list-windows -t "$name" 2>/dev/null | while read -r w; do
          local wnum wname
          wnum=$(echo "$w" | cut -d: -f1)
          wname=$(echo "$w" | cut -d: -f2 | awk '{print $1}')
          local active=""
          echo "$w" | grep -q "active" && active=" \033[33m◀ active\033[0m"
          echo -e "  \033[36m[$wnum]\033[0m $wname$active"
        done

        echo ""
        echo -e "\033[1mPanes:\033[0m"
        tmux list-panes -t "$name" -F '#{window_index}:#{pane_index} #{pane_current_command} #{pane_width}x#{pane_height}' 2>/dev/null | while read -r p; do
          echo -e "  \033[2m▸\033[0m $p"
        done

        echo ""
        # 捕获当前 pane 内容
        echo -e "\033[1mOutput:\033[0m"
        tmux capture-pane -t "$name" -p 2>/dev/null | tail -15
      fi
      ;;
    server)
      local host=$(echo "$entry" | cut -d'|' -f4)
      local desc=$(echo "$entry" | cut -d'|' -f5)

      echo -e "\033[1;35m═══ Server: $name ═══\033[0m"
      echo -e "\033[2mHost: $host\033[0m"
      [[ -n "$desc" ]] && echo -e "\033[2mDesc: $desc\033[0m"
      echo ""

      # 快速探测（使用 ssh-helper 自动处理密码）
      local helper="$SCRIPT_DIR/ssh-helper.sh"
      echo -e "\033[1mConnectivity:\033[0m"
      if bash "$helper" "$name" -o ConnectTimeout=3 "echo ok" 2>/dev/null | grep -q "ok"; then
        echo -e "  \033[32m● 在线\033[0m"
        echo ""

        local gpu_info
        gpu_info=$(bash "$helper" "$name" -o ConnectTimeout=3 "nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null" 2>/dev/null)
        if [[ -n "$gpu_info" ]]; then
          echo -e "\033[1mGPU:\033[0m"
          local idx=0
          while IFS=',' read -r gname gutil gmem_u gmem_t; do
            gname=$(echo "$gname" | xargs)
            gutil=$(echo "$gutil" | xargs)
            gmem_u=$(echo "$gmem_u" | xargs)
            gmem_t=$(echo "$gmem_t" | xargs)
            echo -e "  [$idx] \033[36m$gname\033[0m  $gutil  $gmem_u/$gmem_t"
            idx=$((idx + 1))
          done <<< "$gpu_info"
          echo ""
        fi

        local tmux_info
        tmux_info=$(bash "$helper" "$name" -o ConnectTimeout=3 "tmux list-sessions 2>/dev/null" 2>/dev/null)
        if [[ -n "$tmux_info" ]]; then
          echo -e "\033[1mtmux sessions:\033[0m"
          while IFS= read -r s; do
            echo -e "  \033[2m▸\033[0m $s"
          done <<< "$tmux_info"
          echo ""
        fi

        local load_info
        load_info=$(bash "$helper" "$name" -o ConnectTimeout=3 "uptime 2>/dev/null" 2>/dev/null)
        if [[ -n "$load_info" ]]; then
          echo -e "\033[1mLoad:\033[0m"
          echo -e "  $load_info"
        fi
      else
        echo -e "  \033[31m● 离线 / 无法连接\033[0m"
      fi
      ;;
    action)
      local action_desc=$(echo "$entry" | cut -d'|' -f4)
      echo -e "\033[1;33m═══ Action: $name ═══\033[0m"
      echo ""
      echo -e "$action_desc"
      echo ""

      case "$name" in
        new-session)
          echo "创建一个新的命名 tmux session。"
          echo "会提示输入名称。"
          ;;
        new-window)
          echo "在当前 tmux session 中新建一个 window。"
          echo "继承当前工作目录。"
          ;;
        vsplit)
          echo "在当前 pane 右侧纵向分屏。"
          ;;
        hsplit)
          echo "在当前 pane 下方横向分屏。"
          ;;
        monitor)
          echo "启动多服务器监控面板。"
          echo "显示所有服务器的 GPU/CPU/内存/磁盘状态。"
          echo "按 Ctrl+C 退出。"
          ;;
        bind-all)
          echo "sshfs 挂载所有 servers.conf 中的服务器。"
          echo "挂载后可用本地 Claude Code 直接管理远程文件。"
          ;;
        mount-status)
          echo "查看当前所有 sshfs 挂载状态。"
          ;;
        reconnect)
          echo "尝试重新连接所有断开的服务器挂载。"
          ;;
        reload)
          echo "重新加载 tmux 配置文件 (~/.tmux.conf)。"
          ;;
      esac
      ;;
    HEADER)
      echo ""
      ;;
  esac
}

# ── 格式化 fzf 显示 ──────────────────────────────────────────────
format_entry() {
  while IFS='|' read -r type icon name info extra; do
    case "$type" in
      HEADER)
        echo -e "\033[2m$icon\033[0m"
        ;;
      session)
        if [[ "$icon" == "✦" ]]; then
          printf "  \033[32m●\033[0m \033[1m%-20s\033[0m  %s  \033[32m attached\033[0m\n" "$name" "$info"
        else
          printf "  \033[2m○\033[0m %-20s  %s\n" "$name" "$info"
        fi
        ;;
      server)
        printf "  \033[35m◆\033[0m \033[36m%-20s\033[0m  \033[2m%-20s\033[0m  %s\n" "$name" "$info" "$extra"
        ;;
      action)
        printf "  \033[33m⚡\033[0m \033[33m%-20s\033[0m  \033[2m%s\033[0m\n" "$name" "$info"
        ;;
    esac
  done
}

# ── 执行选中项 ────────────────────────────────────────────────────
execute_selection() {
  local entry="$1"
  local type=$(echo "$entry" | cut -d'|' -f1)
  local name=$(echo "$entry" | cut -d'|' -f3)

  case "$type" in
    session)
      if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$name" 2>/dev/null || tmux attach-session -t "$name"
      else
        tmux attach-session -t "$name"
      fi
      ;;
    server)
      local host=$(echo "$entry" | cut -d'|' -f4)
      # 读取远程目录
      local remote_dir
      remote_dir=$(grep -v '^\s*#' "$CONF_FILE" | grep -v '^\s*$' | awk -v a="$name" '$1 == a {print $3; exit}')
      [[ -z "$remote_dir" ]] && remote_dir="~"

      if [[ -n "${TMUX:-}" ]]; then
        # 在新 window 中打开 SSH
        tmux new-window -n "$name" "bash '$SCRIPT_DIR/login.sh' '$name'"
      else
        bash "$SCRIPT_DIR/login.sh" "$name"
      fi
      ;;
    action)
      case "$name" in
        new-session)
          read -r -p "Session 名称: " sname
          if [[ -n "$sname" ]]; then
            if [[ -n "${TMUX:-}" ]]; then
              tmux new-session -d -s "$sname" && tmux switch-client -t "$sname"
            else
              tmux new-session -s "$sname"
            fi
          fi
          ;;
        new-window)
          [[ -n "${TMUX:-}" ]] && tmux new-window -c "#{pane_current_path}"
          ;;
        vsplit)
          [[ -n "${TMUX:-}" ]] && tmux split-window -h -c "#{pane_current_path}"
          ;;
        hsplit)
          [[ -n "${TMUX:-}" ]] && tmux split-window -v -c "#{pane_current_path}"
          ;;
        monitor)
          if [[ -n "${TMUX:-}" ]]; then
            tmux new-window -n "monitor" "bash '$SCRIPT_DIR/server-monitor.sh'"
          else
            bash "$SCRIPT_DIR/server-monitor.sh"
          fi
          ;;
        bind-all)
          if [[ -n "${TMUX:-}" ]]; then
            tmux new-window -n "bind" "bash '$SCRIPT_DIR/bind-server.sh' --all; read -p 'Press Enter to close...'"
          else
            bash "$SCRIPT_DIR/bind-server.sh" --all
          fi
          ;;
        mount-status)
          bash "$SCRIPT_DIR/bind-server.sh" --status
          sleep 2
          ;;
        reconnect)
          bash "$SCRIPT_DIR/bind-server.sh" --unmount-all 2>/dev/null || true
          bash "$SCRIPT_DIR/bind-server.sh" --all 2>/dev/null || true
          ;;
        reload)
          [[ -n "${TMUX:-}" ]] && tmux source-file ~/.tmux.conf && tmux display-message "Config reloaded"
          ;;
      esac
      ;;
  esac
}

# ── 导出函数供 fzf --preview 使用 ─────────────────────────────────
export SCRIPT_DIR REPO_DIR CONF_FILE
export -f generate_preview 2>/dev/null || true

# ── 主界面 ────────────────────────────────────────────────────────
main() {
  local entries
  entries=$(build_entries)

  # 写入临时脚本供 preview 调用
  local preview_script="/tmp/supershell_preview.sh"
  cat > "$preview_script" << 'PREVIEW_SCRIPT'
#!/usr/bin/env bash
entry="$1"
type=$(echo "$entry" | cut -d'|' -f1)
name=$(echo "$entry" | cut -d'|' -f3)

case "$type" in
  session)
    echo -e "\033[1;36m═══ Session: $name ═══\033[0m"
    echo ""
    if tmux has-session -t "$name" 2>/dev/null; then
      echo -e "\033[1mWindows:\033[0m"
      tmux list-windows -t "$name" 2>/dev/null | while read -r w; do
        wnum=$(echo "$w" | cut -d: -f1)
        wname=$(echo "$w" | cut -d: -f2 | awk '{print $1}')
        active=""
        echo "$w" | grep -q "active" && active=" \033[33m◀ active\033[0m"
        echo -e "  \033[36m[$wnum]\033[0m $wname$active"
      done
      echo ""
      echo -e "\033[1mPanes:\033[0m"
      tmux list-panes -t "$name" -F '  #{window_index}.#{pane_index} #{pane_current_command} #{pane_width}x#{pane_height}' 2>/dev/null
      echo ""
      echo -e "\033[1mOutput (last 20 lines):\033[0m"
      tmux capture-pane -t "$name" -p 2>/dev/null | tail -20
    fi
    ;;
  server)
    host=$(echo "$entry" | cut -d'|' -f4)
    desc=$(echo "$entry" | cut -d'|' -f5)
    echo -e "\033[1;35m═══ Server: $name ═══\033[0m"
    echo -e "\033[2mHost: $host\033[0m"
    [[ -n "$desc" ]] && echo -e "\033[2mDesc: $desc\033[0m"
    echo ""
    echo -e "\033[2mProbing...\033[0m"
    helper="SCRIPT_DIR_PLACEHOLDER/ssh-helper.sh"
    if bash "$helper" "$name" -o ConnectTimeout=3 "echo ONLINE" 2>/dev/null | grep -q "ONLINE"; then
      echo -e "\033[32m● Online\033[0m"
      echo ""
      gpu=$(bash "$helper" "$name" -o ConnectTimeout=3 \
        "nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null" 2>/dev/null)
      if [[ -n "$gpu" ]]; then
        echo -e "\033[1mGPU:\033[0m"
        echo "$gpu" | while IFS=',' read -r idx gname gutil gmem_u gmem_t; do
          printf "  [%s] \033[36m%s\033[0m %s  %s/%s\n" \
            "$(echo $idx | xargs)" "$(echo $gname | xargs)" \
            "$(echo $gutil | xargs)" "$(echo $gmem_u | xargs)" "$(echo $gmem_t | xargs)"
        done
        echo ""
      fi
      sessions=$(bash "$helper" "$name" -o ConnectTimeout=3 "tmux list-sessions 2>/dev/null" 2>/dev/null)
      if [[ -n "$sessions" ]]; then
        echo -e "\033[1mtmux:\033[0m"
        echo "$sessions" | while IFS= read -r s; do
          echo -e "  \033[2m▸\033[0m $s"
        done
        echo ""
      fi
      load=$(bash "$helper" "$name" -o ConnectTimeout=3 \
        "cat /proc/loadavg 2>/dev/null | awk '{print \$1, \$2, \$3}'" 2>/dev/null)
      cores=$(bash "$helper" "$name" -o ConnectTimeout=3 "nproc 2>/dev/null" 2>/dev/null)
      if [[ -n "$load" ]]; then
        echo -e "\033[1mLoad:\033[0m $load  (${cores:-?} cores)"
      fi
      mem=$(bash "$helper" "$name" -o ConnectTimeout=3 \
        "free -h 2>/dev/null | awk '/^Mem:/{print \$3\"/\"\$2}'" 2>/dev/null)
      if [[ -n "$mem" ]]; then
        echo -e "\033[1mMemory:\033[0m $mem"
      fi
    else
      echo -e "\033[31m● Offline\033[0m"
    fi
    ;;
  action)
    action_desc=$(echo "$entry" | cut -d'|' -f4)
    echo -e "\033[1;33m═══ $name ═══\033[0m"
    echo ""
    echo "$action_desc"
    ;;
  HEADER)
    echo ""
    ;;
esac
PREVIEW_SCRIPT
  sed -i.bak "s|SCRIPT_DIR_PLACEHOLDER|$SCRIPT_DIR|g" "$preview_script" && rm -f "${preview_script}.bak"
  chmod +x "$preview_script"

  # 运行 fzf
  local selected
  selected=$(echo "$entries" | \
    fzf \
      --ansi \
      --no-sort \
      --reverse \
      --border=rounded \
      --border-label=" ⚡ SuperShell " \
      --border-label-pos=3 \
      --header="  ↑↓ 选择  Enter 执行  Ctrl-M 监控  Ctrl-R 刷新  Esc 退出" \
      --prompt="  ❯ " \
      --pointer="▶" \
      --marker="✓" \
      --color="bg+:#2d2d2d,fg+:#e0e0e0,hl:#ff9e64,hl+:#ff9e64,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,spinner:#e0af68,header:#565f89,border:#3b4261,label:#7aa2f7" \
      --preview="bash $preview_script {}" \
      --preview-window="right:50%:wrap:border-left" \
      --bind="ctrl-m:execute(bash '$SCRIPT_DIR/server-monitor.sh')" \
      --bind="ctrl-r:reload(bash '$0' --entries)" \
      --with-nth=1.. \
      --delimiter='|' \
    2>/dev/null) || true

  if [[ -n "$selected" ]]; then
    execute_selection "$selected"
  fi

  rm -f "$preview_script"
}

# ── 入口 ──────────────────────────────────────────────────────────
case "${1:-}" in
  --entries)
    build_entries
    ;;
  --preview)
    shift
    generate_preview "$@"
    ;;
  -h|--help)
    echo "supershell.sh — fzf 交互式会话 + 服务器管理器"
    echo ""
    echo "用法："
    echo "  supershell              启动交互界面"
    echo "  在 tmux 中 Ctrl-w S     快捷键启动"
    echo ""
    echo "界面操作："
    echo "  ↑↓ / 输入      选择 / 搜索"
    echo "  Enter          执行选中项"
    echo "  Ctrl-M         启动监控面板"
    echo "  Ctrl-R         刷新列表"
    echo "  Esc            退出"
    ;;
  *)
    main
    ;;
esac
