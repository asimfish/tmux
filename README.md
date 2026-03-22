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
