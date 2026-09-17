# FPGA IOPV 分市场计算与跨市场合成 — 详尽调研报告

**Asia/Shanghai 2026-09-16 18:54** · 批量统一收紧版 · 上游已具备硬件行情解析  
**仓：** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything) · **目录：** `fpga-iopv-per-market-cross-synth-20260916-1854/`

**留证硬规则：** 对比表单元格、机制断言、数字均指出来处 ID；无出处则标 **待核实** 或删除。标注：**事实** / **推断** / **待核实**。

---

## 结论摘要（≤10 行）

1. **口径（事实 S3）：** IOPV 用 **最新成交价** × 清单 qty，加必须替代金额与预估现金差额，÷最小申赎单位。**分市场 partial** = leg 内可加项（`Σqty×px` + 本 leg 必须替代 cash，S3）。**合成** = 只读 partial → ×FX（S7,S9）→ +global_cash（S3）→ ÷unit；**禁止**合成阶段重算 `qty×px`（**推断**，由 S9 公式 FX 与 price 分离推导）。
2. **默认 B0（推断，S1+S2 交叉）：** per-leg 增量累加器 → 同钟中心 synth；跨 FPGA leg 用 CDC — **待核实**（无公开 RTL 实例）。
3. **tick→partial（事实 S1 Claim 6–7, S2 §5.3）：** `partial[leg]+=qty×(px_new−px_old)`；S2 称约 **75%** tick 无价变可过滤。
4. **无效价/非连续态（事实 S2 ffill + 推断）：** valid=0 或 auction/halt → 不更新 px、partial 不变；映射 `session_state` **待核实**。
5. **未齐（事实 S10,S2）：** 跨时区仍用 stale last 参与 iNAV；**仍输出** + `quality`/`stale_leg_mask`（字段名 **推断**）；withhold 仅当产品 gate — **待核实**。
6. **权重（事实 S4 日更清单, S1 Claim 21–22）：** 官方 PCF **日更**；swap 时 partial **重播种**（**推断**）；盘中热更频率 **待核实** → 若 >1×/日换 D0/D1（**推断**）。
7. **FX 跳变（事实 S9）：** `fxt` 与 `pit` 分离 → partial 不变，仅 synth 重算；**非** O(M) 成分重扫（**推断**）。
8. **数值（事实 S3,S9）：** IOPV 发布 **4 位小数**；中间累加用定点 **64b** — bit 宽 **待核实**（S15 仅 L2/L3 定价库参考，**推断**）。
9. **对外（事实 S3,S8,S11）：** 交易所/披露 **15s**；片内可逐笔维护（S2 perRow）；阈值 gate — S1 Claim 24–28（**事实**）。
10. **翻车 + 证伪（事实 S11）：** IOPV **≠** 实时 NAV、清单 **≠** 持仓 — 不可对外宣称等价；权重热更频 → D0/D1；闭市需 FV → Host px_override（S9 §2.2.4, S12 waterfall，**推断** 硬件不内置 FV）。

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)

| 冻结维 | B0 默认 | 出处 | 标注 |
|--------|---------|------|------|
| 触发 | 逐笔 Δ；出 15s gate | S2; S3,S11; S1 Claim 24–28 | 事实+推断 |
| partial | 累加器/leg | S1 Claim 6–7; S2 §5.3 | 事实+推断 |
| 汇合 | 同钟 synth | — | **待核实** |
| 表 | symbol 反向 + basket 正向 | S1 Claim 20 | 事实 |
| 停牌/竞价 | ffill；无效态 freeze px | S2; S3 | 事实+推断 |
| FX/替代 | leg cash；FX@synth | S3; S7; S9 | 事实+推断 |
| 数值 | 64b **待核实**；出 4dp | S3; S9; S15 | 事实+推断 |
| 未齐 | 输出 + degraded | S10; S2 | 事实+推断 |

---

## 1. 范围

### In

- 分市场 partial 数据路径；跨市场合成数据路径；双缓冲/stale/coverage/版本 tag
- 静态表（PCF/IOPV 清单字段、替代标志，S4）
- 上游已解析 tick 字段（**推断** 接口契约，见 §10）

### Out

- 行情协议解析 / TCP / feed handler 重做
- 策略、报单
- RTL top/core 规格
- ETF 申赎状态机（**仅**替代标志 must/may/forbid 入表，S3）
- 未核实 **ns** 延迟
- 合规/会计长文

---

## 2. 假设（无出处即待核实）

