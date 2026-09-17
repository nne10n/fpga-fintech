# 一页纸速览：FPGA IOPV 分市场计算与跨市场合成

**目录：** `fpga-iopv-per-market-cross-synth-20260916-1854/` · **仓：** Research_everything · **Asia/Shanghai 2026-09-16 18:54**

## 结论（≤10 行）

1. **口径（S3）：** partial = 可加项（`Σqty×last_px` + 本 leg 必须替代 cash）；合成 = **只汇合** `Σ(partial×FX)+global_cash` → ÷unit；**禁止**合成回头算 `qty×px`。
2. **默认 B0（S1+S2 交叉 → 推断）：** per-leg 增量累加器 → 同钟 synth；跨卡 CDC **待核实**。
3. **tick→partial（S1 Claim 6–7, S2 §5.3）：** `partial[leg]+=qty×Δpx`；无价变 tick 可 skip（S2 ~75%）。
4. **halt/auction/valid=0（S2 ffill, S3 last）：** 冻结 px 更新；partial 不变；**推断** 映射 `session_state`。
5. **未齐（S10, S2）：** **仍输出** IOPV + `quality`/`stale_leg_mask`；不因闭市 leg withhold（**推断** 除非产品 gate）。
6. **权重（S4 日更清单, S1 Claim 21–22）：** 日更 shadow swap + partial **重播种**；盘中热更 **待核实** → 必须双缓冲+pause（**推断**）。
7. **FX 跳变（S9 `fxt`）：** partial 不变；仅 synth O(legs) 重算；**非**整幅扫成分。
8. **数值（S3,S9 事实 / S15 推断）：** 中间定点 **64b 待核实**；输出 **round 4dp**。
9. **对外（S3,S8,S11）：** 片内逐笔维护；dissemination **15s** 或阈值 gate（S1 Claim 24–28）。
10. **翻车：** 权重 >1×/日热更 → D0/D1；闭市需 FV → Host px_override（S9 §2.2.4）；**S11 证伪** IOPV≠NAV 不可对外宣称等价。

## 冻结八维（每格绑出处）

| 维 | B0 默认 | 出处 | 标注 |
|----|---------|------|------|
| 触发 | 逐笔 Δ；出 15s gate | S2 perRow; S3,S11 15s; S1 Claim 24–28 | 事实+推断 |
| partial | 累加器/leg | S1 Claim 6–7; S2 cumsum | 事实+推断 |
| 汇合 | 同钟 synth | — | **待核实**（无公开 FPGA 多 leg 实例） |
| 静态表 | 双表 symbol→basket | S1 Claim 20 | 事实 |
| 停牌/竞价 | ffill；无效态不更新 px | S2 ffill; S3 last | 事实+推断 |
| FX/替代 | leg cash 常数；FX@synth | S3 三类替代; S7,S9 fxt | 事实+推断 |
| 数值 | 64b 中间；出 4dp | S3,S9 4dp; S15 定点库 | 事实+推断 |
| 未齐 | 输出 + degraded | S10 stale; S2 ffill | 事实+推断 |

## 机制四问（B0）

| 问 | 答 | 出处 |
|----|-----|------|
| tick→partial | `partial[leg]+=qty×Δpx` | S1,S2,S3 |
| 未齐输出？ | **是** + quality | S10,S2 |
| 热更双缓冲？ | 日更 swap+重播种；盘中 **待核实** | S1 Claim 21–22, S4 |
| FX 跳变整幅重算？ | **否**，O(legs) synth | S9 |

## Out

未核实 ns · RTL top · 策略报单 · 行情解析重做 · 申赎状态机深挖

详见 [report.md](./report.md) · [sources.md](./sources.md) · [evidence/](./evidence/)
