# tmux × Claude Code × Codex × OpenClaw

> **用 tmux 高效管理 AI 编程助手的开源教程**
> 一个终端，多个 AI，多个项目，全部尽在掌控。

---

## 这个教程适合谁？

如果你同时使用 **Claude Code**、**Codex**、**OpenClaw** 等 AI 编程工具，你一定遇到过这些问题：

- AI 在跑任务，我不知道该不该打断它去做别的事
- 多个项目同时推进，窗口混乱、切来切去容易丢失上下文
- 重启电脑后，之前所有的工作环境都没了
- 想让 AI 在后台跑，自己去做别的，但关掉终端就断了

**tmux 可以彻底解决以上问题。** 本教程手把手教你搭建一套稳定、高效的 AI 辅助开发工作流。

---

## 核心概念：三层结构

```
Session（会话）  ──  一个大方向 / 一类工作
  └── Window（窗口）  ──  一个项目
        └── Pane（面板）  ──  一个角色（代码 / AI / 日志）
```

类比理解：
- **Session** = 你的工作台（工作 / 个人 / 实验）
- **Window** = 台面上的一个项目文件夹
- **Pane** = 文件夹里同时打开的多个文件

---

## 快速开始

### 1. 安装 tmux

```bash
# macOS
brew install tmux

# Ubuntu / Debian
sudo apt install tmux
```

### 2. 使用本配置

```bash
# 克隆本仓库
git clone https://github.com/asimfish/tmux.git

# 应用配置
cp tmux/.tmux.conf ~/.tmux.conf

# 安装插件管理器 TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 启动 tmux 后安装插件
tmux
# 然后按 Ctrl-w + I（大写）
```

> 本配置将前缀键设为 `Ctrl-w`，下文快捷键均以此为准。

---

## 工作流一：Claude Code 多项目并行

### 推荐布局

```
┌──────────────────────┬───────────────────┐
│                      │                   │
│    代码编辑 / 终端    │    Claude Code    │
│    （你的主工作区）   │    （AI 工作区）   │
│                      │                   │
├──────────────────────┴───────────────────┤
│          日志 / 测试输出 / Git 状态        │
└──────────────────────────────────────────┘
```

### 搭建步骤

```bash
# 新建项目 session
tmux new -s robot

# 左右分栏
Ctrl-w |

# 切到左侧，再上下分栏（底部放日志）
Ctrl-w h
Ctrl-w -

# 切到右侧，启动 Claude Code
Ctrl-w l
claude
```

### 日常操作

| 场景 | 操作 |
|------|------|
| 交代任务给 Claude，自己去写代码 | 右侧输入任务 → `Ctrl-w h` 切到左侧继续工作 |
| 查看 Claude 进度 | `Ctrl-w l` 切回右侧 |
| 放大 Claude 窗口完整阅读输出 | `Ctrl-w z` 最大化，再按一次还原 |
| 复制 Claude 生成的代码 | `Ctrl-w [` 进入复制模式 → `v` 选中 → `y` 复制 |
| 关掉终端但保持 Claude 运行 | `Ctrl-w d` 退出 tmux，Claude 在后台继续跑 |
| 回来查看结果 | `tmux attach -t robot` |

### 多项目切换

```bash
# 每个模块开一个 window
Ctrl-w c   # 新建 window，重命名
Ctrl-w ,   # 输入名称，如 nav / arm / vision

# 状态栏效果：
# [robot]  1:nav  2:arm  ●3:vision
#                         ↑ 当前，黄色高亮

# 切换
Ctrl-w w   # 弹出 window 列表
Ctrl-w n   # 下一个
Ctrl-w p   # 上一个
```

---

## 工作流二：Codex 后台并行任务

Codex 擅长长时间运行的代码生成任务。用 tmux 可以让多个 Codex 任务同时在后台运行，互不阻塞。

### 推荐布局：一个 Window 一个 Codex 任务

```bash
# 新建 session
tmux new -s codex

# Window 1：任务 A
Ctrl-w ,   # 重命名为 task-refactor
# 启动 Codex 任务 A...

# 新建 Window 2：任务 B
Ctrl-w c
Ctrl-w ,   # 重命名为 task-test
# 启动 Codex 任务 B...

# 此时两个任务并行运行，互不干扰
# 随时用 Ctrl-w w 切换查看各任务进度
```

### 关键技巧：detach 让任务彻底在后台

