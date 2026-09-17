# 出处清单与抓取备注

**Asia/Shanghai 2026-09-16 08:48（修订）** · 主题：Bitmap 维护 DDR 有效条目 × AXI 吞吐 · **双路径 α/β**

标注：**事实** = 可核对规范/文档；**推断** = 机制归纳；**待核实** = 缺参或未读原文细节。

---

| # | 来源 | 引用点 | 标注 | 备注 |
|---|------|--------|------|------|
| 1 | [AMBA AXI4 Protocol Specification (ARM IHI 0022E)](https://developer.arm.com/documentation/ihi0022/latest/) | ARLEN/ARSIZE、INCR burst、outstanding、ID ordering、WSTRB narrow write | **事实** |  burst 不跨 4KB；同 ID 顺序返回 |
| 2 | [AMD PG058 — AXI Reference Guide](https://docs.amd.com/r/en-US/pg058-axi-ref) | FPGA AXI 互联、FIFO 深度与 outstanding | **事实** | 具体 IP 参数以 Vivado 配置为准 |
| 3 | [UG473 — 7 Series Memory Resources](https://docs.amd.com/r/en-US/ug473_7Series_CLB) | Block RAM 容量 36Kb、双口 | **事实** | 4096 bit ≪ 单片 BRAM |
| 4 | [UG573 — UltraScale Memory Resources](https://docs.amd.com/r/en-US/ug573-ultrascale-clb) | URAM 288Kb block | **事实** | 大 N bitmap 可用 URAM |
| 5 | [IIT TTO 2024 PDF — URAM orderBook + valid-bitmask](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) | 独立 valid 位阵、hybrid binary-linear 搜 next valid | **事实** | 片上 bitmap 语义；未展开 AXI |
| 6 | [Linux `lib/find_bit.c` — find_next_bit](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/lib/find_bit.c) | word-at-a-time、mask 低位、跳零 word | **事实** | 软件对照，非 FPGA 实现 |
| 7 | [本仓库 fpga-hw-orderbook-price-level-20260916-0838/report.md](../fpga-hw-orderbook-price-level-20260916-0838/report.md) | 类 D valid-bitmask、4096 槽、BBO 扫描 | **事实** | 档位 valid 语义 |
| 8 | [Columbia Market Data Parser PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) | BRAM 稠密槽、valid 字段 | **事实** | 片上为主，非 DDR bitmap |
| 9 | [MDPI Electronics 12(3) 520 — FPGA order book](https://www.mdpi.com/2079-9292/12/3/520) | 片上存储、订单簿结构 | **事实** | 未强调 AXI bitmap |
| 10 | [AMD MIG 7 Series / UltraScale+ DDR Controller PG](https://docs.amd.com/) | AXI 到 DRAM、bank/row | **待核实** | bank 冲突为调度直觉，未引具体 table |
| 11 | [Xilinx WP469 — AXI4 Burst Types](https://docs.amd.com/) | INCR 连续地址效率 | **事实** | 文档编号以 AMD 站点为准 |
| 12 | [FPL17 — FPGA Limit Order Book (Imperial)](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) | 涨跌停 band 内 mask 表 | **事实** | mask 与 qty 分离，片上 |
| 13 | [HLS/RTL priority encoder surveys](https://scholar.google.com/) | popcount、leading-zero 硬件 | **推断** | 未绑定单一论文；延迟为典型 LUT 级 |
| 14 | [ARM AMBA AXI4-Lite IHI 0022 subset](https://developer.arm.com/documentation/ihi0022/latest/) | 无 burst 场景 | **事实** | 本主题默认 **AXI4-Full**；Lite 仅配寄存器 |

---

## 抓取状态

- 规范类（#1–#4, #11, #14）：以 ARM/AMD 公开文档为准，**未在本次环境中逐页下载 PDF**。
- 论文/项目（#5, #8, #9, #12）：链接可访问性 **待用户环境核实**。
- 本仓库交叉引用（#7）：**已存在**，可直接打开。

---

## 未编造声明

本调研 **未给出** 未实测的 DDR GB/s、AXI 延迟 ns、或具体 MIG efficiency 百分比；凡涉及绝对性能处均标 **待核实** 或改用 **相对 AR 次数 / 空读比例** 表述。
