# OpenClaw 工作流

> 用 tmux 管理 OpenClaw 长任务，实时监控输出，断线后无缝恢复，Claude 帮你解读日志。

---

## 为什么 OpenClaw 特别需要 tmux？

OpenClaw 任务通常运行时间长（几分钟到几小时），一旦终端关闭任务即中断。tmux 让任务在服务器后台持续运行，你可以随时离开、随时回来。

---

## 推荐布局

```
┌────────────────────────────────────────────┐
│                                            │
│           OpenClaw 实时输出                │
│           （主日志区，占 60%）              │
│                                            │
├──────────────────────┬─────────────────────┤
│   控制 / 指令输入     │  Claude 日志分析    │
│   发送控制命令        │  解读输出 & 建议    │
└──────────────────────┴─────────────────────┘
```

搭建命令：
```bash
tmux new -s openclaw
Ctrl-w -        # 上下分栏（上：主日志）
Ctrl-w j        # 切到下方
Ctrl-w |        # 左右分栏（左：控制，右：Claude）
Ctrl-w l        # 切到右侧
claude          # 启动 Claude 解读日志
Ctrl-w h        # 切到左侧控制区
```

---

## 启动与后台运行

```bash
# 在主日志 pane 启动 OpenClaw 任务
openssl ...     # 或你的 openclaw 命令

# 任务跑着，你可以随时离开
Ctrl-w d        # detach，任务继续后台运行

# 之后随时回来查看进度
tmux attach -t openclaw
```

**这是 tmux 最核心的价值：任务生命周期与终端连接完全解耦。**

---

## 用 Claude 实时分析日志

在右侧 Claude pane 里，把日志喂给 Claude 分析：

```bash
# 方法一：复制日志片段给 Claude
Ctrl-w [              # 进入复制模式
v                     # 选中关键输出
y                     # 复制
Ctrl-w l              # 切到 Claude pane
Ctrl-v                # 粘贴给 Claude
claude> 这段输出是什么意思？有没有异常？

# 方法二：直接描述让 Claude 指导
claude> OpenClaw 输出了 "connection timeout to peer 192.168.1.5"，
        这是什么问题？怎么排查？
```

---

## 断线恢复

网络断开或意外关闭终端后：

```bash
# 重新连接服务器后
tmux ls                      # 查看任务是否仍在运行
tmux attach -t openclaw      # 直接恢复，一行不丢
```

任务从未中断，日志完整保留。

---

## 多任务并行监控

同时运行多个 OpenClaw 任务时，每个开一个 window：

```bash
tmux new -s openclaw

# window 1: 任务A
Ctrl-w c  →  Ctrl-w ,  →  "task-a"
openssl ...

# window 2: 任务B
Ctrl-w c  →  Ctrl-w ,  →  "task-b"
openssl ...

# 用 Ctrl-w w 快速在任务间巡视
```

---

## 滚动查看历史日志

```bash
Ctrl-w [        # 进入复制模式
Ctrl-u          # 向上翻半页
Ctrl-d          # 向下翻半页
g               # 跳到日志最顶部
G               # 跳到日志最底部（最新输出）
q               # 退出复制模式，回到实时追踪
```

---

## 任务完成后保存环境

```bash
# 保存当前 session 布局和工作状态
Ctrl-w Ctrl-s

# 下次开机后恢复，继续做后续处理
Ctrl-w Ctrl-r
```

---

## 快捷键速查

| 快捷键 | 用途 |
|--------|------|
| `Ctrl-w d` | 退出 tmux，任务后台继续 |
| `tmux attach -t openclaw` | 恢复会话 |
| `Ctrl-w [` | 进入复制模式，查看历史日志 |
| `Ctrl-w z` | 全屏查看日志输出 |
| `Ctrl-w l` | 切到 Claude 分析 pane |
| `Ctrl-w Ctrl-s` | 保存工作环境快照 |
