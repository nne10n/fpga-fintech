# P0 契约：top10_msg + BASE_BEST16 + AXI 口表

状态：**FROZEN**（2026-09-04，小组组长关 P0；含 §1–§3）  
父文档：`book-push-refill-v2.md`（A/B/C 已冻）

---

## 1. `top10_msg_t`（**FROZEN**，已写入 `rtl/book_pkg.sv`）

目标：单 beat / 单 DMA desc 可搬；字段小端。

| 字段 | 宽 | 说明 |
|---|---|---|
| `symbol_id` | 16 | 0..4095 |
| `ts_ns` | 64 | 推送时刻 |
| `seq` | 32 | 该标的簿更新序号（防旧回补） |
| `flags` | 8 | `[0]=rt [1]=timer [2]=refill` |
| `bid_vld` / `ask_vld` | 10+10 | 档有效 |
| `bid_px[10]` / `ask_px[10]` | 64×10 | 10^-4 元，与 event_t 一致 |
| `bid_qty[10]` / `ask_qty[10]` | 32×10 | |

落地宽：**2080 bit = 260B**（`TOP10_MSG_W`/`TOP10_MSG_BYTES`）；level0=最优在各向量 **LSB**。DMA ring 若要求 256B 对齐，desc 长度用 260、缓冲按 320B(5×64B) 对齐即可。

禁止改 `event_t`。`N_HOT` 暂保留；P1 视图 RAM 迁 `N_SYM=4096`。

---

## 2. `BASE_BEST16` 布局

每 symbol 两行（或连续 2×stride）：

```
addr = BASE_BEST16 + symbol_id * STRIDE_SYM
STRIDE_SYM = 2 * 16 * 16 = 512B   // side×16槽×16B对齐槽
槽：{px:64, qty:32, vld:1, pad} → 16B
side=0 bid（px 降序）, side=1 ask（px 升序）
槽0 = 最优
```

读写：回补读 side 的前 10 槽；L1 更新时维护整 16。

与现有：
- `BASE_ORDER` / `BASE_LEVEL` 不变（见 `l1-ddr-design.md`）
- CSR 增加 `csr_base_best16`
- 仿真默认窗（与 `l1_ddr_engine` 参数一致风格）：
  - `BASE_ORDER = 0`
  - `BASE_LEVEL = N_ORDER_L1 * 64`
  - `BASE_BEST16 = BASE_LEVEL + N_LEVEL_L1 * 64`（CSR 可覆盖）
  - 全窗：`4096 * 512B = 2MB`（文档粗算 1.5MB 有效载荷；对齐后按 2MB 预留）

---

## 3. AXI-MM 口表（**已冻结**）

依据：现有 `rtl/l1_ddr_engine.sv` + `rtl/sim/axi_ddr_model.sv` + `docs/l1-ddr-design.md`。  
**FDK 实测前按本表做仿真/RTL；上板前用 FDK 核对，不符则只改参数不改契约语义。**

