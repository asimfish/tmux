# bind-server：一键绑定远程服务器

> 把远程服务器的某个目录「挂载」到本地，然后在这个目录里启动 Claude。
> 对 Claude 来说，它就在那个目录里工作；对你来说，旁边的 pane 是一个正常的 SSH 会话。

---

## 工作原理

### 三个关键技术的组合

```
你的 Mac
────────────────────────────────────────────────────────

  ~/mnt/my-server__projects_nav/     ← sshfs 挂载点
  ├── train.py                        ↕ 透明同步
  ├── config.yaml                     ↕
  └── CLAUDE.md  ← 告诉 Claude 上下文规则

  本地 Claude Code
  工作目录 = ~/mnt/my-server__projects_nav/
  读文件 → 等同于 ssh my-server cat ~/projects/nav/train.py
  写文件 → 等同于 ssh my-server 写入文件

  SSH ControlMaster socket
  ~/.ssh/cm/liyufeng@my-server:22
  → Claude 执行 ssh my-server "cmd" 时复用已有连接，毫秒级响应

远程服务器 my-server
────────────────────────────────────────────────────────
  ~/projects/nav/
  ├── train.py      ← Claude 直接编辑这里
  ├── config.yaml
  └── checkpoints/  ← 大文件，Claude 用 SSH 命令操作，不走挂载
```

### 1. sshfs（文件系统层）

sshfs 基于 FUSE（Filesystem in Userspace），通过 SSH 协议将远程目录挂载为本地文件系统。

- **读文件**：本地进程 `open(file)` → FUSE → SSH → 服务器返回内容
- **写文件**：本地进程 `write(file)` → FUSE → SSH → 服务器写入磁盘
- **对 Claude 完全透明**：Claude 用普通文件 API 读写，感知不到 SSH 的存在

挂载选项说明：

```
reconnect          断线后自动重连，不影响已挂载的目录
ServerAliveInterval=15   每 15 秒发心跳，检测连接
follow_symlinks    跟随符号链接（服务器上常见 data -> /data/shared）
auto_cache         文件未改变时使用本地缓存，加速读取
Compression=no     小文件传输关闭压缩，降低 CPU 开销
```

### 2. SSH ControlMaster（连接复用层）

没有 ControlMaster 时，每次 `ssh my-server "cmd"` 都需要：
- TCP 握手 + SSH 密钥交换 + 认证 ≈ 1-3 秒

有 ControlMaster 后：
- 第一次建立连接创建 socket 文件 `~/.ssh/cm/liyufeng@my-server:22`
- 后续所有连接复用这个 socket，跳过握手 ≈ 50ms

Claude 在右侧 pane 执行大量 `ssh my-server "cmd"` 时，完全不影响你在左侧 pane 的交互体验，两者共享同一个底层 TCP 连接。

### 3. CLAUDE.md（上下文注入层）

bind-server 在挂载目录里自动写入 `CLAUDE.md`，Claude Code 启动时会自动读取它。

这个文件告诉 Claude：
- 当前服务器是谁、远程路径在哪
- **文件读写走挂载**（直接操作即可）
- **命令执行走 SSH**（`ssh my-server "cd path && cmd"`）
- 大文件不要通过挂载读写

这样 Claude 无需用户每次提示，自动按正确方式工作。

---

## 安装

### 1. 安装 macFUSE

```bash
brew install --cask macfuse
```

安装完成后**必须重启 Mac**，然后：
「系统设置」→「隐私与安全」→ 滚到底部 → 点「允许」macFUSE 内核扩展

> macFUSE 是 macOS 内核扩展，让用户态程序（sshfs）能挂载自定义文件系统。不需要在服务器上安装任何东西。

### 2. 安装 sshfs

```bash
brew install gromgit/fuse/sshfs-mac
```

### 3. 配置 SSH ControlMaster

在 `~/.ssh/config` **开头**加入（本仓库 install.sh 已自动配置）：

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

### 4. 配置服务器别名

```ini
# ~/.ssh/config
Host my-server
  HostName 192.168.1.100
  User liyufeng
  Port 22
```

