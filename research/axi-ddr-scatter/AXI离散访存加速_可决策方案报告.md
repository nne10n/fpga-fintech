# AXI4 主机访问 DDR 离散地址空间：开源加速技术可决策方案报告

- 生成时间：2026-09-13（CST）
- 目标平台：UltraScale（假设为 Xilinx/AMD 7 系列后 FPGA）
- 证据副本：本报告的一手核验基于工作区 `_verify/` 下的 git clone 副本（litedram / verilog-axi / axiZero / DRAMSys / iob-cache / fpl19-DynaBurst / RISCV_IOMMU），克隆时间 2026-09-13；核验时未记录各仓 commit hash 的，已在下文标注「克隆日期」。
- 标记约定：**【事实】**=有链接或源码行号可查；**【推断】**=本报告的推理，写了理由；**【待核实】**=写了核验路径。

---

## 1. 结论摘要（≤10 行）

1. **不要指望「AXI 前端把离散地址变连续」**：在 16B 真随机 + 页间跳跃下，没有任何开源 RTL 能在线性地址空间上无中生有地造出 locality；能赚的只有「把同一 DRAM row/同一 burst 上浪费掉的数据变成有用数据」。
2. **推荐技术族：miss-optimized 非阻塞缓存 + 变长 burst 拼装 + row-aware 重排（读路径）**，首选开源锚点 **EPFL-LAP/fpl19-DynaBurst**（MIT，Chisel，有 AXI4 接口与 ZC706 上板流程）。
3. 一句话理由：它是唯一在**开源代码里**同时具备「按 cache line 合并多次离散请求 → 只向 DDR 请求一次」+「`SameRowReadSelector` 把同 row 的多个离散地址合并成一次传输」的完整实现，正对「减少无效 burst」与「隐藏 row 冲突」两个痛点。
4. **关键前提（缺一即大幅贬值）**：该族收益来自「前端看得到大量在途请求」。论文明确写的是「thousands of in-flight misses」「latency-insensitive applications」；而你给的约束是 **outstanding 深度 8、ID 数量 4**——差两个数量级。**这是本次决策的最大风险**。
5. **第二前提：尾延迟口径与「延迟不敏感」天生冲突**。RCR 路线的加速比是在**延迟不敏感**前提下取得的；若你真正的验收是 p99 尾延迟，必须先定义 p99 的测量点与负载，否则本报告无法把「加速」和「不恶化尾延迟」同时承诺。
6. **事实性硬上限**：DDR3/DDR4 以 8 beat × 64bit 为最小访问粒度（512 bit / 64B）；窄于该粒度的访问，剩余数据被丢弃（TRETS 2022 原文），同文指出 ZC706 PS 侧「single requests which waste 75% of the burst content」。因此 16B 随机读在「无同 row 复用」时，DDR 侧本来就有 3/4 传输量是废的——所有方案的收益空间都来自这里有 75% 可回收。**【事实】**
7. **备选**：纯读且不接受改架构时，只在 DDR 控制器层做「bank 分散 + 队列深度」调参（LiteDRAM 的 `bank_byte_alignment`、`cmd_buffer_depth`），属于低成本、低收益、零新 IP 的路线。
8. **写路径开源缺位**：没有任何 AXI 级写合并/聚合 RTL 可复用（本次核验的 7 个仓全部 grep 无有效命中）；写侧建议先不动，或用闭源 Xilinx DataMover 做对照（不做开源推荐）。
9. **淘汰**：descriptor 级 SG-DMA（含 verilog-axi，已自述弃用且 `ENABLE_SG` 未实现）、IOMMU/地址翻译（对真随机无收益，且候选仓 star=0、无上板证据）、预测式 prefetch（真随机下纯浪费带宽）。
10. **最长 48 小时可证伪的问题**：把 outstanding 从 8 抬到 ≥64 并接上 DynaBurst，测同一随机 trace 的 DDR 侧有效带宽与 p99；若抬不动 outstanding，则本推荐直接降级为「暂不推荐」。

---

## 2. 决策问题与约束复述（含假设清单）

### 2.1 决策问题重述

在 UltraScale 上，AXI4 主机访问 DDR 中**非连续、离散、scatter 式**地址（粒度 16B 随机、页间跳跃）时，如何用**开源/可复用**技术，提高有效带宽、降低尾延迟、减少无效 burst 与总线气泡。

### 2.2 可检验成功标准（本报告自行补齐，需你确认）

| 指标 | 定义（建议口径） | 怎么测 | 验收建议 |
|---|---|---|---|
| 有效带宽 | 主机侧「有用的 16B × 完成笔数 / 时间」 | 上板 ILA 或 AXI 从端计数器；仿真用 testbench 计数 | ≥ 同构型单请求基线（无聚合） |
| 尾延迟 p99 | 从 AR 握手到对应 R 最后一拍（含乱序按 ID 回填后的等待） | 时间戳 FIFO 打点 | 不高于基线 + 约定阈值 |
| 无效 burst | DDR 侧传输字节数 / 主机有用字节数（overfetch 比） | 控制器 `with_bandwidth` 或自建计数器 | 向 1.0 收敛 |
| 总线气泡 | AR/R/W 通道 valid=0 的周期占比 | 仿真/ILA 计数器 | 下降 |

