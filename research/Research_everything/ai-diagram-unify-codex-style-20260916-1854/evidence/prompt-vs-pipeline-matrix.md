# 提示词 vs 管道：控制力矩阵

支撑 report §3 · **每行绑 S#**

| 输出属性 | ① Skill | ② IR | ③ mmdc | ④ 后处理 | 聊天窗 | 出处 |
|----------|---------|------|--------|----------|--------|------|
| diagram type | ✅ | ✅ | — | ✅ lint | ⚠️ | S15,S16 |
| TD/LR | ✅ | ✅ | — | — | ⚠️ | S6 |
| subgraph | ✅ | ✅ | — | — | ⚠️ | S6 |
| 禁 classDef | ✅ | ✅ | — | ✅ strip | ❌ | S1,S16 |
| 禁 ASCII 架构 | ✅ | — | — | — | ❌ | S10 |
| fill 色 | ❌ | ❌ | ✅ themeVariables | ✅ | ❌ | **S7** |
| font-family | ❌ | ❌ | ✅ | ✅ | ❌ | **S7** |
| stroke-width | ❌ | ❌ | ⚠️ | ✅ | ❌ | S7 |
| git diff IR | ❌ | ✅ | — | — | ❌ | S9 |
| 发布 SVG 一致 | ❌ | ⚠️需③ | ✅ | ✅ | ❌ | **S9** |

## 误判纠正

| ❌ | ✅ | 出处 |
|----|-----|------|
| AGENTS.md 写 neutral 主题 | `mermaid-config.json` + CI | S7,S9 |
| ChatGPT 里对了就行 | `mmdc` SVG 为准 | S1 |
| 后处理 alone | 须先有 `.mmd` | S9 |

## ① 声明模板

> Mermaid 输出只保证 **结构**（S15）；**颜色/字体以 `mmdc` SVG 为准**（S7,S9）；聊天预览不作数（S1,S21）。
