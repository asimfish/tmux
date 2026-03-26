# 快速登录 & 多服务器监控

## login — 一键 SSH + 远程 tmux

### 为什么需要

直接 SSH 到服务器有两个问题：
1. 关掉本机终端或断网，服务器上的进程（训练、推理）就没了
2. 每次都要 `ssh xxx` → `cd xxx` → `tmux attach`，步骤重复

`login` 解决这两个问题：一条命令完成 SSH + cd + tmux attach/create。

### 用法

```bash
# 先配置 servers.conf（见 server-config.md）

# 查看可用服务器
login --list

# 登录
login liyufeng_4090
```

### 工作流程

```
login liyufeng_4090
       │
       ▼
  SSH 连接到 gpu-4090
       │
       ▼
  cd ~/projects
       │
       ▼
  ┌─ 远程有 tmux session "liyufeng_4090"？
  │
  ├─ 是 → tmux attach（恢复之前的窗口和进程）
  │
  └─ 否 → tmux new-session -s liyufeng_4090
```

### 日常使用场景

**场景 1：启动训练后安心离开**

```bash
login liyufeng_4090           # 登录服务器
# 在 tmux 里启动训练
python train.py
# Ctrl-w d  退出 tmux（训练继续跑）
# 关掉电脑，去吃饭
```

**场景 2：第二天回来查看进度**

```bash
login liyufeng_4090           # 自动 attach 到昨天的 session
# 训练输出还在，直接看结果
```

**场景 3：在 Claude Code 中使用**

在 Claude Code 对话中直接说：

> 帮我登录 liyufeng_4090 检查一下训练进度

Claude 会执行：`bash ~/tmux-ai/scripts/login.sh liyufeng_4090`

---

## server-monitor — 多服务器资源监控

### 为什么需要

管理多台 GPU 服务器时，经常需要：
- 哪台机器有空闲 GPU？
- 训练还在跑吗？
- 磁盘快满了吗？

`server-monitor` 一个面板看所有服务器状态。

### 用法

```bash
# 持续刷新（默认 10 秒）
smon

# 查一次就退
smon --once

# 自定义刷新间隔
smon --interval 5

# 只看某台
smon liyufeng_4090
```

### 监控内容

| 指标 | 来源 | 说明 |
|------|------|------|
| GPU 使用率 | `nvidia-smi` | 每张卡的利用率、显存、温度、功耗 |
| CPU | `/proc/loadavg` | 负载和核心数 |
| 内存 | `/proc/meminfo` | 已用 / 总量 |
| 磁盘 | `df` | 主目录占用 |
| tmux sessions | `tmux list-sessions` | 远程正在跑的 tmux 会话 |
| 连接状态 | SSH 连通性 | 在线(绿) / 离线(红) |

### 特性

- **并行采集**：所有服务器同时查询，不会因为一台慢或离线卡住
- **彩色进度条**：绿色 < 50%、黄色 50-80%、红色 > 80%
- **离线检测**：连不上的服务器标红，不影响其他
- **SSH 超时 8 秒**：避免长时间等待

### 在 tmux 中常驻

建议用一个专门的 tmux session 跑监控：

```bash
tmux new -s monitor
smon

# Ctrl-w d 随时退出，监控暂停
# tmux attach -t monitor 回来看
```

或者在工作 session 里开一个小 pane：

```bash
# 在当前 session 底部分一个窄条
Ctrl-w -
smon --interval 30
```

### 结合 Claude 使用

在 Claude Code 中：

> 帮我检查下所有服务器的 GPU 使用情况

Claude 会执行 `bash ~/tmux-ai/scripts/server-monitor.sh --once`，然后告诉你结果。

---

## 三个命令的分工

| 命令 | 用途 | 你在哪 |
|------|------|--------|
| `login <别名>` | SSH 到服务器，在**远程** tmux 里工作 | 人在服务器终端 |
| `smon` | 在本地看所有服务器状态 | 人在本机 |
| `bind-server <别名>` | 挂载远程目录，用**本地** Claude 管理 | Claude 在本机，操作远程文件 |

选择建议：
- **要在服务器上交互操作** → `login`
- **要让本地 Claude 管理服务器代码** → `bind-server`
- **要看全局状态** → `smon`