> **停手条件判定**：你把吞吐/延迟预算写成「不关心…」，这句在语义上无法作为验收标准。本报告**不触发停手**，因为 AXI 位宽、离散粒度、DDR 位宽/频率/通道数均已给定，且我按第 2.2 节补齐了可检验代理指标。但第 8 节的 Q1/Q5 必须由你回答，否则「加速」无法判定成败。

### 2.3 假设清单（未经你确认的都用【假设】标出）

| 编号 | 假设 | 影响 |
|---|---|---|
| A1 | 【假设】「不关心有效带宽目标/尾延迟」= 没有硬性数字目标，但仍要方案给出机制与适用条件 | 决定本报告只给机制与相对证据，不给绝对值承诺 |
| A2 | 【假设】DDR 控制器允许替换或旁路（你只排除了改 PHY） | 若必须沿用现有 MIG，LiteDRAM 路线不成立，只剩互连/前端方案 |
| A3 | 【假设】主机的 16B 访问无法改成 ≥64B（工作负载不可改） | 若可改，最省力的方案是把访问粒度提到 64B 对齐，直接消掉 75% 浪费 |
| A4 | 【假设】outstanding 深度 8、ID 数量 4 是**主机互连的硬限**，不可上调 | 这是 DynaBurst/RCR 路线的生死线 |
| A5 | 【假设】无 Linux、无 IOMMU，AXI 主机为裸硬件逻辑 | 排除所有依赖驱动/页表的方案 |
| A6 | 【假设】读写混合，但读为主（未给读写比） | 写路径无开源方案，见第 4 节 |
| A7 | 【假设】512b DDR 位宽 + 128b AXI ⇒ 需要位宽上转换，且这是 DSS 侧常规配置 | 影响资源与 CDC 评估 |

---

## 3. 对比表（维度先冻结，行=短名单）

### 3.0 冻结的 8 维（全程未增删）

1. 对离散访问的加速机制（聚合/重排/翻译/缓存/预取/调度）
2. 有效带宽提升条件（在什么离散粒度下才有效）
3. 延迟与 outstanding/乱序代价
4. AXI 契约契合（burst、ID、resp、窄传输、4K 边界）
5. 与 DDR 控制器的耦合度（通用 AXI 口 vs 绑死某 MIG）
6. FPGA 资源与时序风险（量级即可）
7. 开源成熟度（文档、仿真、上板证据、许可）
8. 集成成本与锁定（改口表 / 改时钟域 / 软硬件协同）

### 3.1 长名单 → 短名单（淘汰必须写理由）

| 技术族 | 仓/来源 | 处置 | 淘汰/入选理由（一句） |
|---|---|---|---|
| Descriptor 级 SG-DMA | alexforencich/verilog-axi；AMD AXI DMA SG | 淘汰 | 描述符级只摊薄控制开销，不改变 16B 随机地址的 DRAM burst 浪费；且该仓 `README.md:11` 自述弃用、`ENABLE_SG` 正文 `$error` 未实现 |
| 请求聚合 / write combining | 全仓搜索：axiZero、verilog-axi、litedram 均无 | 淘汰（无实现） | 8 维中「机制」这一列无任何开源 AXI 级实现；litedram 唯一的 merge 在 Wishbone 宽度转换（`litedram/frontend/wishbone.py`），与 AXI 无关 |
| 地址翻译 / IOMMU-lite | BrendanJamesLynskey/RISCV_IOMMU | 淘汰 | 真随机地址经翻译仍是随机；候选仓 star=0、仅仿真、对 row conflict 零作用 |
| Outstanding / 乱序返回重排 | litedram（无）；DynaBurst `ReorderBuffer.scala`（有） | 部分入选 | 读返回按 ID 重排必须有人做；litedram 显式声明 `No reordering.` |
| 近端 cache / 行友好的地址重排 | **EPFL-LAP/fpl19-DynaBurst**、m-asiatici/MSHR-rich、IObundle/iob-cache | 入选（DynaBurst/MOMS） | 直击「同一 row/burst 上的废数据变有用」；iob-cache 许可强互惠且无 row 分组 |
| Prefetch | 无候选仓 | 淘汰 | 对真随机无空间局部性可预取，只会提前占满 outstanding 并浪费 burst |
| 互连 QoS / 多主仲裁 | lcapossio/axiZero、litedram Crossbar | 入选（低成本备选） | litedram 已是 per-bank round-robin；axiZero 提供 WRR+QoS+aging 但成熟度弱 |
| 开源存储栈 | enjoy-digital/litedram + litex | 入选（控制器/集成底座） | 唯一被本次核验证实的开源 AXI→DDR 全栈，且明确不支持 4K 拆分/重排 |
| 学术/竞赛仓（近存、图、哈希） | ICFPT19 RCR（Csordas 等） | 入选（机制参考，无代码） | 机制与结论最贴题（+81% vs 基线），但仓库不存在 ⇒ 弱证据/仅论文 |

