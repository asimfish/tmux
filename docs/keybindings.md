# 快捷键完整手册

> **前缀键：`Ctrl-w`**（本配置已替换默认的 `Ctrl-b`）

本配置有两套键位，**同时有效，任选其一**：
- **tmux 原生**：`Ctrl-w` 前缀键，适合纯键盘操作，SSH 远程同样有效
- **Ghostty 统一**：`Cmd` 系快捷键，在 Ghostty 终端内通过键位映射触发相同的 tmux 指令

---

## Session 管理

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w s` | — | 弹出 session 列表，选择切换 |
| `Ctrl-w d` | — | 退出 tmux（detach），session 保持后台运行 |
| `Ctrl-w $` | — | 重命名当前 session |

**命令行：**
```bash
tmux new -s name          # 新建 session
tmux ls                   # 列出所有 session
tmux attach -t name       # 进入 session
tmux kill-session -t name # 删除 session
```

---

## Window 管理

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w c` | `Cmd+T` | 新建 window（继承当前路径）|
| `Ctrl-w x` | `Cmd+W` | 关闭当前 pane |
| `Ctrl-w w` | — | 弹出 window 列表，选择切换 |
| `Ctrl-w n` | `Cmd+Shift+]` | 切到下一个 window |
| `Ctrl-w p` | `Cmd+Shift+[` | 切到上一个 window |
| `Ctrl-w l` | — | 切到最近使用的 window |
| `Ctrl-w ,` | — | 重命名当前 window |

**命令行：**
```bash
tmux kill-window -t name:1   # 删除指定 window
```

---

## Pane 分栏

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w \|` | `Cmd+D` | 左右分栏 |
| `Ctrl-w -` | `Cmd+Shift+D` | 上下分栏 |
| `Ctrl-w h` | `Cmd+Shift+H` | 切到左侧 pane |
| `Ctrl-w j` | `Cmd+Shift+J` | 切到下方 pane |
| `Ctrl-w k` | `Cmd+Shift+K` | 切到上方 pane |
| `Ctrl-w l` | `Cmd+Shift+L` | 切到右侧 pane |
| `Ctrl-w z` | `Cmd+Shift+Enter` | 当前 pane 最大化 / 还原 |
| `Ctrl-w =` | `Cmd+Shift+=` | 均分所有 pane |
| `Ctrl-w e` | — | 切换到最近使用的 pane |
| `Ctrl-w Ctrl-h` | `Ctrl+Shift+←` | 向左扩大 pane |
| `Ctrl-w Ctrl-j` | `Ctrl+Shift+↓` | 向下扩大 pane |
| `Ctrl-w Ctrl-k` | `Ctrl+Shift+↑` | 向上扩大 pane |
| `Ctrl-w Ctrl-l` | `Ctrl+Shift+→` | 向右扩大 pane |
| `Ctrl-w Ctrl-u` | — | 向上交换 pane |
| `Ctrl-w Ctrl-d` | — | 向下交换 pane |

---

## 复制 & 粘贴

### 鼠标操作（推荐）

| 操作 | 功能 |
|------|------|
| 鼠标拖选 | 自动复制到系统剪贴板，选中高亮保持 |
| 右键单击 | 粘贴系统剪贴板内容 |

> 行为与 Ghostty 的 `copy-on-select = clipboard` 完全一致。

### 键盘操作（vim 风格复制模式）

| tmux 原生 | 功能 |
|-----------|------|
| `Ctrl-w [` | 进入复制模式（可用键盘滚动历史）|
| `Ctrl-u` | 向上翻半页 |
| `Ctrl-d` | 向下翻半页 |
| `g` | 跳到最顶部 |
| `G` | 跳到最底部 |
| `v` | 开始选择文字 |
| `y` | 复制到系统剪贴板并退出 |
| `Enter` | 复制并退出 |
| `q` / `Esc` | 退出复制模式，回到底部 |
| `Ctrl-w ]` | 粘贴 tmux 缓冲区 |

---

## 其他实用操作

| tmux 原生 | Ghostty 统一 | 功能 |
|-----------|-------------|------|
| `Ctrl-w K` | `Cmd+K` | 清屏 + 清除历史滚动 |
| `Ctrl-w r` | — | 重新加载 tmux 配置文件 |

---

## 快照 & 插件

| tmux 原生 | 功能 |
|-----------|------|
| `Ctrl-w Ctrl-s` | 手动保存当前全部工作环境（session/window/pane）|
| `Ctrl-w Ctrl-r` | 手动恢复已保存的工作环境 |
| `Ctrl-w I` | 安装 / 更新 TPM 插件（大写 I）|

> `tmux-continuum` 每 15 分钟自动保存一次，开机自动恢复，一般无需手动操作。

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

---

## Ghostty 键位映射原理

Ghostty 配置里把 `Cmd` 系快捷键映射为向终端发送 tmux 控制序列：
- `\x17` = `Ctrl-w`（tmux 前缀键）
- `\x08` = `Ctrl-h`，`\x0a` = `Ctrl-j`，`\x0b` = `Ctrl-k`，`\x0c` = `Ctrl-l`

例如 `Cmd+D` → 发送 `\x17|` → tmux 收到 `Ctrl-w |` → 左右分栏。

tmux 原生键位**完全保留**，Ghostty 映射是在其基础上额外增加，两套互不影响。
