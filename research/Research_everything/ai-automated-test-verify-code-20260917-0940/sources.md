# 出处索引（sources.md）

> 标注：**事实** = 可核对原文/仓内路径；**推断** = 由多源归纳；**待核实** = 缺 primary 或仅单源

| ID | URL | 类型 | 标注 | 支撑点 |
|----|-----|------|------|--------|
| S1 | https://arxiv.org/html/2510.23761v2 | 论文 TDFlow | 事实 | 四子 Agent 闭环；人写测 94.3% vs LLM 自生成 68.0%（SWE-Bench Verified）；BTR=0 时 93.3%；test hacking 仅 7/800 |
| S2 | https://arxiv.org/pdf/2609.09133 | 论文 EXECCRITIC | 事实 | Test/Repair 角色分离；fail-closed 冻结测；差测 61.2%→57.3%，好测→65.3%；组合 72.6% |
| S3 | https://cursor.com/for/test-generation | 产品文档 | 事实 | run-and-fix 闭环；Auto-run；需求→测→码；CI 失败修复入口 |
| S4 | https://cursor.com/docs/cli/github-actions | 产品文档 | 事实 | CI 中 `agent -p`；全/受限自治；permissions JSON |
| S5 | https://github.com/wrowston/ci-autofix | 开源仓 | 事实 | `if: failure()` 触发 Cloud Agent；复用 workflow |
| S6 | https://arxiv.org/html/2405.12766 | 论文综述 | 事实 | oracle 假阳/假阴；变异分析评 oracle 强度 |
| S7 | https://arxiv.org/html/2410.21136 | 论文实证 | 事实 | LLM oracle 常断言**实现**非**预期**；GPT 变异分 19.10% vs EvoSuite 17.32% |
| S8 | https://homes.cs.washington.edu/~mernst/pubs/neurosymbolic-oracles-ase2025.pdf | 论文 ASE'25 | 事实 | 生成 oracle 约 40% 丢弃；8 个假阳；与人工 oracle 变异分接近 |
| S9 | https://doi.org/10.1109/icse55347.2025.00098 | 论文 TOGLL ICSE'25 | 事实 | TOGLL 正确 assertion 3.8× TOGA；仍约 25% 假阳 |
| S10 | https://yangrenyu.github.io/paper/issta2026.pdf | 论文 ISSTA'26 | 事实 | Prohibited vs Unrestricted 修复率差 ≈1.25pp；**执行反馈非单调有益** |
| S11 | https://arxiv.org/html/2510.09907v1 | 论文 agentic-pbt | 事实 | Hypothesis PBT agent；100 包 56% 有效 bug；3 patch 合并 |
| S12 | https://github.com/mmaaz-git/agentic-pbt | 开源仓 | 事实 | `run.py` 并行测包；`scoring.py` 人工复核 rubric |
| S13 | https://arxiv.org/html/2410.04249v3 | 论文差分测 | 事实 | 规格+实现差异→LLM 差分测；eBPF 1901 条、Wasm 299 条 |
| S14 | https://arxiv.org/abs/2608.16742 | 论文 TDD-Agent | 事实 | test-first + 双轨 refine；RepoEval 优于基线；变异分/覆盖率提升 |
| S15 | https://github.com/ashishsinghbora/eda-agent | 开源仓 | 事实 | `verify`/`sim` 命令；cocotb 闭环自修复；README 架构图 |
| S16 | https://arxiv.org/html/2608.27148 | 论文 AgentDV | 事实 | Verilator+cocotb+pyUVM；CSR 接地；coverage 引导迭代 |
| S17 | https://ar5iv.labs.arxiv.org/html/2607.26181 | 论文 GoGoTB | 事实 | cocotb 优于 SV 直生成；规格接地 coverage closure |
| S18 | https://github.com/mrigankpawagi/PropertyEval | 开源仓 | 事实 | HumanEval Hypothesis strategy；EvalPlus 对标 |

## 抓取备注

| 源 | 状态 | 备注 |
|----|------|------|
| S1 | 200 OK | arXiv HTML；Table 2 数字已摘录至 `evidence/E1-tdflow-excerpt.md` |
| S2 | 200 OK | PDF 转文本；Abstract §5.2.1 数字见 `evidence/E2-execcritic-false-confidence.md` |
| S3–S4 | 200 OK | Cursor 官方文档 |
| S5 | 200 OK | GitHub README；workflow 片段见 report §6 |
| S15 | 200 OK | raw README；`verify`/`sim` CLI 表核对 |
| S10 | 200 OK | ISSTA PDF；Table 2 见 `evidence/E4-comparison-table-cells.md`（ISSTA 行） |
| E5/E6 | — | 本仓推断框架；机制格绑 S1–S5,S15 |
