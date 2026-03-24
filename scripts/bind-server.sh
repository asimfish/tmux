#!/usr/bin/env bash
# bind-server.sh — 挂载远程服务器目录，在挂载目录里启动 Claude
#
# 用法：
#   bind-server.sh <ssh别名> <远程路径>
#
# 示例：
#   bind-server.sh robot ~/projects/nav
#   bind-server.sh nas.zgca.com /data/experiments
#
# 效果：
#   1. 将服务器目录 sshfs 挂载到本地 ~/mnt/<别名>/
#   2. 在当前 tmux window 建立左右布局：
#      左 pane → ssh 交互会话（你用）
#      右 pane → 本地 claude，工作目录 = 挂载目录（AI 用）
#   3. Claude 读写文件 = 直接操作服务器文件，命令走 ControlMaster 秒连

set -e

# ── 参数检查 ──────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo