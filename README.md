# tmux × AI — 用 tmux 高效管理 Claude Code、Codex、OpenClaw

> 一份开源工作流指南，帮你从零搭建 **Ghostty + tmux + AI 工具** 的完整终端工作流，让多个 AI 在后台并行工作，你专注于真正重要的事。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

---

## 一键部署

```bash
git clone https://github.com/asimfish/tmux.git ~/tmux-ai
bash ~/tmux-ai/install.sh
```

安装内容：Ghostty 终端、tmux + 插件、starship / fzf / zoxide / eza / bat / lazygit 等配套工具，以及本仓库的 `.tmux.conf` 配置。

---

## 完整工具链

```mermaid
graph LR
    G["🖥 Ghostty\nGPU 加速终端"] -->|"SSH / 本地"| T["📦 tmux\n会话管理器"]
    T --> S1["Session: work"]
    T --> S2["Session: robot"]
    T --> S3["Session: exp"]

    S1 --> W1["Window: frontend"]
    S1 --> W2["Window: backend"]
    S2 --> W3["Window: nav"]
    S2 --> W4["Window: vision"]

    W1 --> P1["Pane: 代码"]
    W1 --> P2["Pane: Claude Code"]
    W1 --> P3["Pane: 日志"]

    W3 --> AI2["Codex 批量任务"]
    W4 --> AI3["OpenClaw 长任务"]
```

**一句话记住三层结构：**
> **Session** = 工作台　**Window** = 项目　**Pane** = 角色

---

## 第一步：Ghostty 终端

Ghostty 是 GPU 加速的现代终端，macOS 上用 Metal 渲染，启动极快。

### 安装

```bash
brew install --cask ghostty
brew install --cask font-jetbrains-mono-nerd-font
```

### 核心快捷键

**Quick Terminal（最实用功能）**

```
Cmd+Shift+`     全局呼出 / 隐藏下拉终端（任意 App 均可触发）
```

> 从屏幕顶部滑出，按一下消失，再按一下恢复，状态保留。适合随时查看 AI 输出。

**标签页 & 窗口**

| 快捷键 | 功能 |
|--------|------|
| `Cmd+T` | 新建标签页 |
| `Cmd+W` | 关闭当前标签页 |
| `Cmd+数字` | 跳转第 N 个标签页 |
| `Cmd+Shift+[/]` | 上 / 下一个标签页 |
| `Cmd+N` | 新建窗口 |

**分屏**

| 快捷键 | 功能 |
|--------|------|
| `Cmd+D` | 右侧分屏 |
| `Cmd+Shift+D` | 下方分屏 |
| `Cmd+Shift+H/J/K/L` | 切换分屏（vim 风格）|
| `Cmd+Shift+Enter` | 当前分屏全屏 / 恢复 |
| `Ctrl+Shift+方向键` | 调整分屏大小 |

**实用功能**

| 快捷键 | 功能 |
|--------|------|
| `Cmd+K` | 清屏 |
| `Cmd+Shift+F` | 全文搜索 |
| `Cmd+Shift+↑/↓` | 跳到上 / 下一条命令（按命令块跳转）|
| `Cmd+Z` | 撤销关闭的 tab/split（30 秒内有效）|

### Ghostty vs tmux 分工

| 场景 | 用哪个 |
|------|--------|
| 本地日常分屏 / 多标签 | Ghostty 原生分屏 |
| 全局随时呼出终端 | Ghostty Quick Terminal |
| SSH 远程服务器后分屏 | tmux |
| 断线后保持 AI 进程运行 | tmux session |
| 管理多个 AI 项目工作区 | tmux（见下文）|

---

## 第二步：tmux 基础

### 安装 & 配置

```bash
# macOS
brew install tmux

# 应用本仓库配置
cp .tmux.conf ~/.tmux.conf

