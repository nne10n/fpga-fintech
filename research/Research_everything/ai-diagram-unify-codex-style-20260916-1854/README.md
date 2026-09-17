# AI 方案设计图跨工具统一 → Codex 风格

- **Slug:** `ai-diagram-unify-codex-style-20260916-1854`
- **Date (Asia/Shanghai):** 2026-09-16 18:54（收紧修订）
- **Tags:** AI 协作, Mermaid, Codex, IR, mmdc, 风格统一
- **Summary:** 默认 **② `.mmd` + ③ 锁定 `mmdc`**；**S19 证伪** 无官方 Codex 绘图 Spec；留证硬规则：表单元格/机制/数字 **必绑 S#**。

## 留证硬规则

1. 对比表、机制断言、数字 → 指 [`sources.md`](./sources.md) **S1–S21**；写不出 → **待核实** 或删
2. 证据分级：**事实 / 推断 / 待核实 / 证伪 / 边界** 贯穿 report 与 evidence
3. 开源仓写清 **文件/接口/CLI 参数**（如 S9 `mmdc -i/-o/-c`）
4. **Out：** 未核实 ns、RTL top、策略报单；不编 Codex「官方规范」

## 交付物

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 详尽报告（摘要≤10行 + 链 one-pager） |
| [onepager.md](./onepager.md) | 一页纸速览 |
| [sources.md](./sources.md) | **21** 条；含 **S19 证伪、S20/S21 边界** |
| [evidence/](./evidence/) | 主源摘录、证伪/边界、像素核对、CI 片段 |

## 默认方案 + 翻车

- **默认：** ① Skill → ② `.mmd` → ④ lint → ③ `mmdc` → `.svg`（**S9,S7**）
- **翻车：** 专有画布 S20、bounded S14、ASCII S10、classDef 主路径、位图 canonical、聊天窗一致 S21

## Links

- 仓：https://cursor.com/codebase/melon5253/Research_everything
- 目录：`ai-diagram-unify-codex-style-20260916-1854/`
- 上一版：`ai-diagram-unify-codex-style-20260916-0853/`
