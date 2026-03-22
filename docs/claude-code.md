# Claude Code 工作流

> 用 tmux 让 Claude Code 在后台持续工作，你随时切入切出，不打断 AI 的思考流。

---

## 基础布局

```
┌─────────────────────┬──────────────────┐
│                     │                  │
│   你的代码 / 终端    │   Claude Code    │
│                     │    claude>       │
│                     │                  │
├─────────────────────┴──────────────────┤
│              日志 / 测试输出             │
└────────────────────────────────────────┘
```

搭建命令：
```bash
tmux new -s work
Ctrl-w |        # 左右分栏
Ctrl-w l        # 切到右侧
claude          # 启动 Claude Code
Ctrl-w h        # 切回左侧
Ctrl-w -        # 底部日志栏
```

---

## 多项目并行

每个项目开一个 window，Claude Code 各自独立运行：

```bash
# 在同一个 session 里管理多个项目
tmux new -s work

# 新建各项目 window
Ctrl-w c  →  Ctrl-w ,  →  输入 "frontend"
Ctrl-w c  →  Ctrl-w ,  →  输入 "backend"
Ctrl-w c  →  Ctrl-w ,  →  输入 "infra"
```

状态栏效果：
```
[work]  1:frontend  ●2:backend  3:infra
                     ↑ 当前 window（黄色高亮）
```

在各个 window 里分别启动 Claude Code，任务互不干扰：

```bash
# window: frontend
cd ~/projects/frontend && claude

# window: backend
cd ~/projects/backend && claude
```

---

## 让 Claude 在后台工作

最强大的用法：交代任务后 detach，让 Claude 独立完成，你去做别的。

```bash
# 1. 在 Claude pane 里交代任务
claude> 帮我重构 src/controller.py，
        拆分成 service 层和 controller 层，
        完成后告诉我

# 2. 切到代码 pane，继续自己的工作
Ctrl-w h

# 3. 甚至可以完全退出 tmux，Claude 继续跑
Ctrl-w d

# 4. 随时回来看进度
tmux attach -t work
Ctrl-w l    # 切到 Claude pane
```

---

## 查看与复制 Claude 的输出

| 操作 | 方法 |
|------|------|
| 滚动查看历史输出 | `Ctrl-w [` 进入复制模式，方向键 / `Ctrl-u` 上翻 |
| 选中文字 | 复制模式下按 `v` 开始选择 |
| 复制到剪贴板 | 选中后按 `y` |
| 粘贴到代码 | 切到代码 pane，`Ctrl-v`（或 `Cmd-v`）|
| 放大 Claude pane 查看 | `Ctrl-w z`，再按一次还原 |
| 退出复制模式 | `q` 或 `Esc` |

---

## 典型场景示例

### 场景：同时推进两个模块

```bash
# window 1: nav 模块
claude> 帮我实现 A* 路径规划算法，写好单元测试

# 切到 window 2
Ctrl-w c

# window 2: vision 模块，你自己在写代码
vim src/vision/detector.py

# 一段时间后，切回 window 1 看 Claude 进度
Ctrl-w p
```

### 场景：Claude 写代码，你做 Code Review

```bash
# 右侧 Claude pane
claude> 根据 spec.md 实现完整的 REST API

# 底部日志 pane 实时监测变更
watch -n 2 git diff --stat

# Claude 完成后，左侧代码 pane 做 review
git diff
```

---

## 快捷键速查

| 快捷键 | 用途 |
|--------|------|
| `Ctrl-w l` | 切到 Claude pane |
| `Ctrl-w h` | 切回代码 pane |
| `Ctrl-w z` | 全屏查看 Claude 输出 |
| `Ctrl-w [` | 进入复制模式，滚动历史 |
| `Ctrl-w d` | 退出 tmux，Claude 后台继续 |
| `tmux attach -t work` | 回来查看 Claude 进度 |
