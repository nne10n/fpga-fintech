# 一页纸速览：FPGA IOPV 分市场计算与跨市场合成（收紧版）

**Asia/Shanghai 2026-09-16 08:42** · 先钉口径再比方案 · 上游已解析行情字段

## 结论（≤10 行）

1. **口径：** partial = **可加贡献项**（`Σqty×px` + **本 leg 本地必须替代 cash**）；合成 = **只汇合** partial×FX + global 项 → ÷unit — **禁止回头重算成分**。
2. **默认拓扑 B0：** per-leg **累加器** + **同钟**中心 synth；跨卡才 CDC。
3. **新 tick：** `partial[leg]+=qty×Δpx`；halt/auction/circuit/**valid=0** → **不更新 px、partial 不变**（ffill）。
4. **未齐：** **仍输出 IOPV** + `quality`/`coverage`；不因一侧未开盘 withhold（除非产品 gate）。
5. **权重：** 日更 **shadow swap + partial 重播种**；盘中热更 **必须双缓冲+pause**。
6. **FX 跳变：** **不重扫成分**；仅 O(legs) synth 重算。
7. **停牌默认：** last valid ffill + stale；除权 **Host 日更 adjustment**。
8. **数值：** 64b 定点累加；IOPV **round 4dp**（SSE）；last 主路，bid/ask 可选并行路。
9. **触发：** 片内逐笔；对外 15s/阈值 gate。
10. **换方案：** 权重频繁热更→D1/Host；跨市长时间错位→stale+px_override 或 withhold。

## 冻结八维对比（默认 B0 加粗）

| 触发 | partial 结构 | 汇合点 | 静态表 | 停牌/熔断/竞价 | FX/替代 | 数值 | 出处 |
|------|--------------|--------|--------|----------------|---------|------|------|
| **逐笔 Δ** | **累加器** | **同钟** | BRAM+DMA swap | ffill 不更新 | leg cash；FX@synth | 64b→4dp | Exegy |
| 定时 gate | 影子快照 | 同钟 | 同左 | 同左 | 同左 | 同左 | 审计 |
| 权重变更 | 重播种 | CDC | 双缓冲 | 同左 | 同左 | 同左 | 热更 D1 |
| Host 批 | Host Σ | Host | DB | Host | Host | float | DolphinDB |

## 机制四问（B0 默认答）

| 新 tick→partial | 未齐输出？ | 热更双缓冲？ | FX 跳变整幅重算？ |
|-----------------|------------|--------------|-------------------|
| `partial[leg]+=qty×Δpx` | **是**+degraded | 日更 swap；热更 shadow+pause | **否**，O(legs) synth |

## 假设（缺则待核实）

| 参数 | 假定 |
|------|------|
| 市场 | 沪/深主；港扩展 |
| 上游字段 | symbol_id, market_id, px, px_type, ts, valid, session_state |
| 权重 | 日更；盘中热更待核实 |
| FX 源/刷新 | 估值汇率；刷新频率待核实 |
| 停牌 | last valid ffill；除权 Host |
| 输出 | IOPV + quality + coverage |

详见 [report.md](./report.md)。
