#!/usr/bin/env bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$_b" ]] && exec "$_b" "$0" "$@"; done
  echo "需要 bash 4+: brew install bash" >&2; exit 1
fi
# bind-server.sh — 挂载远程服务器目录，在挂载目录里启动 Claude
#
# 用法：
#   bash bind-server.sh <ssh别名> <远程路径>       # 直接指定
#   bash bind-server.sh <服务器别名>               # 从 servers.conf 读取
#   bash bind-server.sh --all                      # 挂载所有 servers.conf 中的服务器
#   bash bind-server.sh --unmount <ssh别名>        # 卸载指定挂载
#   bash bind-server.sh --unmount-all              # 卸载所有挂载
#   bash bind-server.sh --status                   # 查看所有挂载状态
#
# 示例：
#   bash bind-server.sh robot ~/projects/nav
#   bash bind-server.sh liyufeng_4090              # 从 servers.conf 读取
#   bash bind-server.sh --all                      # 挂载全部服务器

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${BLUE}[bind-server]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF_FILE="${SERVERS_CONF:-$REPO_DIR/servers.conf}"

# ── 加载 common.sh ──────────────────────────────────────────────
source "$SCRIPT_DIR/common.sh"

# ── 从 servers.conf 读取服务器信息 ────────────────────────────────
lookup_server() {
  local alias="$1"
  if [[ ! -f "$CONF_FILE" ]]; then
    return 1
  fi

  local line
  line=$(grep -v '^\s*#' "$CONF_FILE" | grep -v '^\s*$' | awk -v a="$alias" '$1 == a {print; exit}')
  if [[ -z "$line" ]]; then
    return 1
  fi

  LOOKUP_HOST=$(echo "$line" | awk '{print $2}')
  LOOKUP_DIR=$(echo "$line" | awk '{print $3}')
  LOOKUP_PASS=$(echo "$line" | awk '{print $4}')
  [[ "$LOOKUP_PASS" == "-" ]] && LOOKUP_PASS=""
  return 0
}