### 3.2 短名单对比表

单元格内 `[F]`=事实（有行号/链接），`[I]`=推断，`[?]`=未知；「未知」单元格在 3.3 给出补齐方法。

| # | 方案 / 仓库 | ①加速机制 | ②有效带宽提升条件 | ③延迟与 outstanding 代价 | ④AXI 契约契合 | ⑤与 DDR 控制器耦合 | ⑥FPGA 资源与时序风险 | ⑦开源成熟度 | ⑧集成成本与锁定 |
|---|---|---|---|---|---|---|---|---|---|
| S1 | **DynaBurst** `EPFL-LAP/fpl19-DynaBurst`（MIT, Chisel） | MSHR 哈希表 + 变长 burst 拼装 + `SameRowReadSelector` 同 row 合并 `[F]` | 离散但**存在可分组区域**；须 ≥ 数十~数百在途请求 `[F][I]` | 缓存是「以面积换延迟容忍」；深度不足则收益归零 `[I]` | 从端 `AXI4FullReadOnly`（ID 位宽参数化，默认 memIdWidth=5）；**无写数据路径** `[F]` | 通用 AXI 从端，不绑 MIG `[F]` | 未核实 LUT/BRAM 绝对值；论文级报告 BRAM 2–15%、Slices 10–15% 相对单请求版 `[F]` | star=5，最后 push 2020-12-03；有 ZC706 + Vivado 2017.4 流程与论文 `[F]` | 需 Chisel/sbt 工具链 + IP-XACT 打包；Vivado 2018.3 默认互连 outstanding 上限会「strongly limit performance」`[F]` |
| S2 | **MSHR-rich (MOMS)** `m-asiatici/MSHR-rich`、`EPFL-LAP/fpga19-MOMS`（MIT, VHDL/Chisel） | 非阻塞缓存合并同一 cache line 的多次 miss + 多 bank `[F]` | 有跨请求行内复用；行间随机则只剩 line 级复用 `[I]` | 需成千在途 miss 才体现优势 `[F]` | AXI 读为主；写路径需另配 `[?]` | 通用 AXI `[F]` | 以 BRAM 换 MSHR（论文强调 24× 面积收益）`[F]` | star=16/22，最后 push 2020-12-03，有论文与 ZC706 流程 `[F]` | 同 S1（Chisel/打包）；本质是 cache，需重塑访存语义 |
| S3 | **LiteDRAM + LiteX** `enjoy-digital/litedram`（BSD-2-Clause） | 无聚合；`per-bank RoundRobin` + 每 bank 命令队列深度 8 + 多 bank 行并行 + `bank_byte_alignment` 打散 `[F]` | 仅当随机地址被铺到不同 bank/row 时才缓解激活-预充电 `[F][I]` | `cmd_buffer_depth` 默认 8，与你的 outstanding=8 无耦合关系，两者独立 `[F]` | AXI 前端 `No reordering.`、不做 4K 边界拆分、窄写靠 WSTRB `[F]` | 自带控制器（可替换 MIG），也可只取互连 `[F]` | Python 生成 RTL（Migen），资源取决于配置；未核实 `[?]` | 545 star、2026-09-10 仍活跃、bench/ 覆盖 kcu105/xcu1525 等、CI + `test/test_axi.py` `[F]` | 低（若本就用 LiteX）；锁定为 LiteX 生态 |
| S4 | **axiZero** `lcapossio/axiZero`（MIT, SpinalHDL） | 仲裁/路由：WRR + 固定优先级 + QoS + aging；位宽 up/downsizer `[F]` | **不直接提速**，只在多主竞争时改善离散流的公平性/气泡 `[I]` | 逐请求仲裁粒度；未核实是否按 burst 保持 `[?]` | 明确支持 AXI4 full（ID/burst/outstanding）、AXI3→AXI4 WID reorder；**未宣称也未实现 4K 拆分** `[F]` | 纯互连，通用 AXI `[F]` | 未核实；SpinalHDL 生成 Verilog `[?]` | star=5，LAST push 2026-09-08；19 个 SpinalSim spec + cocotb、CI、Arty A7-100T 工程 `[F]` | 中：需 SpinalHDL/YAML 生成流程；生态新、社区验证少 |
| S5 | **iob-cache** `IObundle/iob-cache`（CERN-OHL-S-2.0, Verilog） | 可配置 L2 cache，write-back/allocate 可配置，吸收同 line 重复写/读 `[F]` | 仅当存在**行内/行间复用**；真随机下命中率≈0 `[I]` | cache 填充延迟；未核实 MSHR 数量/非阻塞程度 `[?]` | Native IOb 或 AXI4 后端可选 `[F]` | 通用 AXI 后端 `[F]` | 未核实 `[?]` | star=197，2026-06-10 活跃；有论文（Algorithms 2021）`[F]`；许可为**强互惠** | 中高：Py2hwsw/Nix 生成流程；许可对闭源产品不友好 |
| S6 | **RCR（ICFPT19）** 论文，无仓库 | 用 miss 系统里堆积的成千上万未来请求做**大规模单请求重排**，把同一 bank 的 row 冲突压下去，且不产生 burst 废数据 `[F]` | 需要成千在途请求 + 延迟不敏感 `[F]` | 重排窗口越大收益越大，代价是在途状态；论文自述相对基线最高 +81% `[F]` | 在原 miss 系统 AXI 输出后加 per-bank RCR，不要求改 DDR 控制器 `[F]` | 通用（论文用 ZC706）`[F]` | 未核实 `[?]` | **无开源代码**（本次未找到任何 EPFL-LAP RCR 仓；ICFPT19 非开源）⇒ 弱证据，仅作机制/选型参考 | 最高（需自研） |

