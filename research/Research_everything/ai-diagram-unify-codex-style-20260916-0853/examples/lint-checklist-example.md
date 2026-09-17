# 校验清单：对照 §2 冻结特征 F1–F14

## 对 `agent-loop-codex-style.mmd`

| ID | 特征 | 结果 | 标注 |
|----|------|------|------|
| F1 | Mermaid 源码 | ✅ | — |
| F2 | 非手绘 | ✅ | — |
| F3 | flowchart TD | ✅ | — |
| F4 | `-->` 箭头 | ✅ | — |
| F5 | `[]` / `{}` | ✅ | — |
| F6 | subgraph | ✅ turn 子图 | — |
| F7 | 无 classDef | ✅ | — |
| F8–F10 | 字体/线宽/圆角 | ⬜ 跑 `mmdc` 后查 SVG | 待核实 |
| F11 | dagre 布局 | ⬜ 自动 | — |
| F12 | 无 emoji/icon | ✅ | — |
| F13 | 边标签 | ✅ yes/no | — |

## 对 `before-after.mmd` BEFORE 段（合成漂移）

| ID | 结果 |
|----|------|
| F1 | ⚠️ 注释态 |
| F3 | ❌ `graph` |
| F5 | ❌ ID 空格 |
| F7/F12 | ❌ classDef |

## CI lint 规则映射（路径④）

```javascript
// 伪代码：scripts/lint-mermaid.js
assert(noClassDef(source));      // F7, F12
assert(diagramTypeWhitelist);    // F1, F3
assert(nodeCount <= 15);         // 团队扩展
assert(noReservedNodeIds);       // F5 扩展
```

## 像素回归（路径③+④）

1. `mmdc -c docs/mermaid-config.json -i x.mmd -o x.svg`
2. 可选：rasterize SVG → pixelmatch 与 `x.svg golden`
