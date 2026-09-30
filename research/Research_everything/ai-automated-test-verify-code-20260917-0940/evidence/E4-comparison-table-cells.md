# E4：综合对比表单元格 → 出处映射（初版）

> **收紧后**以 [`E6-frozen-comparison-dimensions.md`](E6-frozen-comparison-dimensions.md) 为准；本文件保留初版方案维对照。
> 供 `report.md` 审计；每格必须可回溯

| 方案 | 测试由谁生成 | 执行环境 | Oracle 来源 | 失败修复 | CI 化 | 假绿风险 | 落地成本 | 主出处 |
|------|-------------|----------|-------------|----------|-------|----------|----------|--------|
| Cursor run-and-fix | Agent（可同人） | 本地终端 / Auto-run | 生成 assertion + 运行输出 | 读 stderr 改测或实现 | S4 CLI | 中高（同轨迹） | 低 | S3,S4 |
| TDFlow 人写测 | 人类 reproduction | 沙箱跑全 suite | 人写测 = oracle | Debug One 报告 → Explore 改 patch | 待核实 | 低-中（7/800 hacking） | 中（多 Agent） | S1 |
| TDFlow 自生成 | Generate Tests 子 Agent | 同上 | LLM 测 + BTR 筛选 | 同上但不改测 | 待核实 | **高**（BTR>0） | 高（$4.12/issue） | S1 |
| EXECCRITIC | **独立** Test agent | 项目原生 toolchain | 冻结 agent 测 + 隐藏官方 | Repair 仅改源码 | 可包装 | 中（测质量依赖训练） | 高（RL 训练） | S2 |
| TDD-Agent | LLM test-first | 执行反馈双轨 refine |  evolving tests | 测+码同时 refine | 待核实 | 中 | 中 | S14 |
| Agentic PBT | Agent 挖性质 | pytest+Hypothesis | 文档/代码推性质 | shrink 失败例 → 报告 | `run.py` 可并行 | 低-中（56% 有效 bug） | 中 | S11,S12 |
| 差分 LLM | Agent 读 spec+diff | 多实现对比 | **双实现一致** | 差异即失败 | 定制 | 低（需第二实现） | 高 | S13 |
| CI autofix | Cloud Agent | GitHub Actions | **既有 CI 测** | Agent 开 fix PR | **原生** | 低-中 | 低（+API 费） | S5,S4 |
| ISSTA 无执行修复 | Agent 禁止跑测 | 只读分析 | 隐藏 SWE 测 | 单次/少次 patch | 易 | N/A（不本地验） | 最低 token？ | S10 |
| EDA-Agent verify | Agent 生成 cocotb | Icarus+cocotb make | 参考模型/断言 | sim 失败 → repair loop | Docker | 中（无 spec 时） | 中（EDA 链） | S15 |
| AgentDV | LLM per plan item | Verilator+cocotb | **CSR 寄存器表** | coverage gap 定向补测 | LangGraph | 低-中（CSR 层） | 高 | S16 |

## ISSTA 边界摘录（E4 附属，S10 事实）

> Prohibited vs Unrestricted gap … averaged … only **1.25pp** … **does not produce a reliably positive effect** on repair outcomes.

**证伪含义：** 在 SWE-bench 类任务上，「多跑测迭代」**不保证**比不跑测更好 — 不能将「执行反馈」当作默认增益假设。