### 3.3 空格补齐方法（每个「未知」都有动作）

| 未知项 | 怎么补 | 预计耗时 |
|---|---|---|
| S1 真实 LUT/BRAM/时序 | clone `fpl19-DynaBurst`，用 `MSHR_configurator.sh` 生成与你 DDR 位宽一致的配置，`sbt "test:runMain fpgamshr.main.FPGAMSHRVerilog ..."` 后跑 Vivado 综合 + `report_utilization`/`report_timing` | 1–2 天 |
| S1 写路径是否存在 | 读 `src/main/scala/extmemarbiter/ExternalMemoryArbiter.scala`（`AXI4FullReadOnly`）与 `main/FPGAMSHR.scala` 端口定义，确认无写数据通量 | 0.5 小时（本报告已初判：仅 profiling 用 AXI4Lite 写） |
| S1 是否真正处理离散（不是连续 DMA） | 读 `src/main/scala/extmemarbiter/ExternalMemoryArbiter.scala:238+` 的 `SameRowReadSelector`（按 `getRow(addr)` 分组）与 `reqhandler/cuckoo/*` 的 MSHR 分配 | 0.5 天 |
| S2 写路径/ID 语义 | clone `m-asiatici/MSHR-rich`，看 AXI 端口与 `reqIdWidth`/`memIdWidth` 定义 | 0.5 天 |
| S3 4K 边界到底谁拆 | 在 LiteX `litex/soc/interconnect/axi/axi_full.py` 全文检索 `4K/0x1000/4096`（本次初查未见边界拆分逻辑） | 0.5 天（本报告已初查：未见） |
| S4 QoS 是否按 burst 保持 grant | 读 `hw/spinal/axizero/crossbar/Axi4Crossbar.scala:89-138` 的 QoS/aging 状态机 | 0.5 天 |
| S5 是否非阻塞 / MSHR 深度 | 读 `hardware/modules/iob_cache_back_end_axi/hardware/src/*.v` 的 outstanding 处理 | 0.5 天 |
| S6 是否能复现 +81% | 论文无代码 ⇒ 只能自研原型；或改用 S1 的 `ReorderingExternalMemoryArbiter` 近似（它是 S6 的前身思路） | 2–4 周 |

---

## 4. 方案要点（每个短名单）

### S1 DynaBurst（首选锚点）

- **机制一句话**：把多笔落在同一 cache line / 同一「分组区域」的离散请求合并成一次变长 burst 发给 DDR，并在发给内存前用一个按 row 分组的队列把同 row 的离散地址排到一起，从而「用一次 DRAM 传输服务多笔 16B 请求」并减少 row 冲突。
- **仓库**：`https://github.com/EPFL-LAP/fpl19-DynaBurst`；许可：**MIT**（`LICENSE` 正文与源码 `SPDX` 头一致，本次已读）。
- **关键路径**：
  - `src/main/scala/extmemarbiter/ExternalMemoryArbiter.scala`（`ReorderingExternalMemoryArbiter`、**`SameRowReadSelector`**，其中 `def getRow(addr) = addr(addrWidth-1, colWidth)` 即行判定依据；`numBanks=8`、`queueDepth=8`、`maxInFlightRequests=128`）
  - `src/main/scala/main/FPGAMSHR.scala`（顶层、MSHR 配置、`AXI4FullReadOnly` 端口、`burstLengthWidth`、`numMemoryPorts`）
  - `src/main/scala/util/ReorderBuffer.scala`（按 ID 回读重排）
  - `src/main/scala/reqhandler/cuckoo/**`（MSHR/子项哈希表）
  - `README.md`（构建流程、ZC706、Vivado 2017.4 限制说明）
- **适配点（何种离散模式才赚）**：离散但**成区域出现**（例如图/稀疏矩阵的行窗口内），且 outstanding 足够大（论文口径「thousands」）；同一 cache line 被多次访问时收益最大。16B 粒度本身不阻碍收益，阻碍收益的是「完全无分组可能性」。
- **硬伤**：
  - **AXI 从端仅读**：`ExternalMemoryArbiterBase` 的 out 端口类型为 `AXI4FullReadOnly`；**写路径不存在**。
  - **成也 outstanding，败也 outstanding**：`maxInFlightRequests` 默认 128；你的 8 深度会让重排窗口退化到几乎无效（【推断】，理由：`SameRowReadSelector` 的收益正比于队列中可比较的候选数）。
  - 工具链旧：README 明示 Vivado 2017.4 验证；2018.3 起默认 AXI 互连限制 outstanding，「strongly limit the system performance」。
  - **4K 边界**：源码未见 4K 专项拆分逻辑；若上游给跨越 4K 的窄传输，需自证（【待核实】）。
