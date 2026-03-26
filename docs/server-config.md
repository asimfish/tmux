# 服务器配置指南

## servers.conf 配置

`servers.conf` 是所有服务器管理功能的核心配置文件。login、server-monitor、bind-server 三个命令都从这里读取服务器信息。

### 快速开始

```bash
cd ~/tmux-ai
cp servers.conf.example servers.conf
vim servers.conf
```

### 配置格式

每行一台服务器，`#` 开头为注释：

```
别名  SSH地址  远程工作目录  描述（可选）
```

| 字段 | 说明 | 示例 |
|------|------|------|
| 别名 | 你用来操作的名字，建议有意义 | `liyufeng_4090` |
| SSH地址 | 对应 `~/.ssh/config` 的 Host，或 `user@ip` | `gpu-4090` 或 `liyufeng@10.0.0.1` |
| 远程工作目录 | 登录后自动 cd 到的目录，支持 `~` | `~/projects` |
| 描述 | 可选，显示在 list 和监控面板中 | `4090训练服务器` |

### 完整示例

```
# ── GPU 服务器 ─────────────────────────────────
liyufeng_4090    gpu-4090       ~/projects          4090训练服务器
liyufeng_a100    gpu-a100       ~/experiments       A100实验服务器

# ── 实验室服务器 ───────────────────────────────
lab_server       lab            ~/workspace         实验室公共服务器
lab_storage      lab-nas        /data/datasets      数据存储服务器

# ── 云服务器 ───────────────────────────────────
aws_p4d          aws-gpu        ~/train             AWS p4d.24xlarge
```

### 环境变量

可以用 `SERVERS_CONF` 环境变量指定配置文件路径：

```bash
SERVERS_CONF=~/my-servers.conf login --list
```

默认路径是仓库根目录的 `servers.conf`。

---

## SSH 免密登录配置

### 第一步：生成密钥

```bash
# 如果已有 ~/.ssh/id_ed25519 则跳过
ssh-keygen -t ed25519 -C "your_email@example.com"
```

### 第二步：复制公钥到服务器

```bash
ssh-copy-id user@服务器IP

# 如果端口不是 22
ssh-copy-id -p 2222 user@服务器IP
```

### 第三步：配置 SSH 别名（推荐）

编辑 `~/.ssh/config`：

```
# 全局设置：复用连接，大幅加速后续 SSH 操作
Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
    ServerAliveInterval 30
    ServerAliveCountMax 3

# ── GPU 服务器 ─────────────────────────────────
Host gpu-4090
    HostName 192.168.1.100
    User liyufeng
    Port 22

Host gpu-a100
    HostName 10.0.0.50
    User liyufeng
    Port 22

# ── 实验室服务器 ───────────────────────────────
Host lab
    HostName lab.university.edu
    User liyufeng
    Port 22

# ── 需要跳板机的服务器 ─────────────────────────
Host internal-gpu
    HostName 192.168.100.10
    User liyufeng
    ProxyJump jump-server
```

创建 socket 目录：

```bash
mkdir -p ~/.ssh/sockets
```

### 第四步：验证

```bash
# 应该不需要输密码
ssh gpu-4090 "echo ok"
```

---

## 多服务器管理策略

### 按用途分组

建议在 `servers.conf` 中用注释分组，按用途组织：

```
# ── 日常开发 ───────────────────────────────────
dev_4090         gpu-4090       ~/projects

# ── 大规模训练 ─────────────────────────────────
train_a100_1     gpu-a100-1     ~/train
train_a100_2     gpu-a100-2     ~/train

# ── 推理服务 ───────────────────────────────────
infer_server     infer          ~/serve
```

### 配合 tmux 使用

```bash
# 一台服务器一个 window
tmux new -s servers
login liyufeng_4090              # window 1

Ctrl-w c                         # 新建 window
login liyufeng_a100              # window 2

# 用 Ctrl-w n/p 切换
# 用 server-monitor 在另一个 session 监控
```

### 安全建议

- **不要**在 `servers.conf` 中写密码或密钥路径
- SSH 密钥建议设置密码短语，配合 ssh-agent 使用
- `servers.conf` 已在 `.gitignore` 中（如果你 fork 了仓库），避免提交私有服务器信息
