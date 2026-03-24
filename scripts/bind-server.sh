#!/usr/bin/env bash
# bind-server.sh — 挂载远程服务器目录，在挂载目录里启动 Claude
#
# 用法：
#   bash bind-server.sh <ssh别名> <远程路径>
#
# 示例：
#   bash bind-server.sh robot ~/projects/nav
#   bash bind-server.sh nas.zgca.com /data/experiments

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[bind-server]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── 参数检查 ───────────────────────────────────────────────────────────────
[[ $# -lt 2 ]] && { echo "用法: bind-server.sh <ssh别名> <远程路径>"; exit 1; }

SSH_HOST="$1"
REMOTE_PATH="$2"

# 展开远程 ~
if [[ "$REMOTE_PATH" == ~* ]]; then
  REMOTE_HOME=$(ssh "$SSH_HOST" 'echo $HOME' 2>/dev/null) || err "无法连接到 $SSH_HOST"
  REMOTE_PATH="${REMOTE_PATH/#~/$REMOTE_HOME}"
fi

# ── 挂载目录 ───────────────────────────────────────────────────────────────
SAFE_HOST=$(echo "$SSH_HOST" | tr '.:-' '___')
MOUNT_DIR="$HOME/mnt/${SAFE_HOST}$(echo "$REMOTE_PATH" | tr '/' '_')"

mkdir -p "$MOUNT_DIR"

if mount | grep -q "$MOUNT_DIR"; then
  ok "已挂载：$MOUNT_DIR"
else
  log "挂载 ${SSH_HOST}:${REMOTE_PATH} → ${MOUNT_DIR}"
  sshfs "${SSH_HOST}:${REMOTE_PATH}" "$MOUNT_DIR" \
    -o reconnect \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o follow_symlinks \
    -o auto_cache \
    -o Compression=no \
    -o volname="${SAFE_HOST}" \
    2>/dev/null || err "sshfs 挂载失败，请确认 SSH 别名可用：ssh $SSH_HOST"
  ok "挂载成功：$MOUNT_DIR"
fi

# ── 写入 CLAUDE.md 上下文 ──────────────────────────────────────────────────
cat > "$MOUNT_DIR/CLAUDE.md" << CLAUDEEOF
# 服务器绑定上下文

你正在操作远程服务器，当前目录通过 sshfs 透明挂载，读写文件等同于在服务器上直接操作。

- **服务器**：${SSH_HOST}
- **远程路径**：${REMOTE_PATH}
- **本地挂载**：${MOUNT_DIR}

## 操作规则

- **读写文件**：直接操作当前目录下的文件即可，无需任何 SSH 前缀
- **执行命令**：用 \`ssh ${SSH_HOST} "cd ${REMOTE_PATH} && <命令>"\` 在服务器上运行
- **查看 GPU**：\`ssh ${SSH_HOST} "nvidia-smi"\`
- **查看进程**：\`ssh ${SSH_HOST} "ps aux | grep python"\`
- **后台任务**：\`ssh ${SSH_HOST} "cd ${REMOTE_PATH} && nohup python train.py > out.log 2>&1 &"\`
- **tmux 任务**：\`ssh ${SSH_HOST} "tmux new -d -s train 'cd ${REMOTE_PATH} && python train.py'"\`
CLAUDEEOF

ok "已写入 CLAUDE.md"

# ── tmux 布局 ──────────────────────────────────────────────────────────────
if [[ -n "$TMUX" ]]; then
  log "建立 tmux 布局（左=SSH交互 右=Claude）..."
  CURRENT_PANE=$(tmux display-message -p '#{pane_id}')

  # 右侧启动 Claude，工作目录 = 挂载目录
  tmux split-window -h -c "$MOUNT_DIR" "claude"

  # 左侧连接服务器，进入远程路径
  tmux select-pane -t "$CURRENT_PANE"
  tmux send-keys "ssh -t ${SSH_HOST} 'cd ${REMOTE_PATH} && exec \$SHELL'" Enter

  ok "完成：左 pane = 服务器交互，右 pane = Claude 操作服务器文件"
else
  # 不在 tmux，直接进挂载目录启动 Claude
  log "未检测到 tmux，直接进入挂载目录启动 Claude"
  cd "$MOUNT_DIR" && exec claude
fi