- **证据级别**：仓库、许可、机制 = **事实**（源码行号）；「对 16B 真随机能提升」= **推断**；「提升幅度」= **论文级事实**（见 S6/来源）。

### S2 MSHR-rich / MOMS（DynaBurst 的前身，可读性更好）

- **机制一句话**：非阻塞缓存的 MSHR 用 cuckoo 哈希表扩到「成千上万在途 miss」，同一 cache line 的多个 miss 只向内存发一次，从而减少无效 DRAM burst。
- **仓库**：`https://github.com/m-asiatici/MSHR-rich`（MIT）、`https://github.com/EPFL-LAP/fpga19-MOMS`（MIT）；配套论文 TRETS 2022。
- **关键路径**：MSHR-rich 的 `src/`（Chisel/VHDL 混合，克隆日期 2026-09-13 未记 commit）；论文第 1、6 节。
- **适配点**：只有「同一行/同一 burst 有多笔请求」时才赚；论文原话是针对 latency-insensitive、irregular 的 SpMV/图类负载。
- **硬伤**：本质是 cache，需你接受访存语义改变；写路径未核；同为旧工具链。
- **证据级别**：机制与论文结论 = **事实**；对你的 8 深度场景 = **推断（可能无效）**。

### S3 LiteDRAM + LiteX（控制器/集成底座，低成本备选）

- **机制一句话**：不是加速器；它提供「多 bank 行并行 + per-bank round-robin + 每 bank 队列深度 8」，配合 `bank_byte_alignment` 把离散地址尽量铺到不同 bank，让行激活/预充电互相重叠。
- **仓库**：`https://github.com/enjoy-digital/litedram`；许可 **BSD-2-Clause**（源文件头 `SPDX-License-Identifier: BSD-2-Clause`，如 `litedram/frontend/axi.py:5`）。
- **关键路径**：`litedram/frontend/axi.py`（`LiteDRAMAXI2NativeW/R`，docstring 明写 `No reordering.`）；`litedram/core/crossbar.py:144`（per-bank `RoundRobin`）；`litedram/core/bankmachine.py:116-119`（命令队列 = `cmd_buffer_depth` 默认 8）；`litedram/core/controller.py:43-46`（`address_mapping="ROW_BANK_COL"`、`bank_byte_alignment`）。
- **适配点**：只有在「随机地址在 bank 维度上被分散」时才赚；若你的离散地址低位固定，会集中打同一个 bank，收益为 0（【推断】）。
- **硬伤**：AXI 前端不做 4K 拆分、不做窄/unaligned 聚合、读返回严格保序；地址映射只支持连续 bank 位段（无 XOR/bit-swap）。
- **证据级别**：源码与许可 = **事实**；「能提升多少」= **未知/未核实**（需上板测）。

### S4 axiZero（互连备选）

- **机制一句话**：把仲裁从「固定优先级」换成 WRR/QoS+aging，降低多主竞争时离散流被「饿死」或产生长气泡的概率。
- **仓库**：`https://github.com/lcapossio/axiZero`；许可 **MIT**。
- **关键路径**：`hw/spinal/axizero/crossbar/Axi4Crossbar.scala:89-138`（QoS/aging、RR/固定优先级/WRR）、`adapters/WidthConverter.scala`（up/downsizer）、`README.md:47-62`。
- **适配点**：只在「多主 + 主机侧离散」同时成立时改善公平性与气泡；单主场景无效。
- **硬伤**：**未实现 4K 拆分**（本次 grep 未命中）；star=5，独立复现者少；集成需 SpinalHDL 工具链。
- **证据级别**：特性与源码 = **事实**；收益 = **推断**。

### S5 iob-cache（对照组）

- **机制一句话**：通用可配置 L2（write-back/allocate 可选），靠 cache 命中吸收同一 line 的重复访问。
- **仓库**：`https://github.com/IObundle/iob-cache`；许可 **CERN-OHL-S-2.0（强互惠）**。
- **硬伤**：对**真随机零命中**，收益为 0（【推断】，理由：无空间/时间局部性）；强互惠许可对产品化不友好；需 Nix/Py2hwsw 流程。
- **证据级别**：许可/特性 = **事实**；对本场景无效 = **推断**。

### S6 RCR（ICFPT19，仅机制参考，无开源）

- **机制一句话**：不改 DDR 控制器，而是用 miss 系统里已经堆积的成千上万条未来请求，做「单请求级」的大规模重排，把同一 bank 的 row 冲突压掉，且不像 burst 拼装那样产生废数据。
- **来源**：`In Search of Lost Bandwidth: Extensive Reordering of DRAM Accesses on FPGA`（EPFL LAP 公开 PDF）。
- **原文可取用句**：「Memory controllers reorder DRAM commands to minimize row conflicts; however, general-purpose controllers must also minimize latency, which limits the depth of the internal queues over which reordering can occur.」「we use the thousands of future memory requests that spontaneously accumulate inside the miss-optimized memory system to implement an efficient large-scale reordering mechanism」「Our solution outperforms the baseline miss-optimized memory system by up to 81%」「has better worst, average, and best performance than DynaBurst across 15 benchmarks and 30 architectures」。
- **硬伤**：**无仓库**（本次检索未找到任何 EPFL-LAP RCR 代码仓）；需要成千在途请求；论文定位是 latency-insensitive。
- **证据级别**：论文结论 = **事实（论文级）**；可复用性 = **弱证据**（无代码，且很可能只是专利/论文形态）。