# ── 挂载状态查看 ──────────────────────────────────────────────────
show_status() {
  echo -e "\n${BOLD}当前挂载状态：${NC}\n"
  local mount_base="$HOME/mnt"
  local count=0

  if [[ -d "$mount_base" ]]; then
    for dir in "$mount_base"/*/; do
      [[ -d "$dir" ]] || continue
      local name=$(basename "$dir")
      if mount | grep -q "$dir"; then
        echo -e "  ${GREEN}●${NC} ${CYAN}${name}${NC} → ${dir}"
        count=$((count + 1))
      else
        # 目录存在但未挂载
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
          echo -e "  ${DIM}○ ${name} → ${dir} (未挂载)${NC}"
        fi
      fi
    done
  fi

  if [[ $count -eq 0 ]]; then
    echo -e "  ${DIM}没有活跃的挂载${NC}"
  fi
  echo ""
}

# ── 卸载挂载 ──────────────────────────────────────────────────────
unmount_server() {
  local target="$1"
  local mount_base="$HOME/mnt"

  if [[ "$target" == "all" ]]; then
    log "卸载所有挂载..."
    local found=false
    for dir in "$mount_base"/*/; do
      [[ -d "$dir" ]] || continue
      if mount | grep -q "$dir"; then
        umount "$dir" 2>/dev/null && ok "已卸载 $dir" || warn "卸载失败 $dir，尝试强制卸载"
        umount -f "$dir" 2>/dev/null || true
        found=true
      fi
    done
    $found || warn "没有需要卸载的挂载"
    return
  fi

  # 查找匹配的挂载点
  local matched=false
  for dir in "$mount_base"/*/; do
    [[ -d "$dir" ]] || continue
    local name=$(basename "$dir")
    if [[ "$name" == *"$target"* ]] && mount | grep -q "$dir"; then
      umount "$dir" 2>/dev/null && ok "已卸载 $dir" || {
        warn "尝试强制卸载 $dir"
        umount -f "$dir" 2>/dev/null && ok "强制卸载成功" || err "卸载失败"
      }
      matched=true
    fi
  done

  $matched || err "未找到包含 '$target' 的活跃挂载"
}

# ── 挂载并启动 Claude ─────────────────────────────────────────────
bind_single() {
  local SSH_HOST="$1"
  local REMOTE_PATH="$2"
  local NO_CLAUDE="${3:-false}"
  local BIND_PASS="${4:-}"

  # 展开远程 ~
  if [[ "$REMOTE_PATH" == ~* ]]; then
    local REMOTE_HOME
    if [[ -n "$BIND_PASS" ]]; then
      REMOTE_HOME=$(sshpass -p "$BIND_PASS" ssh -o ConnectTimeout=10 "$SSH_HOST" 'echo $HOME' 2>/dev/null) \
        || err "无法连接到 $SSH_HOST"
    else
      REMOTE_HOME=$(ssh -o ConnectTimeout=10 "$SSH_HOST" 'echo $HOME' 2>/dev/null) \
        || err "无法连接到 $SSH_HOST"
    fi
    REMOTE_PATH="${REMOTE_PATH/#~/$REMOTE_HOME}"
  fi

  # 挂载目录
  SAFE_HOST=$(echo "$SSH_HOST" | tr '.:-' '___')
  MOUNT_DIR="$HOME/mnt/${SAFE_HOST}$(echo "$REMOTE_PATH" | tr '/' '_')"

  mkdir -p "$MOUNT_DIR"

  if mount | grep -q "$MOUNT_DIR"; then
    ok "已挂载：$MOUNT_DIR"
  else
    log "挂载 ${SSH_HOST}:${REMOTE_PATH} → ${MOUNT_DIR}"
    if [[ -n "$BIND_PASS" ]]; then
      echo "$BIND_PASS" | sshfs "${SSH_HOST}:${REMOTE_PATH}" "$MOUNT_DIR" \
        -o reconnect \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o follow_symlinks \
        -o auto_cache \
        -o Compression=no \
        -o volname="${SAFE_HOST}" \
        -o password_stdin \
        2>/dev/null || err "sshfs 挂载失败，请确认 SSH 别名可用：ssh $SSH_HOST"
    else
      sshfs "${SSH_HOST}:${REMOTE_PATH}" "$MOUNT_DIR" \
        -o reconnect \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o follow_symlinks \
        -o auto_cache \
        -o Compression=no \
        -o volname="${SAFE_HOST}" \
        2>/dev/null || err "sshfs 挂载失败，请确认 SSH 别名可用：ssh $SSH_HOST"
    fi
    ok "挂载成功：$MOUNT_DIR"
  fi

  # 写入 CLAUDE.md 上下文
  cat > "$MOUNT_DIR/CLAUDE.md" << CLAUDEEOF
# 服务器绑定上下文

你正在操作远程服务器 **${SSH_HOST}**，当前目录通过 sshfs 挂载到本地。

- **服务器**：${SSH_HOST}
- **远程路径**：${REMOTE_PATH}
- **本地挂载**：${MOUNT_DIR}

## 核心原则

**文件读写走挂载，命令执行走 SSH。**

- 挂载目录只包含源代码和配置文件（小文件），直接读写没有性能问题
- 训练、推理、数据处理等操作全部通过 SSH 在服务器端执行，大文件永远不经过本地
- 绝对不要通过挂载目录读写大文件（模型权重 / 数据集），改用 SSH 命令操作

## 操作规则

- **编辑代码 / 配置**：直接操作当前目录下的文件（等同于在服务器上编辑）
- **执行任何命令**：\`ssh ${SSH_HOST} "cd ${REMOTE_PATH} && <命令>"\`
- **查看 GPU**：\`ssh ${SSH_HOST} "nvidia-smi"\`
- **查看日志**：\`ssh ${SSH_HOST} "tail -f ${REMOTE_PATH}/out.log"\`
- **后台训练**：\`ssh ${SSH_HOST} "cd ${REMOTE_PATH} && nohup python train.py > out.log 2>&1 &"\`
- **tmux 长任务**：\`ssh ${SSH_HOST} "tmux new -d -s train 'cd ${REMOTE_PATH} && python train.py'"\`
- **查看大文件列表**：\`ssh ${SSH_HOST} "ls -lh ${REMOTE_PATH}/checkpoints/"\`（不要直接 ls 挂载目录下的大文件夹）
CLAUDEEOF

  ok "已写入 CLAUDE.md"

  # 如果是批量模式，不启动 Claude
  if [[ "$NO_CLAUDE" == "true" ]]; then
    return
  fi

  # tmux 布局
  if [[ -n "${TMUX:-}" ]]; then
    log "建立 tmux 布局（左=SSH交互 右=Claude）..."
    CURRENT_PANE=$(tmux display-message -p '#{pane_id}')

    tmux split-window -h -c "$MOUNT_DIR" "claude"
    tmux select-pane -t "$CURRENT_PANE"
    if [[ -n "$BIND_PASS" ]]; then
      tmux send-keys "sshpass -p '${BIND_PASS}' ssh -t ${SSH_HOST} 'cd ${REMOTE_PATH} && exec \$SHELL'" Enter
    else
      tmux send-keys "ssh -t ${SSH_HOST} 'cd ${REMOTE_PATH} && exec \$SHELL'" Enter
    fi

    ok "完成：左 pane = 服务器交互，右 pane = Claude 操作服务器文件"
  else
    log "未检测到 tmux，直接进入挂载目录启动 Claude"
    cd "$MOUNT_DIR" && exec claude
  fi
}

# ── 批量挂载所有服务器 ────────────────────────────────────────────
bind_all() {
  if [[ ! -f "$CONF_FILE" ]]; then
    err "找不到配置文件：$CONF_FILE"
  fi

  log "批量挂载所有服务器..."
  local count=0

  load_servers
  for a in "${ALIASES[@]}"; do
    local host="${HOSTS[$a]}"
    local remote_dir="${REMOTEDIRS[$a]}"
    local pass="${PASSWORDS[$a]:-}"

    log "挂载 ${CYAN}${a}${NC} (${host}:${remote_dir})..."
    bind_single "$host" "$remote_dir" "true" "$pass" || warn "跳过 $a（挂载失败）"
    count=$((count + 1))
  done

  echo ""
  ok "完成！共处理 $count 台服务器"
  show_status
}

# ── 主入口 ────────────────────────────────────────────────────────
case "${1:-}" in
  ""|"-h"|"--help")
    echo -e "\n${BOLD}bind-server.sh${NC} — 挂载远程服务器目录，Claude 本地管理\n"
    echo "用法："
    echo "  bind-server <ssh别名> <远程路径>    直接指定并挂载"
    echo "  bind-server <服务器别名>            从 servers.conf 读取配置"
    echo "  bind-server --all                   挂载所有 servers.conf 中的服务器"
    echo "  bind-server --unmount <别名>        卸载指定挂载"
    echo "  bind-server --unmount-all           卸载所有挂载"
    echo "  bind-server --status                查看挂载状态"
    echo ""
    echo "配置文件：$CONF_FILE"
    echo ""
    ;;
  "--all"|"-a")
    bind_all
    ;;
  "--unmount"|"-u")
    [[ -z "${2:-}" ]] && err "请指定要卸载的服务器"
    unmount_server "$2"
    ;;
  "--unmount-all")
    unmount_server "all"
    ;;
  "--status"|"-s")
    show_status
    ;;
  *)
    if [[ $# -ge 2 ]]; then
      bind_single "$1" "$2"
    elif lookup_server "$1"; then
      log "从 servers.conf 读取：$1 → ${LOOKUP_HOST}:${LOOKUP_DIR}"
      bind_single "$LOOKUP_HOST" "$LOOKUP_DIR" "false" "$LOOKUP_PASS"
    else
      err "用法：bind-server <ssh别名> <远程路径>\n  或在 servers.conf 中配置后：bind-server <别名>"
    fi
    ;;
esac