```bash
# 启动 Codex 任务后
Ctrl-w d   # 退出 tmux（任务继续运行）

# 去做别的事...

# 回来查看所有任务状态
tmux ls              # 列出所有 session
tmux attach -t codex # 进入查看结果
```

---

## 工作流三：OpenClaw 长任务监控

OpenClaw 运行时往往需要持续输出日志，用 tmux 可以轻松实现「启动后不管，需要时再看」。

### 推荐布局：日志独占底部

```
┌─────────────────────────────────────────┐
│                                         │
│         OpenClaw 控制 / 交互             │
│                                         │
├─────────────────────────────────────────┤
│         实时日志输出（只读监控）          │
└─────────────────────────────────────────┘
```

```bash
# 新建 session
tmux new -s claw

# 上下分栏
Ctrl-w -

# 上方：运行 OpenClaw
Ctrl-w k
# 启动 OpenClaw...

# 下方：实时跟踪日志
Ctrl-w j
tail -f logs/openclaw.log

# 滚动查看历史日志
Ctrl-w [   # 进入复制模式，用方向键或 PgUp 滚动
q          # 退出复制模式
```

---

## 工作流四：跨项目总览（多 Session）

当你同时有多条工作线时，用 Session 做顶层隔离：

```bash
# 工作项目
tmux new -s work

# 实验 / 探索
tmux new -s exp

# 个人项目
tmux new -s side

# 切换 session
Ctrl-w s   # 弹出 session 列表，方向键选择 + Enter 确认
```

**Session 命名建议：**

| Session 名 | 用途 |
|------------|------|
| `work` | 主力工作项目 |
| `robot` | 机器人 / 具体项目名 |
| `exp` | 实验、原型验证 |
| `codex` | 专门跑 Codex 批量任务 |
| `tmp` | 临时任务（用完 `tmux kill-session -t tmp`）|

---

## 快照：重启电脑不丢工作环境

用 **tmux-resurrect** + **tmux-continuum** 插件，所有 session / window / pane 布局都能保存和恢复。

```bash
# 手动保存当前全部工作环境
Ctrl-w Ctrl-s

# 手动恢复
Ctrl-w Ctrl-r
```

> `tmux-continuum` 每 15 分钟自动保存一次，开机自动恢复，基本无需手动操作。

---

## 快捷键速查

### Session / Window

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w s` | 选择 session |
| `Ctrl-w w` | 选择 window |
| `Ctrl-w c` | 新建 window |
| `Ctrl-w ,` | 重命名 window |
| `Ctrl-w n` | 下一个 window |
| `Ctrl-w p` | 上一个 window |
| `Ctrl-w l` | 最近的 window |
| `Ctrl-w d` | 退出 tmux（session 保持后台运行）|
| `Ctrl-w $` | 重命名 session |

### Pane 分栏

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w \|` | 左右分栏 |
| `Ctrl-w -` | 上下分栏 |
| `Ctrl-w h/j/k/l` | 切换 pane（vim 风格）|
| `Ctrl-w z` | 放大 / 还原当前 pane |
| `Ctrl-w x` | 关闭当前 pane |
| `Ctrl-w e` | 切换到最近 pane |

### 复制 & 配置

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w [` | 进入复制模式（可滚动历史）|
| `v` | 开始选择文字 |
| `y` | 复制到系统剪贴板并退出 |
| `Ctrl-w ]` | 粘贴 |
| `Ctrl-w r` | 重载配置文件 |

---

## 常用命令速查

```bash
tmux new -s robot        # 新建 session
tmux ls                  # 查看所有 session
tmux attach -t robot     # 进入 session
tmux kill-session -t robot          # 删除 session
tmux kill-window -t robot:1         # 删除指定 window
```

---

## 插件列表

| 插件 | 功能 |
|------|------|
| [tpm](https://github.com/tmux-plugins/tpm) | 插件管理器 |
| [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) | 合理的默认设置 |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | 保存 / 恢复 session 布局 |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | 自动保存 + 开机恢复 |
| [tmux-yank](https://github.com/tmux-plugins/tmux-yank) | 系统剪贴板集成 |

---

## 鼠标支持

已启用鼠标，支持：
- 点击切换 pane / window
- 拖拽调整 pane 大小
- 滚轮滚动历史输出
- 拖选文字自动复制到系统剪贴板

---

## 贡献 & 反馈

欢迎提交 Issue 或 PR，分享你的 AI 工作流配置和使用技巧。
