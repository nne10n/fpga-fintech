# FPGA IOPV 分市场计算与跨市场合成调研

- **Slug:** `fpga-iopv-per-market-cross-synth-20260916-0842`
- **Date (Asia/Shanghai):** 2026-09-16 08:42
- **Revision:** 提示词大师口径收紧（先钉 partial/合成定义 → 再比方案；冻结八维对比；机制四问）
- **Tags:** FPGA, IOPV, iNAV, ETF, partial, cross-market, FX, CDC, BRAM, incremental
- **Summary:** 默认 **B0**：per-leg **可加 partial 累加器**（含本 leg 本地必须替代 cash）→ **同钟中心合成**（只汇合 partial×FX + global 项，**禁止回头重算成分**）；逐笔 `partial[leg]+=qty×Δpx`；未齐 **仍输出** + quality/coverage；权重 **shadow swap + partial 重播种**；FX 跳变 **仅 O(legs) synth**；停牌/集合竞价/熔断 **ffill 不更新 px**。

## 范围

- **In：** 分市场 partial 计算与跨市合成的 **数据路径 + 控制规则**（双缓冲、stale/coverage、版本 tag）；静态表/替代标志入表；上游已解析字段接口
- **Out：** 行情解析重做；策略/报单；完整 RTL top/core；ETF 申赎状态机（**仅替代标志入表**）；未核实 ns；合规/会计长文

## 决策问题

1. partial 与合成如何切？→ §3.3–3.4、§4
2. 输入如何进硬件、如何更新？→ §6.1–6.3
3. 默认组合与换方案条件？→ §7（含权重热更、跨市时段错位）

## 文件

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 详尽正文（文首结论+速览；假设先行；冻结八维表含机制四问） |
| [onepager.md](./onepager.md) | 一页纸速览 |
| [sources.md](./sources.md) | ≥16 条出处（事实/推断/待核实） |
