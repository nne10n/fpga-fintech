# AI 跑自动化测试验证代码正确性

- **Slug:** `ai-automated-test-verify-code`
- **Date (Asia/Shanghai):** 2026-09-17 09:40（收紧修订）
- **Tags:** ai-agent, automated-testing, oracle, circular-proof, ci, cocotb, verification
- **Summary:** 拆清三阶段（需求→断言 / 执行 / 判定）；默认 = **契约·人工 AC 作 oracle + CI 执行 + AI 仅补测与失败分类**，**禁止**同模型自测自证；循环证明风险见 report §4。

## 范围

- **In:** 用自动化测试（可含 AI 生成/编排）验证「按需求写出的代码」是否正确的方案；Agent loop；测试类型选型；CI 留证；码测归因；FPGA 仿真可选对照
- **Out:** 训练/微调；完整 IDE 产品设计；与验证无关的生成技巧长文；未核实 ns/准确率编造；UVM 全书；RTL top；策略语义

## 交付物清单

- [x] `report.md` — 收紧版完整报告（§0 假设 → §3 谁在验证什么 → §4 循环证明 → §6 八维对比）
- [x] `sources.md` — S1–S18 可点击 URL
- [x] `evidence/` — E1–E6（含证伪 E2,E3,E4 与 E5,E6 新矩阵）
- [x] `onepager.md`

## Links

- 仓库：[Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- 本目录：`ai-automated-test-verify-code-20260917-0940/`