| 参数 | 假定 | 标注 | 出处 |
|------|------|------|------|
| 主市场 | 沪 SSE + 深 SZSE；港 HKEX 扩展 | 待核实 | — |
| 上游字段 | `symbol_id, market_id, px, px_type, ts, valid, session_state` | 推断 | §10 |
| 权重频率 | 1×/日 PCF/IOPV 清单 | 事实 | S4, S8 |
| 盘中 PCF 热更 | 非官方默认 | 待核实 | — |
| FX 源/刷新 | 估值汇率（港股通 S7）；刷新频率 | 事实+待核实 | S7, S9 |
| 纯 A 股 | 无 FX，CNY 两 leg | 推断 | S3 |
| 并行 ETF 数 B | — | 待核实 | — |
| 成分数 M 上限 | — | 待核实 | — |

---

## 3. 术语与口径

### 3.1 IOPV vs NAV

| 术语 | 含义 | 出处 | 标注 |
|------|------|------|------|
| NAV | 日终净值，1×/日 | S8, S11 | 事实 |
| IOPV/iNAV | 盘中指示性净值，基于 calculation basket + 盘中价 | S3, S10, S12 | 事实 |
| Creation unit | 最小申赎单位 = 归一除数 | S3, S10 | 事实 |

**证伪边界（事实 S11，见 [evidence/S11](evidence/S11-sec-iopv-boundary-falsify.md)）：** IOPV **不应**视为 NAV 实时更新；清单 **可能**≠ 基金持仓。

### 3.2 公式（先钉再选型）

**沪深（事实 S3）：**

```text
IOPV = (必须现金替代 + Σ可替代 qty×last + Σ禁替代 qty×last + 预估现金差额) / 最小申赎单位份额
```

**Deutsche Börse（事实 S9）：**

```text
iNAV_t = (Cash + Σ p_it × fx_t × q_it × c_it) / N_t
```

| 变体 | 官方默认 | 硬件 | 出处 | 标注 |
|------|----------|------|------|------|
| 价格档 | **last** | `partial_last` 累加器 | S3, S10 | 事实 |
| bid/ask IOPV | 非交易所默认 | 并行累加器 | S1 Claim 11 | 事实 |
| mid | 非官方 IOPV | 需 bid+ask 上游 | — | 待核实 |
| 应计/费用 | 并入预估现金差额 | 日更 global 常数 | S3, S11 | 事实+推断 |
| adjustment | 日更 c_it | Host 入表 | S9 | 事实 |
| 舍入 | **4dp** | 输出级 round | S3, S9 | 事实 |

**并非所有 ETF 都发 IOPV（事实 S3）：** 「并非每只 ETF 都会提供实时 IOPV」— 债券等可能无 IOPV。

### 3.3 partial 定义（硬）

```text
partial[L] = Σ_{i∈L} (qty_i × px_i) + cash_substitute_local[L]
```

| 性质 | 出处 | 标注 |
|------|------|------|
| 可加标量，本 leg 货币 | S9 求和结构 | 推断 |
| FX **不**乘入 partial[L] | S9 `fxt` 与 `pit` 分离 | 事实+推断 |
| 必须替代 → `cash_substitute_local[L]` | S3 公式第一项 | 事实 |
| 合成 **禁止** qty×px lookup | — | 推断（工程切分） |

### 3.4 合成定义（硬）

```text
nav_raw = Σ_L (partial[L] × FX(L→report)) + global_estimated_cash
IOPV = round_4dp(nav_raw / creation_unit_shares)
```

| 操作 | 允许/禁止 | 出处 | 标注 |
|------|-----------|------|------|
| 读 partial[]、FX[]、加乘、÷unit | 允许 | S9 | 事实 |
| symbol lookup、qty×px | **禁止** | — | 推断 |
| global_cash 只加一次 | 允许 | S3 | 事实 |
| stale leg 仍计入、降 quality | 允许 | S10 | 事实+推断 |

---

## 4. 开源参考：文件与接口（非本仓 RTL）

### 4.1 DolphinDB 流式 IOPV 教程（S2）

| 项 | 路径/符号 | 用途 |
|----|-----------|------|
| 文档 | `docs.dolphindb.com/en/Tutorials/streaming_IOPV.html` | IOPV 增量教程 |
| 历史 ffill | `rowSum(ffill(constituentValue))` §3 | stale 语义 |
| 截面引擎 | `createCrossSectionalEngine(..., triggeringPattern='perRow')` §4.2 | 逐笔触发 |
| 无价变过滤 | `createReactiveStateEngine(..., filter=<deltas(Price)!=0>)` §5.1 | skip 不变价 |
| 增量 | `deltas(Price*Position)` + `cumsum(deltaValue)` §5.2–5.3 | Δ 路径 |
| 回放 | `replayDS`, `replay` §4.1 | 测试用，**Out** 行情解析 |