### 对照行（闭源，不作为推荐）

| 来源 | 机制 | 为什么不推荐 |
|---|---|---|
| AMD/Xilinx AXI DMA (SG) | 描述符级 scatter-gather | 描述符开销摊薄 ≠ 减少 16B 的 DRAM burst 浪费；闭源 |
| AMD/Xilinx DataMover | 字节级 realignment/重排 | 闭源 IP，不可审计；本次无一手规格 |
| AMD/Xilinx SmartConnect QoS | 互连 QoS | 闭源；且 QoS 不能造 locality |

---

## 5. 推荐与适用条件 / 淘汰条件

**推荐（首选）**：S1 DynaBurst（读路径）作为技术族锚点，S3 LiteDRAM 作为 DDR 侧底座/对照基线。

- **适用条件（全部满足才上）**：
  1. 读为主（写路径本方案不覆盖）；
  2. 能把在途请求深度从 8 提到 ≥64（论文口径是上千，工程上至少两位数才有意义）；
  3. 接受「以面积换带宽」的 cache/MSHR 占地；
  4. 能接受 Chisel/IP-XACT 工具链，或愿意把 `SameRowReadSelector` 思路用自有 RTL 重写（约 200–400 行级，属【推断】）。
- **淘汰条件（任一出现就放弃 S1）**：
  1. outstanding/ID 数不可上调（→ 退化为 S3 调参）；
  2. 主负载是写（→ 开源无解，考虑闭源 DataMover 或主机侧合并）；
  3. 验收真的是 p99 尾延迟且不允许面积换延迟容忍（→ 缓存类方案会拉长最坏路径）；
  4. 必须沿用现有 MIG 且不能在其前面插 AXI 从端（→ 只剩 S4 类互连方案）。
- **备选（低成本、低收益）**：S3 的 bank 分散 + 队列深度调参；S4 的仲裁改善。二者都不改变「真随机 + 窄访问」的物理上限。
- **明确不选**：IOMMU/地址翻译（不减少 row 冲突）、prefetch（浪费 burst）、descriptor SG-DMA（改不到 DDR 侧 wasted burst）。

---

## 6. 风险、未知项、验证计划

### 6.1 风险清单

| 风险 | 类型 | 触发信号 | 缓解 |
|---|---|---|---|
| outstanding=8 使重排/合并窗口失效 | 架构级 | 接入后有效带宽与直连无差 | 先做「抬 outstanding」可行性评审；否则放弃本族 |
| 写路径无开源实现 | 覆盖缺口 | 负载含大量写 | 写侧先不动；仅在必要时评估闭源对照 |
| 许可传染 | 法务 | iob-cache(CERN-OHL-S)/GPL 类被引入 | 只用 MIT/BSD 仓（DynaBurst/MOMS/LiteDRAM/axiZero） |
| 工具链腐化 | 工程 | Vivado 2017.4 流程不可用 | 只移植 RTL 思路，不移植整个工程 |
| 4K 边界未定义归属 | 契约 | 出现跨界窄传输导致 split/错误 | 在主机侧保证 burst 不跨 4K；集成层加断言 |
| 论文数字被误当作你的预期 | 决策 | 拿「3.4×」当承诺 | 论文数字标注为论文工况（ZC706/AWS、SpMV、latency-insensitive） |

### 6.2 验证计划（谁 / 看哪个仓 / 什么激励 / 多久证伪）

**阶段 0（0.5 天，证伪最快）**
- 动作：在 LiteX/LiteDRAM 现有仿真里，用纯 16B 随机读 trace 打满 outstanding，测 overfetch 与 row hit 分布。
- 看：`_verify/litedram/test/test_axi.py`（现有 AXI 用例，无 4K/narrow 专项）、`litedram/core/bankmachine.py`。
- 成功标准：能稳定复现「有效带宽 ≈ 峰值 × 有用字节/DRAM burst 字节」。

**阶段 1（1–2 天，仿真）**
- 激励必须覆盖：**4K 跨界**（地址 0xFF8+16B）、**outstanding 打满**（8/16/64 三档）、**乱序 resp**（按 ID 乱序回填）、**bank 冲突**（构造同 bank 连续地址）、**窄传输/unaligned**（WSTRB 局部有效、地址非字对齐）。
- 看：`fpl19-DynaBurst/src/main/scala/extmemarbiter/ExternalMemoryArbiter.scala` 的 `SameRowReadSelector`；`m-asiatici/MSHR-rich`。
- 工具：Verilator（DynaBurst README 说 Verilator 非必需，但 RTL 级仿真可用）/ SpinalSim。

