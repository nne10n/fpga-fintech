# 一页纸速览 — FPGA 硬件订单簿价格档位

**目录：** `fpga-hw-orderbook-price-level-20260916-1854/` · **仓：** Research_everything

## 默认方案（推断，口径未改）

| 层 | 选择 | 主据 |
|----|------|------|
| 承载 | 分侧 BRAM/URAM 稠密槽 | S1 §3.1.3；S3 `docs/adr/ADR-004-order-book-bram-aos.md` |
| 索引 | `off=⌊(px−base)/T⌋` 或 `Ap=Ald+(p−pld)/pt` | S1 §3.1.3；S2 Eq.1 |
| 字段 | `{agg_qty, order_cnt, valid}`；px 可隐含 | S1 Table 2；S8 `README.md` §Price Level Table |
| BBO | 寄存器 + 增量 tracker | S1 §3.1.3 Top-of-Book Tracking |
| 越界 | 硬 drop + 计数 | S1 §3.1.3；S3 `ADR-005` Pre-conditions |

## 翻车条件 → 换档

| 条件 | 换方案 | 主据 |
|------|--------|------|
| 有效档稀疏、band 内多空档 | F 价链 / C Top-K / G mod m | S7；S9 §3 Figure 6；S2 Fig.3 |
| 窗越界且无 rebase | rebase 或价哈希（S1 stretch） | S1 §3.1.3 末段 |
| tick×价域超片上 | E DRAM 行 + CACHE | S6 摘要 |
| 仅 Top-K 且档常越 K | ↑K 或 D bitmask+hybrid | S3 ADR-012；S4 Poster |
| mod m alias 不可接受 | 禁用 G → A/F | S7 §Bid and ask processors |

## 六维压缩（每格有出处 → 详表见 `evidence/E02`）

| ID | 承载 | 索引 | 字段 | 稀疏 | 穿 best |
|----|------|------|------|------|---------|
| A | M10K 8192×64b | `(sym<<11)\|off` | qty32,cnt16,v1 | 近密 liquid | tracker 扫 | S1 §3.1.3 |
| B | BRAM 全 tick band | Eq.1 | qty+mask | 有界枚举 | reduction/cache | S2 §III–IV |
| C | Reg K + BRAM WO | 排名 k | px,qty | 热⊂K | cache 移位 | S3 ADR-012 |
| D | URAM+bitmask | abs off | qty+bit | 中稀疏 | hybrid 搜 | S4 Poster |
| E | DRAM 行 | px→row | qty+CACHE | 超片上 | 两级 CACHE | S6 摘要 |
| F | dummy 价链 | 链表 | px,qty | 高稀疏 | 链头/Top | S9 §3 |
| G | 圆环 m | mod m | qty,v | 近 touch | rebalance | S7 |
| H | BRAM 256×82 | 128+128 | 显式 px | 浅簿 | FSM 扫 | S8 README |
| **反例** | sorted order array | 排名插入 | per-order ID | — | **非档位聚合** | **S14 `rtl/order_book.sv`** |

## Out（本题不写）

未核实 ns、RTL top、策略报单、会话/ITCH 栈、档内 per-order 状态机。

## 证据入口

- 正文：[`report.md`](report.md)
- 出处：[`sources.md`](sources.md)（S1–S14，≥10 URL）
- 留证：[`evidence/E01–E03`](evidence/)
