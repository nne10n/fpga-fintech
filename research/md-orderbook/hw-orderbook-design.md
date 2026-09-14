# 硬件行情订单簿 · 设计总稿（草案）

日期：2026-09-11  
状态：**草案** — G0 成文（H1–H5）；待验收/优先级裁完 + 切片齐后 FROZEN
G0：`docs/boundary/硬件行情订单簿-边界单.md` @ melon5253/fpga-md-orderbook commit `e9a2232b8c865c9611602a2c6bedd0a88eef317a`  
产物仓：https://cursor.com/codebase/melon5253/fpga-md-orderbook  
章程：`team-design-charter.md`（含稀有异常铁律）

---

## 0. Scope

| 项 | 内容 |
|---|---|
| 目标 | 硬件行情订单簿 |
| N_SYM | 最大 **4096** |
| L1 | **DDR** 全量档位记录 |
| L0 | **片上** 每标的买卖各 **10** 档最优（bid/ask L1–L10） |
| 不做 | 策略、报单、完整交易所会话栈、超出簿管理 |

**勿写死（待业务/调研裁定）：** 行情协议与更新原语、延迟/吞吐数值目标、DDR 带宽与地址映射细节。

**稀有异常默认：** 丢 + sticky 可观测 + `sys_rst_n` 空管；反对堆优雅恢复。

---

## 1. D4 假设（口头）

| ID | 假设 |
|---|---|
| B1 | 热路径更新 L0；全量在 DDR；缺档回补不得反压解码（对照既有 book-push 铁律，是否采用待切片确认） |
| B2 | 推送/查询产品行为（整十档 vs delta、定时全推等）**本轮未冻**，D2 先留钩子不写死 |
| B3 | 对照文档可参考 md-card `book-push-refill-v2` / `l1-ddr-design`，**以新边界单为准** |
| B4 | 产物仓正式：**`melon5253/fpga-md-orderbook`**（https://cursor.com/codebase/melon5253/fpga-md-orderbook；初始 0466033） |
| H1 | 簿内核 **协议无关**：原语 add/mod/cancel/trade@价位；ITCH/固定 tick 适配后置；核心禁写死协议 |
| H2 | DDR 全量 = **L2 价格聚合档（Σqty）**，非 L3 逐单 |
| H3 | 十档 = 买卖各侧各 **10 个聚合价位**；DDR 权威，片上 Top-10 为投影（档变修补） |
| H4 | **固定 4096 槽**（symbol→slot）；超限拒收且可观测 |
| H5 | 本步 **不做缺口完整恢复**；可标脏；CPU snapshot 另开（对齐稀有异常：脏+复位/CPU，不堆恢复态） |

---

## 2. D1 骨架

```text
适配层（ITCH/… 后置）──► 协议无关原语
        add/mod/cancel/trade @ price
                 │
                 ▼
          cmd_dispatch
           │         │
           ▼         ▼
    L0 片上投影     L1 DDR L2 聚合档（权威）
    Top-10×4096      Σqty / price level
           ▲         │
           └─ 档变修补 / 缺档旁路（不堵热路径）
```

超限（>4096 槽）：拒收 + sticky/计数。缺口：标脏，完整恢复另开（H5）。
细节待数据面/契约切片；**延迟数勿写死**。

---

## 3. 出门清单

- [x] 成文边界单（e9a2232；H1–H5）
- [ ] 验收/优先级（点子王草案 + 业务裁）— **FROZEN 前门禁**  
- [x] 产物仓路径（`melon5253/fpga-md-orderbook`）  
- [ ] D2 契约切片  
- [ ] 数据面切片  
- [ ] 复用/缺页  
- [ ] D3 验收点  
- [ ] 家规/反发散切片  

齐后宣布 G1 FROZEN。
