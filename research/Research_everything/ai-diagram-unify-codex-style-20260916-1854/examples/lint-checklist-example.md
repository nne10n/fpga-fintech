# 校验清单：F1–F12 · 每行绑出处

## `agent-loop-codex-style.mmd`

| ID | 特征 | 结果 | 出处 |
|----|------|------|------|
| F1 | Mermaid 源码 | ✅ | S1 |
| F2 | 非手绘 | ✅ | S1 |
| F3 | flowchart TD | ✅ | S1 |
| F4 | `-->` | ✅ | S1,S6 |
| F5 | `[]`/`{}` | ✅ | S1 |
| F6 | subgraph | ✅ | S6 |
| F7 | 无 classDef | ✅ | S1,S2 |
| F8–F9 | 像素 | ⬜ `mmdc` 后查 | S7,S9 |
| F10 | 边标签 | ✅ | S1 |
| F12 | 无 emoji | ✅ | S1 |

## `before-after.mmd` BEFORE（合成 · S18）

| ID | 结果 | 出处 |
|----|------|------|
| F7/F12 | ❌ classDef | **S18** 合成，非 primary |

## CI lint（路径④ · S16）

```javascript
assert(noClassDef(source));   // S1,S16
assert(noAsciiBoxDrawing);   // S10
assert(diagramTypeWhitelist); // S6,S16
```

## 像素回归

1. `mmdc` **S9** `-i/-o/-c`
2. [`evidence/pixel-verification-checklist.md`](../evidence/pixel-verification-checklist.md) **S7**
