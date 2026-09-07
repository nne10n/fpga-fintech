# 订单簿推送与 DDR 回补方案 v2 — **契约冻结**

日期：2026-09-04  
状态：**FROZEN**（A/B/C + P0 AXI/`top10_msg`/`BASE_BEST16` 已关闭，2026-09-04）  
板卡：Yusur NDPP X1100（深市单卡）

相对 v1 增量：
1. 标的十档**有更新时推送该标的完整新十档**（非整档零散 delta）
2. **定时推送 4096 只**标的十档快照（默认 10ms，`snap_skip_empty=1`）
3. 十档**缺失时自动从 DDR 全量簿回补**（**best16 旁路**，不做活单扫描）

---

## 0. 冻结决议（不可擅自改）

| ID | 决议 |
|---|---|
| **A** | **4096×Top-10 全部常驻片上**，优先 URAM。综合不过再降级（`N_SYM=2048` / px 压 32b）。**默认不做**「目录+活跃 cache」。 |
| **B** | 定时全推默认 **10ms**；CSR 可配；`snap_skip_empty=1`。 |
| **C** | 回补采用 **best16 旁路**（**不做**活单扫描）。 |
| 优先级 | **实时推送 > 回补 > 定时**；回补**不反压**行情；回补返回用 **seq 防旧盖新**。 |

URAM 综合不过 → **第一时间回小组组长**，再走降级路径。

---

## 1. 目标架构

```text
  逐笔 ADD/CXL/TRADE
           │
           ▼
    ┌──────────────┐
    │ cmd_dispatch │
    └───┬──────┬───┘
        │      │ 并行
        ▼      ▼
   ┌────────┐  ┌─────────────────┐
   │ L0     │  │ L1 DDR 全量簿   │
   │ URAM   │  │ Order+Level     │
   │ Top-10 │  │ + best16/side   │
   │ ×4096  │  │ 多 bank AXI-MM  │
   └───┬────┘  └────────┬────────┘
       │                │
       │    refill req  │
       │◄───────────────┤
       │                │
       ▼                ▼
  book_push_engine ──► DMA / 组播
  - rt：单标的完整 Top-10
  - refill：回补后推送
  - timer：4096 @ 10ms
```

---

## 2. 片上 L0：4096×Top-10（冻结）

### 2.1 存储

每标的：`2 侧 × 10 档 × {px:64, qty:32, valid:1}` ≈ 240B  
4096×240B ≈ **960KB** → **优先 URAM**。

另：`order_cache` 建议 4k～16k 槽（热路径加减，不每次读 DDR）。

参数：`localparam int N_SYM = 4096;`（`book_pkg`）

### 2.2 `top10_msg_t`（P0 冻结字段）

固定长度，便于 DMA（小端打包示意）：

```systemverilog
typedef struct packed {
  logic [15:0]  pad;
  logic [7:0]   flags;      // bit0=from_rt,1=from_timer,2=from_refill
  logic [31:0]  seq;
  logic [63:0]  ts_ns;
  logic [15:0]  symbol_id;
  // bid[0]=最优 … bid[9]
  logic [63:0]  bid_px  [10];
  logic [31:0]  bid_qty [10];
  logic [9:0]   bid_vld;    // bit i = bid[i] valid
  logic [63:0]  ask_px  [10];
  logic [31:0]  ask_qty [10];
  logic [9:0]   ask_vld;
} top10_msg_t;  // 实现时压成单 packed 向量，总宽以 rtl/book_pkg.sv 为准
```

**推送规则：** 该标的 Top-10 任一档变化 → 入 `push_q_rt`；同 `symbol_id` 已 pending → **覆盖写最新**。

---

## 3. 定时全量快照（冻结）

- CSR：`period_cycles` 默认对应 **10ms**（按系统时钟折算）
- CSR：`snap_skip_empty=1`（默认开）
- `snap_fsm`：`id = 0..4095` 轮询；空槽跳过
- `push_q_snap` 与 `push_q_rt`：**实时优先**；被抢占的 id 下一轮补
- 带宽粗算：满推 ≈1MB/轮 @10ms → ~100MB/s；跳空后实测标定

---

## 4. 十档缺失 → best16 回补（冻结）

### 4.1 触发

1. CXL/TRADE 后某侧 `top_depth < 10` 且 `l1_may_have_more=1`
2. CSR 强制 `refill_symbol`

### 4.2 best16

DDR 每 `(symbol, side)` 维护有序 **best16** `{px,qty}`（优于哈希档的「取最优 10」路径）。  
ADD/CXL/TRADE 时与 Level 表一并维护；回补 **只读 best16 前 10** 写回 L0 该侧，再发 `top10_msg(from_refill)`。

### 4.3 竞态

回补启动时锁存 `seq_start`；返回时若 L0 该标的 `seq > seq_start` → **丢弃或重发 refill**，禁止旧数据盖新。

### 4.4 队列

`refill_fifo` depth≥64；同 symbol 合并。优先级：**rt > refill > timer**。

---

## 5. AXI / DDR 地址窗（P0 与 AXI 负责人共冻）

| 窗名 | 内容 | 备注 |
|---|---|---|
| `BASE_ORDER` | OrderTable | 沿用 l1-ddr-design |
| `BASE_LEVEL` | LevelTable | 沿用 |
| **`BASE_BEST16`** | 每 symbol×2side×16 槽 | **本方案新增** |

粗算 best16：4096×2×16×12B ≈ **1.5MB** DDR（可接受）。

AXI 需求（待 AXI 负责人回填实测）：
- AXI4-MM master，建议 DATA_W=512，outstanding≥4
- `ddr_clk` ↔ 322M 异步 FIFO（cmd / refill rsp / push 侧）
- 与 LightningDMA 带宽共存：定时 ~100MB/s 峰值 + 回补随机读

仿真：扩展 `axi_ddr_model` 支持 `BASE_BEST16`。

---

## 6. 模块与排期

| 阶段 | 内容 | 责任 |
|---|---|---|
| **P0** 1～2 天 | 冻 `top10_msg` / `BASE_BEST16` / AXI 口表与带宽预算 | 架构 + AXI |
| **P1** | L0→4096、`book_push_engine`、L1 best16+refill | 并行 + 码农 |
| **P2** | 缺档回补、定时全推、seq 竞态、带宽压测 | 验证 |

衔接现有：`book_engine` / `l1_ddr_engine` / `USE_L1_DDR`；新增 `book_push_engine`。

---

## 7. 风险

| ID | 风险 | 动作 |
|---|---|---|
| R1 | 960KB URAM 综合不过 | **立即回组长**，再降 N_SYM/px |
| R2 | 定时带宽打满 DMA | 拉长周期 / 跳空已默认 |
| R3 | 回补竞态 | seq 门禁 |
| R4 | best16 与 Level 漂移 | SNAP 纠偏 + gold |
| R5 | FDK 无 DDR | 回补不可用，产品降级 |

---

## 8. 变更控制

本文件标题含 **FROZEN**。改 A/B/C 或优先级铁律须 **小组组长书面同意**。P0 字段细节由架构+AXI 小改可合入，合入后 bump 小节修订号。