**标注：** 单域单币种；**无** native multi-leg partial — 本报告 leg 切分为 **推断** 扩展。

### 4.2 Exegy 专利（S1，非开源）

| 项 | 位置 | 用途 |
|----|------|------|
| Δ NAV | Claim 6–7 | `contribution + previous` |
| 多 NAV 类型 | Claim 11 | bid/ask/last |
| 双表索引 | Claim 20 | symbol→pointer→basket pairs |
| 表热更 | Claim 21–22 | client 改 weight |
| 披露 gate | Claim 24–28 | threshold vs reference |
| FPGA | Claim 34 | reconfigurable logic |

### 4.3 Xilinx Vitis Quant Finance（S15，非 IOPV 专用）

| 项 | 路径 | 用途 |
|----|------|------|
| 库索引 | `xilinx.github.io/Vitis_Libraries/quantitative_finance/2020.2/` | L2/L3 定点算子参考 |
| IOPV/basket | — | **无** 专用模块 |

**标注：** 64b 定点为 **推断**；**待核实** 具体 scale。

---

## 5. 方案对比（机制四问 — 每格绑出处）

| 方案 | 触发 | partial | 汇合 | tick→partial | 未齐输出 | 热更双缓冲 | FX 跳变 | 出处 | 标注 |
|------|------|---------|------|--------------|----------|------------|---------|------|------|
| **B0** | 逐笔 Δ；出 15s | 累加器/leg | 同钟 synth | `partial+=qty×Δpx` | 输出+degraded | 日更 swap+重播种 | 否；synth only | S1,S2,S3,S9,S10,S11 | 事实+推断 |
| B1 | 逐笔/定时 | 影子向量 | 同钟 | 累加器→拷贝→synth | 输出 | swap 后重拷 | 否 | — | **待核实** |
| C0 CDC | 逐笔/leg | 累加器/域 | CDC FIFO | 域内同 B0 | 输出 | 分域 pause+swap | 否 | — | **待核实** |
| D0 Host | 批/定时 | Host Σ | Host | Host 增量 | 可 withhold | DB 事务 | Host 重算 | S2 教程架构 | 推断 |
| D1 | 权重事件 | 累加器+重播种 | 同钟 | swap 后 seed | 可 gate | shadow+pause | 否 | S1 Claim 21–22 | 推断 |

### 5.1 机制四问默认答（B0）

| 问 | 答 | 出处 | 标注 |
|----|-----|------|------|
| 新 tick→partial | `partial[leg]+=qty×Δpx`；无效态不更新 | S1,S2,S3 | 事实+推断 |
| 未齐是否输出 | **是**；ffill stale | S10,S2 | 事实 |
| 权重热更双缓冲 | 日更 swap（S4）；改表 S1 Claim 21–22；pause 周期 | S1,S4 | 事实+**待核实** |
| FX 跳变整幅重算 | **否** | S9 | 事实+推断 |

草稿：[evidence/mechanism-four-questions-draft.md](evidence/mechanism-four-questions-draft.md)

---

## 6. 机制

### 6.1 权重与表（S1 Claim 20, S4）

| 字段 | 更新 | 出处 | 标注 |
|------|------|------|------|
| qty, substitute_flag | 日更 / swap | S4 | 事实 |
| cash_substitute_local[leg] | 日更 | S3 | 事实 |
| global_estimated_cash | 日更 | S3 | 事实 |
| adjustment_factor | 日更 | S9 `c_it` | 事实 |
| last_px, stale | tick | S2 | 事实+推断 |

**swap 流程（推断）：** Host 写 shadow → swap_req → pause → `partial[L]:=partial_seed[L]` → resume。pause 拍数 **待核实**。

### 6.2 停牌 / 竞价 / 熔断

| 状态 | px | partial | 合成 | 出处 | 标注 |
|------|-----|---------|------|------|------|
| continuous+valid | 更新 | +=Δ | 正常 | S3 | 事实+推断 |
| valid=0 | skip | 不变 | 输出 | S2 ffill | 事实+推断 |
| auction/halt | freeze | 不变 | 输出+stale | S3 last 语义 | **推断** |
| px=0 | **禁止**用于更新 | — | — | — | 推断 |

### 6.3 FX 与替代（S3, S7, S9, S12）

- 必须替代 → 日更写入 `partial[L]` 常数（S3，事实）
- FX → synth 乘 `FX(L→report)`（S7,S9，事实）
- FX 更新 → `fx_version++`，partial 不动，重跑 synth（S9，事实+推断）
- S9 §2.2.3：跨时区方法切换时 iNAV **可能小幅跳变**（事实）→ `quality=FX_METHOD_SWITCH`（推断）
- S12 pricing waterfall → Host `px_override`（推断）；FPGA **不**内置 FV（S14 闭市 FV 讨论，事实背景）

