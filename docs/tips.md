# 进阶技巧

---

## 命名规范

良好的命名让状态栏一眼看懂当前全局状态。

**Session 命名：按生命周期分类**

| Session 名 | 适用场景 |
|------------|----------|
| `work` | 主力工作，长期保留 |
| `robot` / `myproject` | 具体项目名 |
| `exp` | 实验、原型，随时可删 |
| `codex` | 专跑 Codex 批量任务 |
| `tmp` | 临时任务，用完即删 |

**Window 命名：按模块或功能**

```bash
Ctrl-w ,    # 重命名当前 window
```

推荐命名：`nav` / `vision` / `arm` / `api` / `frontend` / `train` / `logs`

---

## 快照恢复：重启不丢环境

tmux-resurrect + tmux-continuum 插件组合：

```bash
Ctrl-w Ctrl-s    # 手动保存：保存所有 session / window / pane 布局
Ctrl-w Ctrl-r    # 手动恢复：重启后一键还原
```

> `tmux-continuum` 每 15 分钟自动保存一次，开机自动恢复，基本无需手动操作。

**保存内容包括：**
- 所有 session、window、pane 的结构
- 每个 pane 的工作目录
- 正在运行的程序（需配置 resurrect-processes）

---

## 脚本自动化：一键搭建工作环境

把常用布局写成脚本，每次开工一行命令搞定：

```bash
#!/bin/bash
# setup-work.sh：一键搭建 AI 工作环境

SESSION="work"

# 如果 session 已存在，直接进入
tmux has-session -t $SESSION 2>/dev/null && tmux attach -t $SESSION && exit

# 新建 session，第一个 window：frontend
tmux new-session -d -s $SESSION -n frontend -c ~/projects/frontend
tmux split-window -h -t $SESSION:frontend    # 右侧 pane
tmux send-keys -t $SESSION:frontend.1 'claude' Enter  # 右侧启动 Claude
tmux split-window -v -t $SESSION:frontend.0  # 底部日志

# 第二个 window：backend
tmux new-window -t $SESSION -n backend -c ~/projects/backend
tmux split-window -h -t $SESSION:backend
tmux send-keys -t $SESSION:backend.1 'claude' Enter

# 默认选中第一个 window
tmux select-window -t $SESSION:frontend
tmux select-pane -t $SESSION:frontend.0

# 进入 session
tmux attach -t $SESSION
```

使用：
```bash
chmod +x setup-work.sh
./setup-work.sh
```

---

## 跨机器使用（远程服务器）

tmux 在远程服务器上特别有价值：SSH 断开后任务继续运行。

```bash
# 登录服务器，新建或恢复 session
ssh user@server
tmux new -s train        # 首次
tmux attach -t train     # 断线重连后

# 在 session 里跑长任务（AI 训练、OpenClaw 等）
python train.py

# 关掉 SSH 窗口，任务继续跑
# 下次 SSH 进来，attach 即可看到完整日志
```

---

## 调整 pane 大小

```bash
Ctrl-w Ctrl-h    # 向左扩大
Ctrl-w Ctrl-l    # 向右扩大
Ctrl-w Ctrl-k    # 向上扩大
Ctrl-w Ctrl-j    # 向下扩大
```

或者用鼠标直接拖拽分割线（已在配置中启用）。

---

## 状态栏说明

```
[work]  1:frontend  ●2:backend  3:infra    hostname | 2026-03-15 14:32
  ↑         ↑          ↑                       ↑
Session  Window    当前Window            右侧信息栏
         列表      (黄色高亮)
```

- `●` 表示该 window 有活动（输出变化）
- 当前 window 黄色高亮
