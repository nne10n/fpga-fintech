# AI 方案设计图跨工具统一 → Codex 风格

- **Slug:** `ai-diagram-unify-codex-style-20260916-0853`
- **Date (Asia/Shanghai):** 2026-09-16 08:53
- **Tags:** AI 协作工具, 设计文档, Mermaid, Codex, 架构图, 风格统一
- **Summary:** **② Mermaid IR + ③ 单一 `mmdc` 渲染主题** 为主路径，**① Skill** 约束结构为辅，**④ lint/后处理** 为 CI 门；一致性口径为 **生成后一键重渲**；§2 冻结 F1–F14 特征清单（事实/推断/待核实分列）；不存在可引用的官方 Codex Diagram Design System。

## 范围

- **In:** 统一到 Codex 可观察视觉/结构习惯的 **实现方案**；四条路径对比；Skill/渲染管线；位图降级；Markdown + Mermaid 协同
- **Out:** 训练/微调模型；完整绘图产品；FPGA 等无关专题；未核实的品牌法律结论；编造「官方 Codex Design Spec」

## 一句话结论

**Canonical = `docs/diagrams/*.mmd` → 锁定主题的 `mmdc` → `docs/figures/*.svg`**；提示词只管结构与语法，**像素一致靠渲染管道，不靠聊天窗**。

## 文件

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 详尽调研报告（修订版） |
| [onepager.md](./onepager.md) | 一页纸速览 |
| [sources.md](./sources.md) | 出处索引（≥10） |
| [examples/](./examples/) | Skill、Mermaid 对比、自检清单 |

## Links

- 仓库：https://cursor.com/codebase/melon5253/tmp-1675434d3013d1ad
- 本目录：`ai-diagram-unify-codex-style-20260916-0853/`
