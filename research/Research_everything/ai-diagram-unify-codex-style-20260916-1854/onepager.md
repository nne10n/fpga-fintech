# 一页纸速览 · AI 方案设计图 → Codex 风格

Asia/Shanghai 2026-09-16 · 目录 [`ai-diagram-unify-codex-style-20260916-1854/`](.) · 仓 [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)

---

## 默认方案

```text
① Skill（结构） → ② docs/diagrams/*.mmd → ④ lint → ③ mmdc（锁版本+主题）→ docs/figures/*.svg
```

- **主路径**：② IR + ③ 锁定 `@mermaid-js/mermaid-cli`（`mmdc -i -o -c`）— **S9**
- **辅**：① Skill 降 IR 脏度 — **S15**
- **门**：④ strip `classDef`、IR diff — **S16**
- **口径**：**生成后一键重渲**；聊天窗预览不作 canonical — **S1,S10**

## Codex 风格是什么（非官方 Spec）

OpenAI **未公开** Diagram Design System — **证伪 S19**。可操作锚点 = **§2 F1–F12**（issue 样例 + Mermaid 文档）；像素色值来自 **Mermaid `themeVariables`** — **S7**，禁止写「官方 Codex 色」。

## 四路径（禁止混写）

| 路径 | 管什么 | 出处 |
|------|--------|------|
| ① Skill | 结构/语法 | S15 |
| ② `.mmd` IR | diff、解耦 | S1,S6 |
| ③ `mmdc` 主题 | **发布 SVG 像素** | S7,S9 |
| ④ lint/SVG | 漂移、CI 门 | S16 |

**提示词管不住**：F7–F9 颜色/字体/线宽、各宿主 Mermaid 版本 — **S1,S7,S10**

## 位图降级

仅 PNG → `_derivative/`（非 canonical）→ 反写 `.mmd` → ③ 重渲；S2 建议「Mermaid 源 + SVG/PNG 查看」— **S2**

## 翻车条件

| 条件 | 出处 |
|------|------|
| 专有画布（`/design` 持久画布）锁死 IR | **S20** |
| bounded 渲染器 + 高阶 Mermaid 语法 | **S1,S14** |
| Claude ASCII 替代架构图 | **S10** |
| `classDef` 当风格主路径 | **S1,S2**（样例无） |
| 位图当 canonical | **S2** |
| 指望聊天窗像素一致 | **S1,S21** |

## Out

训练微调、完整绘图 SaaS、**未核实 ns / RTL top / 策略报单**、编造 Codex 官方 VI。

## 证据入口

[`report.md`](./report.md) · [`sources.md`](./sources.md)（S1–S21）· [`evidence/`](./evidence/)