# 安装插件管理器 TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 启动 tmux 后按 Ctrl-w + I 安装插件
tmux
```

> 本配置前缀键为 `Ctrl-w`，下文快捷键均以此为准。

### 核心快捷键

> 两套键位**同时有效**，任选其一。详见 [完整快捷键手册](docs/keybindings.md)。

**Session / Window**

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w s` | — | 选择 session |
| `Ctrl-w d` | — | 退出 tmux（session 保持后台运行）|
| `Ctrl-w c` | `Cmd+T` | 新建 window |
| `Ctrl-w x` | `Cmd+W` | 关闭当前 pane |
| `Ctrl-w n` | `Cmd+Shift+]` | 下一个 window |
| `Ctrl-w p` | `Cmd+Shift+[` | 上一个 window |
| `Ctrl-w ,` | — | 重命名 window |

**Pane 分栏**

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w \|` | `Cmd+D` | 左右分栏 |
| `Ctrl-w -` | `Cmd+Shift+D` | 上下分栏 |
| `Ctrl-w h/j/k/l` | `Cmd+Shift+H/J/K/L` | 切换 pane |
| `Ctrl-w z` | `Cmd+Shift+Enter` | 放大 / 还原当前 pane |
| `Ctrl-w =` | `Cmd+Shift+=` | 均分所有 pane |
| `Ctrl-w Ctrl-h/j/k/l` | `Ctrl+Shift+方向键` | 调整 pane 大小 |

**复制 & 粘贴**

| 操作 | 功能 |
|------|------|
| 鼠标拖选 | 自动复制到系统剪贴板，高亮保持（与 Ghostty 一致）|
| 右键 | 粘贴系统剪贴板 |
| `Ctrl-w [` → `v` → `y` | 键盘进入复制模式，选中，复制 |
| `Ctrl-w K` / `Cmd+K` | 清屏 + 清除历史 |
| `Ctrl-w r` | 重载配置文件 |

**快照恢复**

| tmux 原生 | 功能 |
|-----------|------|
| `Ctrl-w Ctrl-s` | 手动保存所有 session 布局 |
| `Ctrl-w Ctrl-r` | 恢复保存的布局 |

> `tmux-continuum` 每 15 分钟自动保存，开机自动恢复。

### 常用命令

```bash
tmux new -s robot          # 新建 session
tmux ls                    # 查看所有 session
tmux attach -t robot       # 进入 session
tmux kill-session -t robot # 删除 session
tmux kill-window -t robot:1 # 删除指定 window
```

---

## 第三步：AI 工具工作流

### 标准布局：一个项目三格分屏

```
┌─────────────────────┬──────────────────┐
│                     │                  │
│   代码编辑 / 终端    │   Claude Code    │
│      （主工作区）    │   claude>        │
│                     │                  │
├─────────────────────┴──────────────────┤
│              日志 / 测试 / Git 状态      │
└────────────────────────────────────────┘
```

搭建命令：

```bash
tmux new -s myproject
Ctrl-w |          # 左右分栏
Ctrl-w l          # 切右侧
claude            # 启动 Claude Code
Ctrl-w h          # 切左侧
Ctrl-w -          # 底部日志栏
```

### Claude Code：多项目并行

```bash
# 同一 session 内，每个模块一个 window
tmux new -s robot
Ctrl-w c → Ctrl-w , → 输入 "nav"      # 导航模块
Ctrl-w c → Ctrl-w , → 输入 "vision"   # 视觉模块
Ctrl-w c → Ctrl-w , → 输入 "arm"      # 机械臂模块

# 各 window 内分别启动 Claude
cd ~/robot/nav && claude
```

**让 Claude 后台跑，你去做别的：**

```bash
# 右侧 Claude pane 交代任务
claude> 帮我重构 src/controller.py，完成后告诉我

# 切到左侧继续写代码
Ctrl-w h

# 甚至完全退出 tmux，Claude 继续运行
Ctrl-w d

# 随时回来查看进度
tmux attach -t robot
```

### bind-server：一键绑定远程服务器，体验等同本地

> 用 sshfs 把服务器目录挂载到本地，Claude 直接读写远程文件，执行命令走 ControlMaster 复用连接，**无感知地在服务器上「开了一个 Claude」**。

**前置安装（只需一次）：**

```bash
brew install --cask macfuse          # 安装后重启 Mac，在「系统设置 → 隐私与安全」点允许
brew install gromgit/fuse/sshfs-mac
```

**使用：**

```bash
bash scripts/bind-server.sh <ssh别名> <远程路径>

# 示例：绑定到 GPU 服务器的训练目录
bash scripts/bind-server.sh my-server ~/projects/train
```

自动完成：

```
┌──────────────────────┬───────────────────────┐
│                      │                       │
│   SSH 交互会话        │   本地 Claude Code    │
│   cd ~/projects/nav  │   工作目录 = 挂载目录  │
│   （你操作）          │   （AI 直接读写文件）  │
│                      │                       │
└──────────────────────┴───────────────────────┘
```

**核心规则：文件读写走挂载（代码/配置），命令执行走 SSH（训练/推理），大文件永不过本地。**

```bash
# Claude 自动用 ControlMaster 秒连跑命令
ssh my-server "cd ~/projects/train && python train.py"
ssh my-server "nvidia-smi"
```

加 alias 简化调用：

```bash
# ~/.zshrc
alias bind-server="bash ~/tmux-ai/scripts/bind-server.sh"

# 之后直接
bind-server my-server ~/projects/train
```

> 详细配置和多服务器并行管理见 [远程 SSH 工作流](docs/remote-ssh.md)。

---

### Codex：批量任务调度

```bash
# 新建专属 session
tmux new -s codex-batch

# 多个 window 并行跑不同任务
Ctrl-w c → Ctrl-w , → "refactor"
codex "重构 src/utils.py"

Ctrl-w c → Ctrl-w , → "tests"
codex "为所有 API 接口生成单元测试"

# 底部 pane 监控进度
Ctrl-w - → watch -n 3 git status
```

### OpenClaw：长任务监控

```bash
┌────────────────────────────────────────┐
│           OpenClaw 实时输出             │
├──────────────────┬─────────────────────┤
│   控制 / 干预    │   Claude 分析日志    │
└──────────────────┴─────────────────────┘
```

```bash
tmux new -s openclaw
# 上方全屏跑 OpenClaw
openclaw run task.yaml

# Ctrl-w - 分出底部，左右再分
# 左侧发控制指令，右侧开 Claude 分析日志
Ctrl-w -
Ctrl-w |
ctrl-w l → claude
```

### 多 Session 全局总览

```bash
# 按工作方向建 session，Ctrl-w s 弹出列表一键切换
tmux new -s work      # 主力工作
tmux new -s robot     # 机器人项目
tmux new -s exp       # 实验 / 原型
tmux new -s codex     # Codex 批量任务专用

# 查看所有 session
tmux ls

# 全局跳转
Ctrl-w s   # 弹出 session 列表，方向键选择 + Enter 确认
```

---

## 详细文档

| 文档 | 内容 |
|------|------|
| [架构详解](docs/architecture.md) | 三层结构图解、布局模板、设计原则 |
| [Ghostty 终端配置](docs/ghostty.md) | GPU 加速终端、Quick Terminal、与 tmux 分工 |
| [Claude Code 工作流](docs/claude-code.md) | 多项目并行、后台任务、复制粘贴技巧 |
| [Codex 工作流](docs/codex.md) | 批量任务调度、进度监控、结果汇总 |
| [OpenClaw 工作流](docs/openclaw.md) | 长任务管理、日志追踪、断线恢复 |
| [远程 SSH 工作流](docs/remote-ssh.md) | sshfs 挂载远程目录，体验等同在服务器上直接开 Claude；bind-server 一键建立布局 |
| [bind-server 详解](docs/bind-server.md) | 原理剖析、完整安装、参数说明、多服务器并行、常见问题排查 |
| [快捷键手册](docs/keybindings.md) | tmux 原生 + Ghostty 统一键位完整对照表 |
| [进阶技巧](docs/tips.md) | 脚本自动化、命名规范、快照恢复 |

---

## 贡献

欢迎提交 PR，分享你的 AI 工作流配置和使用技巧！详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## License

[MIT](LICENSE)
