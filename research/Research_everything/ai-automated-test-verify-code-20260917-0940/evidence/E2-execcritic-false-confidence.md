# E2：同轨迹自写自测 → 假置信（证伪/边界）

- **出处：** S2 — https://arxiv.org/pdf/2609.09133
- **标注：** 事实（Abstract + §5.2.1）
- **类型：** **边界/证伪** — 证明「有测试闭环 ≠ 有正确性」

## 原文摘录

> Agent-generated tests can encode incomplete or incorrect behavioral targets; when the **same trajectory writes both the patch and the test**, their errors can agree and create **false confidence**.

> Holding the base Repair agent fixed, tests from the base Test agent **reduce resolved rate from 61.2% to 57.3%**, whereas tests from GPT-5.6-generated tests **raise it to 65.3%**.

## 机制对照

| 组件 | 行为 | 出处 |
|------|------|------|
| Test agent | 独立写 repository-native test patch | S2 Fig.1 |
| Harness | fail-closed  qualify + **freeze** tests | S2 Abstract |
| Repair agent | **仅改源码**，不可改 tests | S2 §2 |
| 官方 evaluator | 最终权威 | S2 §1 |

## 推断（绑 S2）

- 「跑测全绿」若测与实现同源，可能是**共谋通过**（coupled repair & validation）
- 缓解：**角色分离 + 测冻结 + 隐藏/人工测作最终 oracle**