| 项 | 假设（待确认） | 实测/FDK（本表冻结） |
|---|---|---|
| 协议 | AXI4-MM master | **冻：User Logic 单口 AXI4-MM master**（AW/W/B/AR/R）；仿真接 `axi_ddr_model`。FDK 若无 DDR 口 → R5 降级，回补不可用。 |
| DATA_W | 512 | **冻：512**（64B/beat）。与现 `AXI_DATA_W=512`、Order/Level 64B 槽一致。FDK 若为 256：槽仍 64B，一拍可装 4 槽，改 `AXI_DATA_W` 参数即可。 |
| ADDR_W | 33? | **冻：33**（与现 RTL 参数一致）。CSR 基址按字节地址；访问必须 **64B 对齐**（`awsize/arsize=$clog2(64)`，`len` 按突发）。 |
| outstanding | ≥4 | **冻：`MAX_OUTSTAND=4`**（与现 L1 一致）。建议 FDK 允许时抬到 **8**，给 best16 回补留槽，避免与 4 bank RMW 互堵。ID_W=4。 |
| 时钟 | `ddr_clk` vs `sys_clk` 322M | **冻：双域。** 热路径 `sys_clk`=**322.265625 MHz**；L1/AXI 跑 **`ddr_clk`**（频率跟 FDK；仿真可 `ASYNC=0` 单钟）。CDC 见下。 |
| 与 DMA 关系 | 共享 / 独立 | **冻：逻辑分流。** ① 定时/实时 `top10_msg`：**L0 URAM → `book_push_engine` → LightningDMA**，**不走** User Logic DDR AXI。② L1 Order/Level/best16 RMW+回补读：**独占** User Logic AXI-MM→DDR。③ FDK 若 DMA 描述符环/暂存也落同一 DDR 控制器 → 按「共享控制器」预算（见带宽）；若仅 PCIe 主机口 → 视为 **独立**，DDR AXI 只服务 L1+refill。 |
| 定时峰值 | ~100MB/s @10ms 满推 | **可接受（DMA/PCIe 侧）。** 4096×256B≈1MB/轮 @10ms → ~100MB/s；`snap_skip_empty=1` 降实载。LightningDMA 公开 ~230ns 单向，PCIe 吃 100MB/s 无压力。**不计入 DDR AXI 带宽**（除非 FDK 证实共享控制器写暂存）。共享时预留同量级写带宽，必要时拉长 `period`。 |
| 回补读 | 随机 256B/次 | **可接受（DDR AXI 侧，低优先）。** 单侧 best16=256B=**4 beat** @512b；整 symbol=512B=8 beat。QoS：**L1 bank RMW > refill AR**（arbiter 固定优先）；refill 不得占满 outstanding（建议 ≤1～2 槽）。不反压 322 热路径；rsp 经 async FIFO 回 L0/push。开盘突发以 FIFO+丢弃/合并 symbol 吸收。 |

### CDC（冻结）

| 路径 | 方向 | 要求 |
|---|---|---|
| `l1_cmd` / refill_req | 322 → `ddr_clk` | 异步 FIFO；满则 **丢 cmd + drop_cnt**（永不堵解码） |
| refill rsp / repair | `ddr_clk` → 322 | 异步 FIFO；L0 用 **seq** 防旧盖新 |
| push（rt/timer） | 仅 322 | 读 L0，**不**过 DDR CDC |
| 复位 | 每域 | `sys_rst_n` / `ddr_rst_n` 异步断言、同步释放 |

禁止：热路径 `always` 里等 AXI rsp；禁止把 `m_axi_*ready` 传到 `udp_strip`。

### 带宽一句话结论

**10ms 满推 + best16 回补：可行。**  
满推走 DMA≈100MB/s（可接受）；回补是低频随机读，与 L1 共 AXI 时用 outstanding 限额 + RMW 优先即可。上板前唯一硬门禁：**FDK 确认 User Logic 确有 AXI-MM↔DDR**；若与 LightningDMA 共控制器，再实测开盘水位，不够则拉长定时周期。

### 仿真扩展

- 继续用 `rtl/sim/axi_ddr_model.sv`（ADDR_W=33, DATA_W=512, MAX_PEND≥16）
- 扩展地址译码覆盖 `BASE_BEST16` 窗（稀疏 mem 已按字节地址，只需 DUT 发对地址）
- `l1_ddr_engine` 增加 `BASE_BEST16` 参数 + best16 RMW/refill 读路径（实现阶段，非本表）

---

## 4. P0 验收

- [x] `top10_msg_t` 写入 `book_pkg.sv` 且文档一致
- [x] `BASE_BEST16` 公式写入 `l1-ddr-design.md` 修订段
- [x] AXI 口表本表填满（2026-09-04 AXI 负责人）
- [x] 带宽结论：10ms 全推 + 回补 **可行**（见 §3）