### 6.4 数值

| 阶段 | 格式 | 出处 | 标注 |
|------|------|------|------|
| 累加 | 定点，bit 宽 | S15 | **待核实** |
| IOPV 输出 | round **4dp** | S3, S9 | 事实 |
| bid/ask 路 | 独立累加器 | S1 Claim 11 | 事实 |

### 6.5 quality 字段（推断，边界来自 S11）

```text
quality ∈ { OK, DEGRADED, STALE_LEG, PCF_SWAP, FX_METHOD_SWITCH }
stale_leg_mask, coverage_pct, pcf_version, fx_version
```

S11：外国成分价可能不更新 — 输出须标记，不可假精度（事实）。

---

## 7. 默认 partial→合成 与翻车条件

### 7.1 B0 默认

| 层 | 选择 | 出处 | 标注 |
|----|------|------|------|
| 拓扑 | 反向表 → per-leg 累加 → 同钟 synth | S1 Claim 20; S1,S2 Δ | 事实+推断 |
| 价格 | last 主路 | S3 | 事实 |
| partial | 含 leg 必须替代 cash | S3 | 事实 |
| 停牌 | ffill + stale | S2,S10 | 事实+推断 |
| FX | synth ×FX | S9 | 事实 |
| 未齐 | 输出 + quality | S10,S11 | 事实+推断 |
| 对外 | 15s 或阈值 | S3,S8,S11; S1 Claim 24–28 | 事实 |

### 7.2 翻车换方案

| 条件 | 换方案 | 出处 | 标注 |
|------|--------|------|------|
| 盘中 PCF 热更 >1×/日 | D1 或 D0 Host | S1 Claim 21–22 | **待核实** 阈值 |
| 闭市 leg 需 FV 定价 | Host px_override；或 withhold | S9 §2.2.4; S12; S14 | 事实+推断 |
| 跨卡/多域 leg | C0 CDC | — | **待核实** |
| tick 级审计回放 | B1 影子快照 | — | **待核实** |
| 产品无 IOPV 义务 | 不硬算 IOPV | S3 | 事实 |
| 对外宣称 IOPV=NAV | **禁止** | S11 | 事实 |

---

## 8. 算例（算术示例，非实测）

### 8.1 单 leg tick（S3 公式结构）

unit=1,000,000；qty=1000；10.00→10.06；cash_substitute=30,000；global_cash=20,000

```text
partial += 1000×0.06 = 60
nav_raw = partial + global_cash → IOPV = round_4dp(nav_raw/unit)
```

合成路径 **不** lookup qty（推断）。

### 8.2 HK stale + FX 跳变（S9 FX 分离）

partial[SSE]=3,000,000；partial[HK]=500,000（冻结，S10 stale）；FX 0.9200→0.9250

```text
nav_old = 3,000,000 + 500,000×0.9200 + global
nav_new = 3,000,000 + 500,000×0.9250 + global   // partial 未变
```

整幅重算成分？**否**（推断，S9 结构支持）。

---

## 9. 待核实清单

| 项 | 原因 |
|----|------|
| 同钟 synth vs CDC 分界 | 无公开 FPGA 多 leg 实例 |
| 64b 定点 scale | S15 非 IOPV 专用 |
| session_state→freeze 映射 | 无交易所 FPGA 规范 |
| pause 拍数、B、M 上限 | 无本仓 RTL |
| 盘中 PCF 热更频率 | 官方日更 S4 |
| withhold vs 仍输出 | 产品 gate |

---

## 10. 上游接口（推断，无公开标准）

```text
// 输入：上游 feed handler 已解析（Out：协议解析）
struct MdTick {
  uint32_t symbol_id;
  uint8_t  market_id;      // → leg_id，映射表 待核实
  int64_t  px;
  uint8_t  px_type;        // LAST=0 默认，S3
  uint64_t ts;
  uint8_t  valid;
  uint8_t  session_state;
};

// 输出
struct IopvOut {
  uint32_t basket_id;
  int64_t  iopv;           // 4dp，S3,S9
  uint8_t  quality;        // 推断
  uint8_t  stale_leg_mask;
  uint32_t pcf_version;
  uint32_t fx_version;
};
```

---

## 11. 出处

- [`sources.md`](sources.md) — S1–S16；**S11 为证伪/边界源**
- [`evidence/`](evidence/) — 摘录与四问草稿
- 前序：[`0842`](../fpga-iopv-per-market-cross-synth-20260916-0842/)
