# tmux 配置与使用教程

本仓库包含个人 tmux 配置文件（`.tmux.conf`）及使用指南。

---

## 安装

### macOS
```bash
brew install tmux
```

### Ubuntu / Debian
```bash
sudo apt install tmux
```

---

## 使用本配置

```bash
# 克隆仓库
git clone https://github.com/asimfish/tmux.git

# 安装配置
cp tmux/.tmux.conf ~/.tmux.conf

# 安装插件管理器 TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 重载配置（在 tmux 内执行）
tmux source ~/.tmux.conf

# 安装插件（在 tmux 内按）
# Prefix + I
```

---

## 前缀键

本配置将前缀键改为 `C-w`（即 `Ctrl+W`），替换默认的 `Ctrl+B`。

---

## 快捷键速查

### Session / Window 管理

| 快捷键 | 功能 |
|--------|------|
| `Prefix s` | 选择 session |
| `Prefix w` | 选择 window |
| `Prefix n` | 下一个 window |
| `Prefix p` | 上一个 window |
| `Prefix l` | 最近的 window |
| `Prefix c` | 新建 window（继承当前路径）|
| `Prefix ,` | 重命名 window |
| `Prefix $` | 重命名 session |

### Pane 分栏

| 快捷键 | 功能 |
|--------|------|
| `Prefix -` | 垂直分栏（上下）|
| `Prefix \|` | 水平分栏（左右）|
| `Prefix h/j/k/l` | 在 pane 间移动（vim 风格）|
| `Prefix e` | 切换到最近 pane |
| `Prefix z` | 当前 pane 最大化 / 还原 |
| `Prefix x` | 关闭当前 pane |
| `Prefix ^h/^j/^k/^l` | 调整 pane 大小 |
| `Prefix ^u` | 向上交换 pane |
| `Prefix ^d` | 向下交换 pane |

### 复制模式（vim 风格）

| 快捷键 | 功能 |
|--------|------|
| `Prefix [` | 进入复制模式 |
| `v` | 开始选择 |
| `y` | 复制并退出（写入剪贴板）|
| `Enter` | 复制并退出 |
| `Prefix ]` | 粘贴 |

### 配置管理

| 快捷键 | 功能 |
|--------|------|
| `Prefix r` | 重新加载配置文件 |
| `Prefix d` | 暂时退出 tmux（detach，session 保持后台运行）|

---

## 插件列表

