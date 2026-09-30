# E6：冻结对比维 — 单元格出处绑定

> report §6 综合对比表；每维取值须可回溯 S#

| 方案 | oracle 来源 | 人机门禁位置 | 同模型自测自证 | 覆盖层 | 失败定位 | CI 留证 | 成本/幻觉 | 出处 |
|------|-------------|--------------|----------------|--------|----------|---------|-----------|------|
| **契约+CI（推荐默认）** | 人工 AC + OpenAPI | merge 前人审 PR | **禁止** M 自签 | 单测+集成+隐藏 | CI log 行号 | run URL+JUnit+exit | 低/中 | S3,S4 推断 |
| Cursor run-and-fix | LLM assertion | 弱（同会话） | **允许** | 单测为主 | stderr 栈 | 本地 log | 低/高 | S3 |
| TDFlow 人写测 | 人工 reproduction | 人写测即门禁 | 测人写码 Agent | 单测+回归 | Debug One 报告 | 沙箱 log | 中/中 | S1 |
| EXECCRITIC | 冻结 Test+隐藏 | 官方 evaluator | Test≠Repair 角色 | repo-native | 执行反馈 | bundle 冻结 | 高/中 | S2 |
| Agentic PBT | 文档挖性质 | scoring 人工 rubric | Agent 写性质非实现 | 性质测 | Hypothesis shrink | bug report 文件 | 中/中 | S11,S12 |
| 差分 | 双实现一致 | 人确认 bug | 可交叉 | 定向输入 | 差异输出 | 区分测列表 | 高/中 | S13 |
| CI autofix | **既有 CI** | fix PR 人审 | CI 测非 Agent 写 | 同 CI | failed job log | workflow_run id | API/低 | S5 |
| EDA-Agent verify | 参考模型/断言 | 人看 VCD | Agent 可写 TB+RTL | **仿真**非单测 | triage-log | VCD/JUnit | 中/中 | S15 |

**覆盖层说明（推断）：** 软件单测 ≠ RTL 仿真；FPGA 行见 S15,S16，勿与 pytest 层混计。
