# SuperShell & 工作区模板

## SuperShell — 交互式会话管理器

### 启动方式

```bash
# 方式 1：命令行
supershell

# 方式 2：tmux 快捷键（推荐，弹窗模式）
Ctrl-w S
```

### 界面说明

```
╭──── ⚡ SuperShell ────────────────────────────────────────────╮
│                                    │                          │
│  ❯ 搜索...                        │  ═══ Session: dev ═══    │
│                                    │                          │
│  ━━━━ 本地 Sessions (3) ━━━━      │  Windows:                │
│  ● dev          2 windows attached │    [1] code ◀ active     │
│  ○ robot        1 windows          │    [2] git               │
│  ○ train        3 windows          │                          │
│                                    │  Panes:                  │
│  ━━━━ 远程服务器 (2) ━━━━          │    1.1 zsh  120x40      │
│  ◆ liyufeng_4090  gpu-4090         │    1.2 claude 60x40     │
│  ◆ liyufeng_a100  gpu-a100         │                          │
│                                    │  Output:                 │
│  ━━━━ 快捷操作 ━━━━                │    $ python train.py     │
│  ⚡ new-session   创建新 session    │    Epoch 3/10 loss=0.42  │
│  ⚡ monitor       启动监控面板       │    ...                   │
│                                    │                          │
╰────────────────────────────────────┴──────────────────────────╯
  ↑↓ 选择  Enter 执行  Ctrl-M 监控  Ctrl-R 刷新  Esc 退出
```

### 支持的操作

**选择 Session**：Enter 切换到该 session

**选择服务器**：Enter 在新 window 中 SSH + tmux 登录

**快捷操作**：

| 操作 | 说明 |
|------|------|
| new-session | 创建新的命名 tmux session |
| new-window | 在当前 session 新建 window |
| vsplit | 纵向分屏（左右）|
| hsplit | 横向分屏（上下）|
| monitor | 启动多服务器监控面板 |
| bind-all | sshfs 挂载所有服务器 |
| mount-status | 查看挂载状态 |
| reconnect | 重连所有断开的挂载 |
| reload | 重载 tmux 配置 |

### 预览面板

- **Session**：显示 windows、panes、最近输出
- **服务器**：实时探测在线状态、GPU 使用、tmux sessions、负载
- **操作**：显示操作说明

---

## 工作区模板 — setup-workspace

### 启动

```bash
# 交互式选择（fzf）
setup-workspace

# 直接指定模板
setup-workspace <模板名> [参数]
```

### 可用模板

#### dev — 标准开发布局

```bash
setup-workspace dev [session名] [工作目录]
```

布局：

```
┌──────────────────────┬──────────────────┐
│                      │                  │
│   代码编辑 / 终端    │   Claude Code    │
│      （主工作区）    │                  │
├──────────────────────┤                  │
│   日志 / 测试        │                  │
└──────────────────────┴──────────────────┘
```

包含：
- Window 1 (code)：三格布局
- Window 2 (git)：lazygit

#### train — 远程训练布局

```bash
setup-workspace train [服务器别名]
```

不指定服务器时会弹出 fzf 选择器。

包含：
- Window 1 (ssh)：SSH 到服务器，自动 tmux
- Window 2 (monitor)：服务器资源监控
- Window 3 (claude)：bind-server 挂载 + Claude

#### multi — 多服务器并行

```bash
setup-workspace multi
```

从 servers.conf 读取所有服务器。

包含：
- Window 1 (monitor)：全局监控面板
- Window 2~N：每台服务器一个 window

#### claude — Claude Code 专用

```bash
setup-workspace claude [工作目录]
```

包含：
- Window 1 (main)：Claude 全屏
- Window 2 (term)：终端
- Window 3 (git)：lazygit

---

## tmux 新增快捷键

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `Ctrl-w S` | SuperShell | 弹窗式交互面板 |
| `Ctrl-w M` | Server Monitor | 弹窗式监控面板 |
| `Ctrl-w L` | Quick Login | 弹窗式服务器选择 |

---

## 健康检查 — health-check

```bash
# 一次性检查
health-check

# 只检查某台
health-check liyufeng_4090

# 持续监控（默认 60s 一次）
health-check --watch

# 自定义间隔
health-check --watch --interval 30

# JSON 输出（给其他工具用）
health-check --json
```

### 检查项和阈值

| 检查项 | 警告 | 严重 |
|--------|------|------|
| GPU 温度 | ≥85°C | ≥90°C |
| GPU 显存 | ≥95% | — |
| 内存使用率 | ≥90% | — |
| 根分区磁盘 | ≥85% | ≥95% |
| Home 磁盘 | ≥85% | ≥95% |
| Zombie 进程 | >5 个 | — |
| SSH 连通性 | — | 无法连接 |

严重告警时（macOS）会弹出系统通知。