验证能正常连接：

```bash
ssh my-server "echo ok"
```

---

## 使用

### 基本用法

在 tmux 里执行：

```bash
bash scripts/bind-server.sh <ssh别名> <远程路径>
```

**示例：**

```bash
# 绑定到 GPU 服务器的训练目录
bash scripts/bind-server.sh my-server ~/projects/train

# 绑定到另一台服务器的数据处理目录
bash scripts/bind-server.sh nas-server /data/experiments/run01
```

### 加 alias（推荐）

```bash
# ~/.zshrc
alias bind-server="bash ~/tmux-ai/scripts/bind-server.sh"
```

之后直接：

```bash
bind-server my-server ~/projects/train
```

### 执行效果

脚本会自动：

1. 将 `my-server:~/projects/train` 挂载到 `~/mnt/my-server__projects_train/`
2. 在挂载目录写入 `CLAUDE.md`
3. 当前 tmux window 分为左右两个 pane：

```
┌──────────────────────────┬─────────────────────────┐
│                          │                         │
│   SSH 到 my-server        │   本地 Claude Code      │
│   cd ~/projects/train    │   工作目录 =             │
│                          │   ~/mnt/my-server__...  │
│   你在这里交互            │   AI 在这里读写文件      │
│                          │   执行命令走 SSH         │
└──────────────────────────┴─────────────────────────┘
```

---

## 操作规范

### 文件操作（直接读写，走挂载）

Claude 直接操作文件，无需任何前缀：

```
claude> 修改 config.yaml 里的 learning_rate 为 1e-4
claude> 在 train.py 里加上 early stopping 逻辑
claude> 读一下 src/model.py 告诉我模型结构
```

### 命令执行（走 SSH）

Claude 自动用 `ssh my-server "cd path && cmd"` 格式：

```bash
# 启动训练
ssh my-server "cd ~/projects/train && python train.py"

# 查看 GPU 使用
ssh my-server "nvidia-smi"

# 查看实时日志
ssh my-server "tail -f ~/projects/train/out.log"

# 后台长任务（不怕断线）
ssh my-server "cd ~/projects/train && tmux new -d -s train 'python train.py 2>&1 | tee out.log'"

# 查看进程
ssh my-server "ps aux | grep python"
```

### 大文件规则

| 操作 | 正确做法 | 错误做法 |
|------|----------|----------|
| 查看 checkpoint 列表 | `ssh my-server "ls -lh ~/projects/train/checkpoints/"` | `ls ~/mnt/.../checkpoints/`（会触发网络传输） |
| 复制数据集到另一台服务器 | `ssh my-server "cp /data/dataset /data2/dataset"` | 通过挂载目录复制 |
| 下载模型权重 | `ssh my-server "wget ... -O model.bin"` | 通过挂载写入 |

---

## 多服务器并行

每台服务器开一个 tmux window：

```bash
# 先建好 session
tmux new -s servers

# Window 1：绑定 GPU-A（当前 window）
bind-server gpu-a ~/projects/train

# 新建 Window 2：绑定 GPU-B
Ctrl-w c
bind-server gpu-b ~/projects/eval

# 新建 Window 3：绑定数据服务器
Ctrl-w c
bind-server nas-server /data/raw
```

ControlMaster 保证三个 window 的 Claude pane 执行 SSH 命令时共享连接，无额外认证开销。

---

## 卸载挂载

```bash
# 正常卸载
umount ~/mnt/my-server__projects_train

# 强制卸载（网络已断开时）
diskutil unmount force ~/mnt/my-server__projects_train
```

---

## 常见问题

### sshfs 挂载失败

```
[✗] sshfs 挂载失败，请确认 SSH 别名可用：ssh my-server
```

排查步骤：

```bash
# 1. 确认 SSH 别名可用
ssh my-server "echo ok"

# 2. 确认 macFUSE 内核扩展已允许
# 系统设置 → 隐私与安全 → 允许 macFUSE

# 3. 确认 sshfs 版本
sshfs --version
```

###