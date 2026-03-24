# 远程 SSH + 本地 Claude Code 统一工作流

> **核心原则**：Claude Code 始终运行在本地，通过 sshfs 挂载远程目录，
> 体验与「在服务器上直接开 Claude」完全一致。

---

## 方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| **sshfs 挂载 + bind-server（推荐）** | 编辑文件无感，体验等同本地；配置/历史统一在本地 | 需要 macFUSE，首次安装要重启 Mac |
| 本地 Claude + SSH 命令 | 零安装 | 每次操作文件需手写 SSH 前缀 |
| 服务器装 Claude | Claude 直接读写远程文件 | 需每台服务器配置 API key，历史分散 |

---

## 一键安装（macOS）

### 1. 安装 macFUSE + sshfs

```bash
brew install --cask macfuse          # 安装内核扩展，需要重启 Mac
brew install gromgit/fuse/sshfs-mac  # 安装后可直接使用
```

重启 Mac 后，进入「系统设置 → 隐私与安全」滚到底，点「允许」macFUSE 内核扩展。

### 2. 配置 SSH ControlMaster（连接复用）

在 `~/.ssh/config` **开头**加入：

```ini
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm/%r@%h:%p
    ControlPersist 10m
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

创建 socket 目录：

```bash
mkdir -p ~/.ssh/cm
```

效果：第一次 `ssh robot` 建立连接后，后续所有 `ssh robot "cmd"` 自动复用该连接，无需重新认证，Claude 执行远程命令速度极快。

### 3. 配置服务器别名

```ini
# ~/.ssh/config
Host my-server
  HostName 192.168.1.100
  User liyufeng
  Port 22
```

---

## bind-server：一键绑定服务器

`scripts/bind-server.sh` 是核心脚本，一条命令完成：

1. sshfs 挂载远程目录到本地 `~/mnt/`
2. 写入 `CLAUDE.md` 告知 Claude 上下文规则
3. 在 tmux 里自动建立左右布局：
   - **左 pane** → SSH 交互会话（你操作）
   - **右 pane** → 本地 Claude，工作目录 = 挂载目录（AI 操作）

```bash
bash scripts/bind-server.sh <ssh别名> <远程路径>

# 示例
bash scripts/bind-server.sh my-server ~/projects/nav
```

建议加 alias 简化调用：

```bash
# ~/.zshrc
alias bind-server="bash ~/tmux-ai/scripts/bind-server.sh"
```

之后直接：

```bash
bind-server my-server ~/projects/nav
```

### 布局效果

```
┌──────────────────────┬───────────────────────┐
│                      │                       │
│   SSH 交互会话        │   本地 Claude Code    │
│   cd ~/projects/nav  │   工作目录 = 挂载目录  │
│   （你操作）          │   （AI 操作服务器文件）│
│                      │                       │
└──────────────────────┴───────────────────────┘
```

---

## 大文件注意事项

**文件读写走挂载，命令执行走 SSH。**

- sshfs 挂载目录只用于**源代码和配置文件**（小文件），直接读写没有性能问题
- 训练、推理、数据处理等操作全部通过 SSH 在服务器端执行，**大文件永远不经过本地网络**
- 模型权重 / 数据集等大文件，让 Claude 用 SSH 命令在服务器端操作：

```bash
# Claude 执行（不走挂载）
ssh my-server "cd ~/projects/nav && python train.py"
ssh my-server "ls -lh ~/data/checkpoints/"
ssh my-server "tail -f ~/projects/nav/out.log"
```

---

## 多服务器并行管理

每台服务器开一个 tmux window，用 bind-server 绑定：

```bash
# window 1：绑定 GPU 服务器 A
bind-server server-a ~/projects/train

# window 2（Ctrl-w c）：绑定 GPU 服务器 B
bind-server server-b ~/projects/eval
```

ControlMaster 保证每个 window 的 Claude pane 执行 SSH 命令时共享已有连接，无额外认证开销。

---

## 卸载挂载目录

```bash
# 卸载指定挂载点
umount ~/mnt/my-server__projects_nav

# 或强制卸载（连接已断开时）
diskutil unmount force ~/mnt/my-server__projects_nav
```

---

## 保持 SSH 连接稳定

长时间运行任务时，即使 SSH 断开，远程服务器上的任务仍在 tmux session 里运行：

```bash
# 断线后重连，恢复远程 session
ssh my-server
tmux attach   # 或 tmux ls 查看所有 session
```

---

## Claude Code 配置同步

Claude Code 的配置和历史存储在本地 `~/.claude/`，完全在你的机器上，无需同步到服务器。

> API key 不要提交到 git，通过环境变量或手动配置管理。
