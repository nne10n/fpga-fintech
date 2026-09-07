# P1 开工点：L0×4096 + book_push_engine + L1 best16/refill

状态：P0 **已关闭**（2026-09-04）  
契约：`book-push-refill-v2.md`、`p0-top10-axi-contract.md`（FROZEN）  
类型：`rtl/book_pkg.sv`（`N_SYM`、`top10_msg_t`、`best16_addr`）

---

## 范围

| 做 | 不做 |
|---|---|
| L0 Top-10 视图扩到 **4096**（URAM） | 改 `event_t` / 解码热路径反压 |
| `book_push_engine`：rt / refill / timer 三级 | 真板 FDK 调参 |
| L1 维护 **best16** + refill 读回 L0 | 活单扫描回补 |
| seq 防旧盖新；满则 drop | 纳秒 KPI |

---

## 建议编码序

1. **P1.0** `book_pkg` 已齐 → `top10_ram`（4096×两侧 Top-10）+ 单标的组装 `top10_msg`
2. **P1.1** `book_push_engine`：`push_q_rt` 覆盖合并、`push_q_snap` 10ms、`snap_skip_empty`
3. **P1.2** L1 `BASE_BEST16` RMW（跟 Level 更新）
4. **P1.3** refill_req/rsp + seq 门禁 + 优先级 rt>refill>timer
5. **P1.4** 接到 `book_engine` / `md_rx_top_x1100`；`make sim-book` / 新 `sim-push` 绿

---

## 铁律

- 回补/L1 **不反压** 322 解码
- 定时默认 10ms，CSR 可配
- URAM 综合不过 → **立即回小组组长**（降 N_SYM=2048 或 px 压 32b）

## 责任（组长协调）

并行 + 码农：RTL；验证：缺档/定时/seq/带宽；架构：契约答疑。


---

## P1.4 接入状态（hooks-first slice）

**已落盘（默认 `USE_BOOK_PUSH=0`，`make sim-book` 绿）：**

- `order_cache`：`m_rt_valid` + `m_rt_row`（全侧 Top-10）；CXL/TRADE dig-hole → `m_dig_hole`
- `book_engine`：导出 `o_rt_*` / `o_refill_req_*`；`USE_BOOK_PUSH=1` 时例化 `book_push_refill_top`
  - DDR CDC：`i_ddr_req_ready=1`，无 rsp（best16 壳未接）
  - DMA：内部永远 `ready=1`（铁律：不反压解码）；`i_push_dma_ready` 仅观察
  - interim `symbol_id = hot_id - 1`（待 code→id 表）

**启用 push 顶：**

```bash
make sim-book              # USE_BOOK_PUSH=0（默认）
make sim-book-push-hook    # USE_BOOK_PUSH=1 + PUSH_N_SYM=64 + BOOK_PUSH_EXTRA
make sim-book-push         # P2 TB on book_push_refill_top
```

**仍待（完整 P1.4）：**

1. refill AXI / best16 rsp 壳接到 `l1_ddr_engine`
2. `md_rx_top_x1100`：`ENABLE_BOOK` + 可选 `USE_BOOK_PUSH`，DMA 接到真实 sink
3. hot Port-A / order_cache 与 `l0_top10_mem` 单一 L0 源（现双写镜像）
4. code→`symbol_id` 映射（替换 hot_id-1）
