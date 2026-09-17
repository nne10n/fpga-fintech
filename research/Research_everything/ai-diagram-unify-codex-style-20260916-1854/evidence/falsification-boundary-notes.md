# 证伪与边界留证

Asia/Shanghai 2026-09-16 · 绑定 [`sources.md`](../sources.md) **S19,S20,S21,S1,S14**

---

## S19 证伪：不存在可引用的 Codex Diagram Design System

### 检索动作

| 检索面 | 文件/页面 | 结果 |
|--------|-----------|------|
| OpenAI 博客 | S4 agent loop；S5 App Server | 有 **静态架构插图** 与组件名；**无** diagram VI PDF/hex/font 链接 |
| openai/codex issue | S1 #35628；S2 #32356；S3 #36660 | 有 **Mermaid 围栏样例**；**无**「Design System」文档引用 |
| Mermaid 官方 | S7 theming | 有 `primaryColor` `#fff4dd`、`fontSize` `16px` — 属 **Mermaid**，非 OpenAI |

### 证伪结论

**不能**在团队文档写「Codex 官方主色/字体/线宽 = …」。若需统一像素，必须 **自订** `docs/mermaid-config.json` 并标注来源 **S7+团队**。

---

## S20 边界：专有持久画布 vs `.mmd` canonical

**来源：** openai/codex#35100（S1 #35628 Related issues 引述）

**issue 摘要：** 提案 `/design` mode with a **persistent architecture canvas** — 与标准 Mermaid fenced block **不同交互模型**。

**边界含义：**

- 若产品选型 **持久画布** 为唯一编辑面 → `docs/diagrams/*.mmd` **可能非 canonical**
- 本报告默认方案 **失效**；需另定 IR 导出规则

**标注：** **边界**（开放 issue，非已实现产品声明）

---

## S21 边界：Claude VS Code 不计划 inline Mermaid

**来源链：** S10 #14375 → 评论 tactician200（2026-05-22）引 #20529

**可核对陈述（S10 评论）：**

> Issue #20529 … was closed as **`NOT_PLANNED`** … today **no functional path** to render mermaid in the VS Code extension

**边界含义：**

- Claude VS Code 聊天窗 **不能**作为 Mermaid 预览基准
- 与「聊天窗像素一致」目标 **冲突** — 必须 ②+③ 出 SVG

**标注：** **边界**（issue 状态引述，非 Anthropic 官方新闻稿）

---

## S1 边界：CLI TUI 提案禁 `mmdc`

**来源：** S1 #35628 Suggested constraints

| 约束 | 原文要点 |
|------|----------|
| 禁外部 `mmdc` | no shelling out to `mmdc` |
| 禁 Node/Chromium | no Node / Chromium dependency |
| 失败回退 | graceful fallback to original source |

**边界含义：** Codex CLI **终端预览** 与 CI **`mmdc` SVG** 可能 **长期不一致** — 与 §7「生成后重渲」口径一致，**不矛盾**。

---

## S14 边界：bounded Rust Mermaid 子集

**来源：** github.com/warpdotdev/mermaid-to-svg

| 项 | 内容 |
|----|------|
| 形态 | Pure Rust crate Mermaid→SVG |
| 边界 | **子集**语法；高阶/实验语法可能失败 |
| 对策 | ② 白名单 + ③ 完整 `mmdc` 作发布 |

---

## 数字留证（可核对）

| 数字 | 含义 | 出处 |
|------|------|------|
| `16px` | Mermaid 默认 `fontSize` | **S7** theming 表 |
| `#fff4dd` | Mermaid 默认 `primaryColor` | **S7** |
| `@11` | 示例锁定 mermaid-cli major | 团队 CI 约定；CLI 接口 **S9** |
| `NOT_PLANNED` | #20529 关闭状态 | **S10** 评论引述 → **S21** |