| 插件 | 功能 |
|------|------|
| [tpm](https://github.com/tmux-plugins/tpm) | 插件管理器 |
| [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) | 合理的默认设置 |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | 保存 / 恢复 session |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | 自动保存 + 开机恢复 |
| [tmux-yank](https://github.com/tmux-plugins/tmux-yank) | 系统剪贴板集成 |

### tmux-resurrect 使用

| 快捷键 | 功能 |
|--------|------|
| `Prefix Ctrl+s` | 手动保存 session |
| `Prefix Ctrl+r` | 手动恢复 session |

---

## 常用 tmux 命令

```bash
# 新建 session
tmux new -s 工作

# 列出所有 session
tmux ls

# 连接到已有 session
tmux attach -t 工作

# 分离当前 session（保持后台运行）
# Prefix d

# 关闭指定 window
tmux kill-window -t 工作:1

# 在 session 外杀掉指定 session
tmux kill-session -t 工作
```

---

## 状态栏说明

- 左侧：`[session名]`
- 中间：window 列表，当前 window 高亮黄色
- 右侧：`主机名 | 日期 时间`

---

## 鼠标支持

已启用鼠标，支持：
- 点击切换 pane / window
- 拖拽调整 pane 大小
- 滚轮滚动历史
- 拖选文字自动复制到剪贴板

---

## 用 tmux + Claude Code 管理多项目

tmux 和 Claude Code 组合使用，可以让你同时驾驭多个项目，每个项目有独立的工作空间，Claude 在后台持续工作，你随时切换查看进度。

---

### 核心思路

```
一个 Session  =  一个大方向（如：工作 / 个人 / 实验）
一个 Window   =  一个项目
一个 Pane     =  一个角色（代码 / Claude / 日志）
```

这样无论同时跑几个项目，都井井有条，不会混乱。

---

### 推荐布局：单项目三格分屏

```
┌─────────────────────┬──────────────────┐
│                     │                  │
│   代码编辑 / 终端    │   Claude Code    │
│   （主工作区）       │   （AI 助手）     │
│                     │                  │
├─────────────────────┴──────────────────┤
│         日志 / 测试输出 / Git 状态       │
└────────────────────────────────────────┘
```

**搭建步骤：**

```bash
# 1. 新建项目 session
tmux new -s robot

# 2. 左右分栏：左边写代码，右边开 Claude
Ctrl-w |

# 3. 切到左侧，再上下分栏，底部放日志
Ctrl-w h
Ctrl-w -

# 4. 切到右侧 pane，启动 Claude Code
Ctrl-w l
claude
```

---

### 多项目并行工作流

每个项目开一个 **window**，Claude 在各自的 pane 里独立运行，互不干扰。

```bash
# 在 robot session 里建多个 window
tmux new-window -n robot-nav    # 导航模块
tmux new-window -n robot-arm    # 机械臂模块
tmux new-window -n robot-vision # 视觉模块
```

状态栏效果：
```
[robot]  1:robot-nav  2:robot-arm  ●3:robot-vision
                                    ↑ 当前窗口，黄色高亮
```

在任意 window 按 `Ctrl-w w` 弹出列表，一眼选择目标项目。

---

### 典型工作场景

#### 场景一：让 Claude 在后台跑任务，你去做别的

```bash
# 在 pane 右侧启动 Claude，交代任务
claude
> 帮我重构 src/controller.py，完成后告诉我

# 切到左侧 pane 继续写代码（Claude 同步工作）
Ctrl-w h

# 想看 Claude 进度时，切回去
Ctrl-w l
```

#### 场景二：多项目同时推进

```bash
# window 1：robot-nav，Claude 正在写导航算法
Ctrl-w c   # 新建 window 2

# window 2：robot-arm，你在调试机械臂
# ... 调试中 ...

# 切回 window 1 看 Claude 是否完成
Ctrl-w p
```

#### 场景三：跨 session 管理工作与个人项目

```bash
# 工作 session（白天）
tmux new -s work

# 个人项目 session（晚上）
tmux new -s side

# 两个 session 之间随时切换，互不影响
Ctrl-w s   # 弹出 session 列表选择
```

---

### 在 tmux 里高效使用 Claude Code

| 操作 | 方法 |
|------|------|
| 查看 Claude 输出历史 | `Ctrl-w [` 进入复制模式，向上滚动 |
| 复制 Claude 的代码 | 复制模式下 `v` 选中，`y` 复制到剪贴板 |
| 把代码粘贴给 Claude | 终端直接 `Ctrl-v`（或 `Cmd-v`）|
| 放大 Claude 窗口查看 | `Ctrl-w z` 最大化当前 pane，再按还原 |
| 临时离开保持 Claude 运行 | `Ctrl-w d` detach，Claude 继续在后台跑 |
| 回来查看结果 | `tmux attach -t session名` |

---

### 推荐的 Session 命名规范

```bash
tmux new -s work      # 工作项目
tmux new -s robot     # 机器人项目
tmux new -s exp       # 实验 / 探索
tmux new -s tmp       # 临时任务（用完 kill）
```

Window 命名建议与模块/功能对应，方便状态栏一眼识别：

```bash
Ctrl-w ,   # 重命名当前 window
# 例：nav / arm / vision / train / server / git
```

---

### 快照：随时保存，重启无忧

项目跑到一半需要重启电脑？不用担心：

```bash
# 手动保存当前所有 session / window / pane 布局
Ctrl-w Ctrl-s

# 重启后恢复一切（包括 Claude Code 的工作目录）
Ctrl-w Ctrl-r
```

> `tmux-continuum` 插件会每隔 15 分钟自动保存一次，开机也会自动恢复，基本无需手动操作。
