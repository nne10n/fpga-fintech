# Skill: diagram-codex-style

---
name: diagram-codex-style
description: 生成对齐 Codex 可观察习惯的 Mermaid 架构/数据流/时序图。触发词：架构图、数据流、模块关系、agent loop。
---

## 路径定位

- 本 Skill = **路径①**（结构/语法）；**不**承诺聊天窗像素
- 合并前必须走 **路径②③**：`.mmd` → `mmdc` → `.svg`

## 硬规则（映射 F1–F12）

| 规则 | 冻结 ID |
|------|---------|
| 只输出 `docs/diagrams/<slug>.mmd` 或 ` ```mermaid ` 围栏 | F1 |
| 禁止 Excalidraw/纯 PNG 替代架构图 | F1,F2 |
| 禁止 ASCII 框图替代架构图（Claude 漂移） | F1,F2 |
| `flowchart TD`（架构）或 `LR`（链路）；sequence/state 按需 | F3 |
| 过程 `[]`、决策 `{}`；边用 `-->` 与 `\|label\|` | F4,F5,F10 |
| `subgraph id [Label]` 表达 Client/Harness/Core/Tools | F6 |
| **禁止** `classDef`/`style`/`linkStyle`/emoji/icon | F7,F12 |
| 节点 ≤15；ID camelCase；标签特殊字符加引号 | 团队扩展 |
| 图后 ≤5 行图例（缩写、信任边界） | F6 扩展 |

## 提示词 **管不住**（必须告知用户）

- 颜色/字体/线宽/圆角 → **CI `mmdc` 主题**（F7–F9）
- 聊天窗预览 ≠ 发布 SVG（F11）

## 位图降级

若工具只给 PNG：存 `_derivative/`，**不得**当 canonical；必须反写 `.mmd` 后重渲。

## 模板

- [agent-loop-codex-style.mmd](./agent-loop-codex-style.mmd)
- [app-server-harness.mmd](./app-server-harness.mmd)
