# 贡献指南

欢迎贡献！这个项目的目标是收集真实可用的 tmux × AI 工作流，帮助更多人高效使用 Claude Code、Codex、OpenClaw 等工具。

---

## 可以贡献什么？

- **新的工作流** — 你在实际使用中总结的 AI 工具 + tmux 用法
- **布局模板** — 适合特定场景的 pane 布局（附 ASCII 图示）
- **自动化脚本** — 一键搭建工作环境的 shell 脚本
- **配置优化** — 对 `.tmux.conf` 的改进建议
- **文档改进** — 修正错误、补充说明、改善表达
- **翻译** — 欢迎添加英文版文档

---

## 提交 PR 步骤

```bash
# 1. Fork 本仓库
# 2. 克隆到本地
git clone https://github.com/你的用户名/tmux.git

# 3. 创建分支
git checkout -b feature/my-workflow

# 4. 修改 / 新增内容
# ...

# 5. 提交
git add .
git commit -m "add: 描述你的改动"

# 6. 推送并发起 PR
git push origin feature/my-workflow
```

---

## 文档规范

- 新增工作流放在 `docs/` 目录下
- 布局图用 ASCII 或 Mermaid，不要上传图片文件
- 快捷键统一用 `Ctrl-w` 前缀（本配置的前缀键）
- 中文为主，欢迎中英双语

---

## 提 Issue

发现问题或有功能建议，直接开 Issue 即可，不需要任何格式要求，描述清楚问题或想法就好。
