# Codex 工作流

> 用 tmux 管理 Codex 批量任务，让多个编码任务并行跑，实时监控每一个的进度。

---

## 基础布局

```
┌──────────────────────┬──────────────────────┐
│                      │                      │
│   任务列表 / 控制台   │   Codex 任务输出      │
│   （分配 & 监控）     │   （实时日志）        │
│                      │                      │
├──────────────────────┴──────────────────────┤
│              结果汇总 / Git diff              │
└─────────────────────────────────────────────┘
```

搭建命令：
```bash
tmux new -s codex
Ctrl-w |        # 左右分栏
Ctrl-w -        # 右侧再上下分（日志 + 结果）
```

---

## 多任务并行调度

每个 Codex 任务开一个 window，同时推进多个编码工作：

```bash
# 新建 session
tmux new -s codex-batch

# window 1：重构任务
Ctrl-w c  →  Ctrl-w ,  →  "refactor"
codex "重构 src/utils.py，拆分为独立模块"

# window 2：测试生成任务
Ctrl-w c  →  Ctrl-w ,  →  "tests"
codex "为 src/api/ 下所有接口生成单元测试"

# window 3：文档生成任务
Ctrl-w c  →  Ctrl-w ,  →  "docs"
codex "为所有 public 函数生成 docstring"

# 用 Ctrl-w w 在任务间切换查看进度
```

---

## 后台批量运行

提交任务后 detach，让 Codex 在后台独立执行：

```bash
# 在各 window 分别提交任务后
Ctrl-w d    # 完全退出 tmux，所有任务继续后台运行

# 稍后回来查看所有任务状态
tmux attach -t codex-batch

# 快速浏览各 window 结果
Ctrl-w w    # 弹出 window 列表
```

---

## 监控任务进度

在底部日志 pane 用 watch 实时追踪变更：

```bash
# 监控文件变化
watch -n 2 'git diff --stat'

# 或监控特定目录
watch -n 2 'ls -lt src/ | head -20'
```

---

## 结果对比与合并

多个 Codex 任务完成后，在日志 pane 做汇总：

```bash
# 查看所有变更
git diff --stat

# 逐个 review
git diff src/utils.py

# 分批提交
git add src/utils.py && git commit -m "refactor: split utils"
```

---

## 与 Claude Code 联动

**推荐工作流：Codex 生成 → Claude Code Review**

```
┌──────────────────┬──────────────────┬──────────────────┐
│                  │                  │                  │
│   Codex 生成代码  │  Claude Code     │   测试 / 验证    │
│                  │  Review & 修改   │                  │
└──────────────────┴──────────────────┴──────────────────┘
```

```bash
# window: codex-gen
codex "实现 OAuth2 登录流程"

# 完成后，切到 window: review
Ctrl-w c
claude
claude> 帮我 review 刚刚生成的 OAuth2 代码，
        检查安全漏洞和最佳实践
```

---

## 快捷键速查

| 快捷键 | 用途 |
|--------|------|
| `Ctrl-w c` | 新建 window 跑新任务 |
| `Ctrl-w w` | 切换查看各任务进度 |
| `Ctrl-w z` | 全屏查看当前任务输出 |
| `Ctrl-w d` | 退出 tmux，任务后台继续 |
| `Ctrl-w [` | 滚动查看任务历史输出 |
