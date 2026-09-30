# E3：Oracle 断言实现而非意图（证伪）

- **出处：** S7 — https://arxiv.org/html/2410.21136；S6 — https://arxiv.org/html/2405.12766
- **标注：** 事实（S7 结论段）；综述（S6 假阳定义）
- **类型：** **证伪** — LLM 生成 assertion **不能默认**代表需求

## S7 原文摘录

> Our findings indicate that LLMs are prone to generate test oracles that capture the **actual program implementation** rather than the **expected one**.

> the overall performance of the LLMs is relatively **low (less than 50% accuracy)**

## S6 原文摘录（假阳定义）

> a **false positive** is a correct and expected program state for which the oracle is false, i.e., a **false alarm**.

> false positives are more critical, as they can lead to false alarms resulting in unnecessary debugging efforts.

## 数字（S7 Table V / Figure 4，事实）

| 指标 | GPT LLM oracle | EvoSuite oracle |
|------|----------------|-----------------|
| 平均 best mutation score | **19.10%** | **17.32%** |

**解读（推断，绑 S7+S6）：** 略高 mutation score **不等于** oracle 正确 — 可能仍锚定错误实现；需人工/规格/差分对照。

## S8 补充（事实）

- 生成 oracle **~40% 丢弃**（编译失败/测失败/需 PIT 绿套件）
- 8 个 failing oracle 经人工确认为 **incorrect (false positives)**（S8 Figure 7 描述）