**阶段 2（2–5 天，架构级）**
- 工具：DRAMSys（`_verify/DRAMSys`，有 FR-FCFS、open/closed/adaptive page policy、`Reorder` 返回保序选项）——**这是最省力的「DDR 控制器重排深度 vs 你 trace」定量实验台**。
- 方法：导入你的随机 trace，扫 scheduler buffer 深度与 page policy，得到「控制器自身最多能救多少」的上界；它给出的上界若已足够，就不必引入 S1。

**阶段 3（上板，1–2 周）**
- 看：`litedram/bench/kcu105.py`、`xcu1525.py`（贴近 UltraScale）；`fpl19-DynaBurst` 的 ZC706 流程作参考。
- 度量：ILA 或自建计数器统计最坏/平均完成间隔（尾延迟代理）。

**谁能回答哪些未决问题**：见第 8 节。

---

## 7. 来源列表

| # | 标题 / 仓库 | URL | 本报告取用了哪句结论 |
|---|---|---|---|
| 1 | EPFL-LAP/fpl19-DynaBurst (MIT) | https://github.com/EPFL-LAP/fpl19-DynaBurst | README：「groups incoming requests into bursts… reduces DDR row conflicts and increases the utilization of DDR bursts」；「Vivado 2018.3 uses different default settings for the AXI interconnects that limit the number of outstanding memory operations, which strongly limit the system performance」；源码 `ExternalMemoryArbiter.scala` 的 `SameRowReadSelector` / `ReorderingExternalMemoryArbiter` / `maxInFlightRequests=128` / `AXI4FullReadOnly` / `numBanks=8` / `queueDepth=8` |
| 2 | DynaBurst FPL'19 幻灯片（EPFL/BSC 公开） | https://fpl2019.bsc.es/sites/default/files/uploaded/M31.FPL2019-slides-DynaBurst.pdf | 「Up to 60% of bandwidth lost to row conflicts」；「(1) Useless with multiple, narrow ports… Most of DDR burst content is wasted」；「Up to 3.4x speedup at similar area cost where caches are ineffective」；「Resource Utilization … PS 0–15% BRAM / 30–40% Slices；PL 2–15% BRAM / 10–15% Slices」；测试平台「ZC706… PL DDR3 12.0 GB/s through one 512-bit port at 200 MHz」 |
| 3 | Asiatici & Ienne, *Request, Coalesce, Serve, and Forget*（TRETS 15(2), 2021/2022） | https://www.epfl.ch/labs/lap/wp-content/uploads/2022/06/AsiaticiJun22_RequestCoalesceServeAndForget_TRETS.pdf | 「both DDR3 and DDR4 operate on bursts of eight beats, normally of 64 bits each, which results in a minimum access granularity of a full 512-bit burst. If accesses are narrower than the burst size, then the remaining data returned from memory will be discarded」；「on the ZC706 PS system… single requests which waste 75% of the burst content」；「provides up to 25% speedup with 24× area reduction on 15 large sparse matrix-vector multiplication benchmarks」 |
| 4 | Csordas, Asiatici & Ienne, *In Search of Lost Bandwidth: Extensive Reordering of DRAM Accesses on FPGA*（ICFPT'19） | https://www.epfl.ch/labs/lap/wp-content/uploads/2020/03/CsordasDec19_InSearchOfLostBandwidthExtensiveReorderingOfDramAccessesOnFpga_ICFPT19.pdf | 「general-purpose controllers must also minimize latency, which limits the depth of the internal queues over which reordering can occur」；「thousands of future memory requests… implement an efficient large-scale reordering mechanism」；「outperforms the baseline… by up to 81%」；「better worst, average, and best performance than DynaBurst across 15 benchmarks and 30 architectures」 |
| 5 | enjoy-digital/litedram (BSD-2-Clause) | https://github.com/enjoy-digital/litedram | `frontend/axi.py` docstring「No reordering.」；`core/crossbar.py`「Each bank has a RoundRobin arbiter」；`core/controller.py` `cmd_buffer_depth=8`、`address_mapping="ROW_BANK_COL"`、`bank_byte_alignment`；`test/test_crossbar.py`「the only supported address mapping is ROW_BANK_COL」 |
| 6 | enjoy-digital/litex | https://github.com/enjoy-digital/litex | AXI 互连实现位于 `litex/soc/interconnect/axi/`；本次在该目录检索未见 4K 边界拆分逻辑（【待核实】） |
| 7 | m-asiatici/MSHR-rich、EPFL-LAP/fpga19-MOMS (MIT) | https://github.com/m-asiatici/MSHR-rich ；https://github.com/EPFL-LAP/fpga19-MOMS | 「multi-banked non-blocking cache that handles efficiently thousands of outstanding misses, especially suited for bandwidth-bound latency-insensitive hardware accelerators with irregular memory access patterns」 |
| 8 | IESE-T3/DRAMSys | https://github.com/IESE-T3/DRAMSys | 「FIFO, FR-FCFS and FR-FCFS with read/write grouping scheduling policies」「open, closed, open adaptive and closed adaptive page policy」；scheduler buffer 深度与 `Reorder` 返回策略（用作验证台） |
| 9 | alexforencich/verilog-axi (MIT) | https://github.com/alexforencich/verilog-axi | `README.md:11` 弃用声明；`axi_dma_rd.v`/`axi_dma_wr.v` 中 `ENABLE_SG` 走 `$error`（未实现）；全仓无 reorder 模块 |
| 10 | lcapossio/axiZero (MIT) | https://github.com/lcapossio/axiZero | README 特性表；`Axi4Crossbar.scala` 的 WRR/QoS+aging；未实现 4K 拆分 |
| 11 | IObundle/iob-cache（CERN-OHL-S-2.0） | https://github.com/IObundle/iob-cache | 「Write Policy is configurable: either write-through/not-allocate or write-back/allocate」；AXI4 后端可选 |
| 12 | BrendanJamesLynskey/RISCV_IOMMU (MIT) | https://github.com/BrendanJamesLynskey/RISCV_IOMMU | Sv32 I/O 地址翻译 + IOTLB + AXI4 接口（入选长名单后淘汰） |

