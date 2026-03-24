# 远程 SSH + 本地 Claude Code 统一工作流

> **核心原则**：Claude Code 始终运行在本地，SSH 连接放在旁边的 pane。
> 配置、历史、API key 全在本地，无需在服务器上重复配置。

---

## 为什么这样做

| 方案 | 优点 | 缺点 |
|------|------|------|
| **本地 Claude + SSH pane（推荐）** | 配置/历史完全统一，无需服务器装 claude | 需要通过 SSH 命令操作远程文件 |
| 服务器装 Claude | Claude 直接读写远程文件 | 需每台服务器配置 API key，历史分散 |
| sshfs 挂载 | 本地 Claude 直接读写远程文件 | 网络延迟影响体验，连接断开会卡住 |

---

## 推荐布局

```
┌──────────────────────┬───────────────────┐
│                      │                   │
│   SSH 到远程服务器    │   本地 Claude     │
│   （跑代码 / GPU）   │   （AI 助手）      │
│                      │                   │
├──────────────────────┴───────────────────┤
│           本地日志 / 文件对比             │
└──────────────────────────────────────────┘
```

搭建步骤：

```bash
# 1. 新建 session
tmux new -s robot

# 2. 左右分栏
Ctrl-w |      # 或 Cmd+D

# 3. 左侧：SSH 到服务器
Ctrl-w h
ssh user@your-server

# 4. 右侧：本地启动 Claude Code
Ctrl-w l
claude
```

---

## 让本地 Claude 操作远程文件

### 方式一：让 Claude 通过 SSH 命令操作（最简单）

直接告诉 Claude 用 SSH 执行命令：

```
claude> 帮我查看服务器上 ~/robot/src/nav.py 的内容
        服务器地址是 user@192.168.1.100
```

Claude 会自动执行：
```bash
ssh user@192.168.1.100 cat ~/robot/src/nav.py
```

### 方式二：配置 SSH 别名（推荐）

在本地 `~/.ssh/config` 里配置好服务器别名，让操作更简洁：

```ini
# ~/.ssh/config
Host robot
    HostName 192.168.1.100
    User liyufeng
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

之后告诉 Claude：
```
claude> 服务器别名是 robot，帮我修改 ~/src/controller.py
```

Claude 执行：
```bash
ssh robot cat ~/src/controller.py
ssh robot "echo '...' > ~/src/controller.py"
```

### 方式三：rsync 同步（适合大量文件操作）

把远程项目目录同步到本地，Claude 直接操作本地文件，完成后推回：

```bash
# 拉取远程文件到本地
rsync -avz robot:~/projects/nav/ ~/local/nav/

# Claude 在本地修改后，推回服务器
rsync -avz ~/local/nav/ robot:~/projects/nav/
```

可以在 tmux 底部 pane 挂一个监控，自动同步：
```bash
# 监听本地文件变化，自动推送（需要 fswatch）
brew install fswatch
fswatch -o ~/local/nav/ | xargs -n1 -I{} rsync -avz ~/local/nav/ robot:~/projects/nav/
```

---

## 实战场景

### 场景一：Claude 帮你调试远程训练代码

```bash
# 左侧 pane：SSH 查看训练日志
ssh robot
tail -f ~/train/logs/train.log

# 右侧 pane：告诉 Claude
claude> 服务器 robot 上 ~/train/logs/train.log 显示 loss 不收敛，
        帮我查看 ~/train/src/model.py 并分析原因
```

Claude 会 SSH 读取文件，分析后给出修改建议，你在左侧 pane 直接应用。

### 场景二：本地写代码，远程跑验证

```bash
# 右侧 Claude pane
claude> 帮我实现 src/nav/astar.py 的 A* 算法

# Claude 在本地写好后，左侧 pane 推送并运行
rsync -avz src/ robot:~/robot/src/
ssh robot python ~/robot/src/nav/astar.py
```

### 场景三：多台服务器统一管理

```bash
# 每台服务器开一个 window，Claude 在独立 pane 统一指挥
tmux new -s servers

Ctrl-w c → Ctrl-w , → "gpu-1"   # ssh gpu1
Ctrl-w c → Ctrl-w , → "gpu-2"   # ssh gpu2
Ctrl-w c → Ctrl-w , → "claude"  # 本地 Claude，管理所有服务器
```

---

## 保持 SSH 连接稳定

长时间运行任务时，SSH 连接可能断开。tmux 的 session 保活 + SSH 配置组合解决这个问题：

```ini
# ~/.ssh/config 加入
Host *
    ServerAliveInterval 60      # 每 60 秒发心跳
    ServerAliveCountMax 10      # 最多重试 10 次
    TCPKeepAlive yes
```

即使 SSH 断开，远程服务器上的任务仍在 tmux session 里运行：

```bash
# 断线后重连，恢复远程 session
ssh robot
tmux attach   # 或 tmux ls 查看所有 session
```

---

## Claude Code 历史与配置同步

Claude Code 的配置和历史存储在本地 `~/.claude/`，完全在你的机器上，无需同步到服务器。

如果你在多台 Mac 之间工作，可以用本仓库的脚本同步配置：

```bash
# 导出本地 Claude 配置（不含对话历史）
cp ~/.claude/settings.json ~/tmux-ai/claude-settings.json

# 在另一台 Mac 上导入
cp ~/tmux-ai/claude-settings.json ~/.claude/settings.json
```

> API key 不要提交到 git，通过环境变量或手动配置管理。
