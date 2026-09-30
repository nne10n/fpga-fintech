# E1：TDFlow 人机测 vs 自生成测（摘录）

- **出处：** S1 — https://arxiv.org/html/2510.23761v2
- **标注：** 事实（Table 2 原文）
- **核对路径：** §4.2 / Table 2

## 原文摘录

> When provided with human-written tests, TDFlow achieves a **94.3%** success rate on SWE-Bench Verified … Combined with the **68.0%** performance when generating its own tests, this suggests the test resolution capabilities of TDFlow are already human-level, while the final hurdle in LLM repository-scale issue resolution lies within **test generation**.

| System | Pass Rate | Cost/Issue | Test Resolution Cost |
|--------|-----------|------------|------------------------|
| TDFlow: LLM-generated | 68.0% | $4.12 | $2.83 |
| TDFlow: Human-written | 94.3% | $1.01 | $1.01 |

## BTR 边界（事实）

- BTR = 不成功 reproduction tests / 总 LLM 生成 tests
- **BTR=0**（全部 reproduction 有效）时 solve rate **93.3%**（S1 Figure 2 描述）
- 推论：测质量决定下游「解测」上限，而非 patch 推理能力本身

## 机制断言

- TDFlow **不允许**修改 reproduction tests（§5 Discussion）
- 四子 Agent：Generate Tests → Explore Files → Debug One → Revise Patch（S1 Figure 1）