---

## 8. 未决问题（最多 5 条）

| # | 问题 | 谁能回答 / 怎么回答 |
|---|---|---|
| Q1 | 「不关心有效带宽目标/尾延迟」到底是「没有数字目标但仍要机制」，还是「这两项不是选型维度」？若是后者，真正的选型维度是什么（面积？确定性？上市时间？） | 你（决策者）直接回答；这决定第 2.2 节验收表是否成立 |
| Q2 | outstanding 深度 8、ID 数量 4 是硬限还是当前实现值？能否通过换互连/加 ID 位宽提到 ≥64？ | 你方数字设计负责人；核 `AXIInterface` 的 `id_width` 与互连 `maxOutstanding` 配置（LiteX/axiZero 均可改） |
| Q3 | 离散模式是「完全均匀随机」还是「页内成簇、页间跳跃」？两者收益差一个量级 | 你方工作负载负责人；给一段真实地址 trace（≥10 万笔），用 DRAMSys 跑上界实验即可判定 |
| Q4 | 主负载读写比？写占比超过多少就不能只看读路径方案？ | 你方负载负责人；用 AXI 通道计数器统计 AR/AW 笔数 |
| Q5 | 是否必须沿用现有 MIG/DDR 控制器？若必须，能否在其 AXI 从端前插一级只读聚合器？ | 你方系统架构负责人；核当前 top 的 DDR 控制器例化与 AXI 端口连接方式 |

---

## 附录 A：本次核验动作记录（可复现）

- 克隆到工作区 `_verify/`：`enjoy-digital/litedram`、`alexforencich/verilog-axi`、`IESE-T3/DRAMSys`、`lcapossio/axiZero`、`BrendanJamesLynskey/RISCV_IOMMU`、`EPFL-LAP/fpl19-DynaBurst`、`IObundle/iob-cache`（克隆日期 2026-09-13）。
- 一手阅读并引用的文件：`litedram/frontend/axi.py`、`litedram/core/controller.py`、`litedram/core/crossbar.py`、`litedram/core/bankmachine.py`、`litedram/test/test_crossbar.py`；`fpl19-DynaBurst/src/main/scala/extmemarbiter/ExternalMemoryArbiter.scala`、`.../main/FPGAMSHR.scala`、`.../util/ReorderBuffer.scala`、`README.md`；`axiZero/README.md`、`hw/spinal/axizero/**`；`iob-cache/README.md`、`LICENSE`。
- 论文 PDF：TRETS 2022、ICFPT19、DynaBurst FPL19 幻灯片（均 EPFL LAP / BSC 公开直链，已下载并抽取文本）。
- 未做的事：未综合、未上板、未跑任何仿真；本报告所有带宽/延迟/资源数字均转引自上述公开来源，未自行推算绝对值。

## 附录 B：与现有划分的影响（模块级，不写 RTL）

| 模块 | 若采用 S1/S2（读路径聚合） | 若只采用 S3/S4（控制器+互连调参） |
|---|---|---|
| host（AXI 主机） | 需保证每笔 ≤64B 且不跨 4K；尽量多 ID/多在途 | 同左（更关键，因为没有聚合器兜底） |
| interconnect | 需允许按 ID 乱序返回并保持 AXI 保序语义 | 换 WRR/QoS+aging，避免离散流被饿死 |
| DMA | 不参与（本方案不用描述符） | 不参与 |
| 地址翻译 | 不引入 IOMMU；若需，仅做「bank 位段平移/打散」的极简重映射层 | 同左，且是主要收益来源之一 |
| 请求聚合（新增） | **新增一级只读聚合器/非阻塞缓存（吃加速的模块）** | 不新增 |
| DDR 调度 | 通用 AXI 从端，依赖下游控制器重排 | 调 `cmd_buffer_depth`/page policy/`bank_byte_alignment` |
| CDC/桥 | 若聚合器在 300–400MHz 域而 DDR 在 200MHz，需新增异步 FIFO | 已有 CDC 不变 |
