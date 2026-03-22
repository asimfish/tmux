# 快捷键完整手册

> 前缀键：`Ctrl-w`（本配置已替换默认的 `Ctrl-b`）

---

## Session 管理

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w s` | 弹出 session 列表，选择切换 |
| `Ctrl-w d` | 退出 tmux（detach），session 保持后台运行 |
| `Ctrl-w $` | 重命名当前 session |

**命令行操作：**
```bash
tmux new -s name          # 新建 session
tmux ls                   # 列出所有 session
tmux attach -t name       # 进入 session
tmux kill-session -t name # 删除 session
```

---

## Window 管理

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w c` | 新建 window（继承当前路径）|
| `Ctrl-w w` | 弹出 window 列表，选择切换 |
| `Ctrl-w n` | 切到下一个 window |
| `Ctrl-w p` | 切到上一个 window |
| `Ctrl-w l` | 切到最近使用的 window |
| `Ctrl-w ,` | 重命名当前 window |

**命令行操作：**
```bash
tmux kill-window -t name:1   # 删除指定 window
```

---

## Pane 分栏

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w \|` | 左右分栏 |
| `Ctrl-w -` | 上下分栏 |
| `Ctrl-w h` | 切到左侧 pane |
| `Ctrl-w j` | 切到下方 pane |
| `Ctrl-w k` | 切到上方 pane |
| `Ctrl-w l` | 切到右侧 pane |
| `Ctrl-w e` | 切换到最近使用的 pane |
| `Ctrl-w z` | 当前 pane 最大化 / 还原 |
| `Ctrl-w x` | 关闭当前 pane |
| `Ctrl-w Ctrl-h` | 向左扩大 pane |
| `Ctrl-w Ctrl-j` | 向下扩大 pane |
| `Ctrl-w Ctrl-k` | 向上扩大 pane |
| `Ctrl-w Ctrl-l` | 向右扩大 pane |
| `Ctrl-w Ctrl-u` | 向上交换 pane |
| `Ctrl-w Ctrl-d` | 向下交换 pane |

---

## 复制模式（vim 风格）

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w [` | 进入复制模式 |
| `Ctrl-u` | 向上翻半页 |
| `Ctrl-d` | 向下翻半页 |
| `g` | 跳到最顶部 |
| `G` | 跳到最底部 |
| `v` | 开始选择文字 |
| `y` | 复制到系统剪贴板并退出 |
| `Enter` | 复制并退出 |
| `q` / `Esc` | 退出复制模式 |
| `Ctrl-w ]` | 粘贴 |

---

## 快照 & 插件

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-w Ctrl-s` | 手动保存当前全部工作环境 |
| `Ctrl-w Ctrl-r` | 手动恢复已保存的工作环境 |
| `Ctrl-w r` | 重新加载配置文件（无需重启）|
| `Ctrl-w I` | 安装 TPM 插件（大写 I）|

---

## 常用命令速查

```bash
# Session
tmux new -s name           # 新建 session
tmux ls                    # 列出所有 session
tmux attach -t name        # 进入 session
tmux kill-session -t name  # 删除 session

# Window
tmux kill-window -t name:1 # 删除指定 window

# 配置
tmux source ~/.tmux.conf   # 重载配置
```
