# 一维卷积神经网络（1D-CNN）FPGA 加速器
## Phase 1 — 模块微架构设计

| 项目 | 内容 |
| --- | --- |
| 文档编号 | QDR-1DCNN-FPGA-uARCH-P1 |
| 版本 / 状态 | **V1.0 待签核** |
| 编写日期 | 2026-10-17（Asia/Shanghai） |
| 上游 | Phase0 定稿 + Phase1 系统架构说明书 |
| 用途 | **两名互不交流的实施者的唯一微架构契约**；禁止私自改接口 |
| 禁止 | 本文不提供可综合完整 RTL；可含接口伪代码与状态机要点 |

---

## 0. 全局约定（所有模块强制）

### 0.1 数据类型

| 名称 | 定义 |
| --- | --- |
| `act_t` | `int16_t`（two's complement）激活/样点 |
| `wgt_t` | `int16_t` 权重/偏置 |
| `acc_t` | `int32_t` 累加器 |
| `score_t` | `int16_t` 或 `int32_t` 输出分数；**V1 默认 INT16**，累加后按 per-tensor/per-channel scale 右移饱和到 INT16 |

### 0.2 握手与时钟复位

- 流接口：AXI4-Stream（下文 `axis_*`）。
- 控制：AXI4-Lite 32-bit，见架构书寄存器 map（**不得改偏移**）。
- `clk`：模块属 `clk_pl`，除非注明。
- `rst_n`：**低有效**；异步断言、同步释放。
- 传输拍：`valid && ready`。

### 0.3 量化应用顺序（bit-exact 契约）

对每个 Conv 输出通道 c：

```
acc = bias_c                          # INT32，已含 BN 融合后的偏置
for ...: acc += (act * wgt)           # INT16×INT16 → INT32 MAC
acc_scaled = (acc * scale_mult_c) >> scale_shift_c   # 训练导出
act_out = saturate_int16(acc_scaled)
act_out = ReLU(act_out)               # max(0, x)，在饱和后或前？→ **约定：先 scale+饱和到 int16，再 ReLU**
```

MaxPool：对 INT16 取 max。GAP：INT32 累加后按长度做平均（除法可用倒数乘法；**除数与移位由导出脚本给出固定 reciprocal**，写入量化元数据区）。

### 0.4 测试向量契约

- 文件格式：每层输入/输出 HEX 或 CSV，INT16 十进制有符号；元数据 JSON：`scale_mult[]`, `scale_shift[]`, `recip_gap`.
- 至少 32 组：全零、全 +1、全 -1、饱和上溢、随机、真实窗。
- 顶层：输入窗 2048 × int16 → 输出 10 × int16 分数；**允许误差 0 bit**（相对定点参考）。

### 0.5 HLS 参数（建议同名）

```
WIN_LEN_MAX=4096, CH_MAX=2, N_CLASS=10,
PE_M=16,          // 时间维并行度（可综合扫）
PE_K_UNROLL=8,    // 核维展开
DATA_W=16, ACC_W=32
```

---

## 1. 模块 adc_frontend

### 1.1 职责

适配 AD7606 级 ADC 的 SPI 或并行接口，完成 2 通道同步采样对齐，经异步 FIFO 跨到 `clk_pl`，输出 AXIS `act_t` 流；检测溢出/失锁。

### 1.2 参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `ADC_IF_TYPE` | `0` SPI / `1` Parallel | 编译期 |
| `FIFO_DEPTH` | 256 | 异步 FIFO 深度（样点字） |
| `N_CH` | 2 | |
| `PACK_CH` | 0 | 0：按 `CH_SEL` 输出单通道流；1：双通道打包 |

### 1.3 接口时序

**时钟复位：** `clk_adc`, `rst_adc_n`, `clk_pl`, `rst_n`。

**物理侧（SPI 模式摘要）：** `adc_cs_n`, `adc_sclk`, `adc_mosi`, `adc_miso`, `adc_busy`, `adc_convst` — 具体时序遵循 AD7606 datasheet；采样率由 `REG_FS_SEL` 映射分频。

**AXIS 主口 `m_axis`（clk_pl）：**

| 信号 | 宽 | 说明 |
| --- | --- | --- |
| TDATA | 16 或 32 | PACK_CH=0 → 16；=1 → {ch1,ch0} |
| TVALID/TREADY/TLAST | 1 | 连续流，**无窗 TLAST**（窗边界由 window_buffer 产生） |
| TUSER | 24 | [7:0] ch_id（PACK=0 时），其余 0 |

**状态出：** `fifo_wr_err`, `fifo_rd_level`（可选）→ axi_ctrl。

**文字时序：**

```
clk_adc: CONVST 脉冲 → BUSY 高 → BUSY 降 → 读出 ch0,ch1 → 打包写入 FIFO wr
clk_pl:  若 !empty 且 TREADY → 弹出 FIFO → TVALID=1
         若 almost_full：置 ovfl sticky；策略=停 CONVST 或丢新样（默认停采并置错）
```

### 1.4 内部子块

1. `adc_phy` — SPI/并行状态机  
2. `pack_align` — 双通道对齐  
3. `afifo` — XPM/async FIFO，Gray 指针  
4. `axis_adapter` — FIFO → AXIS  

### 1.5 存储与带宽

- FIFO：256 × 32b ≈ 1 KB（计入「输入缓冲」预算）。  
- 吞吐：≤100 KB/s。

### 1.6 控制状态机要点

`IDLE → WAIT_BUSY → READ_CH → WRITE_FIFO → IDLE`；错误→`ERROR` 直到 soft_rst。

### 1.7 验收检查点

- 30 min @25.6 kHz 双通道无丢样（ovfl=0）。  
- 用 ILA 比对 FIFO 两侧样点连续序号。  
- 复位后 TVALID=0。

### 1.8 非目标

- 不做板级校准算法；不做 IEPE 激励控制。

---

## 2. 模块 preprocess_fir

### 2.1 职责

直流去除（滑动均值或一阶 IIR）+ 固定系数 FIR（抗混叠/带通）；`fir_bypass=1` 时纯组合旁路（1 拍寄存器可选）。

### 2.2 参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `FIR_TAPS` | 32 | 偶数对称优先 |
| `COEF_W` | 16 | 系数 INT16 |
| `BYPASS_REG` | 1 | 旁路是否打拍 |

系数常量 ROM；由脚本生成 `fir_coef.h / .coe`。

### 2.3 接口时序

- `s_axis` / `m_axis`：与全局 AXIS 契约一致（16/32 随 PACK_CH）。  
- `bypass`：来自 `REG_CTRL[3]`，同步到 clk_pl。  
- 旁路：`m.TDATA=s.TDATA`，握手直通（BYPASS_REG=1 则延迟 1 拍，TLAST/TUSER 同步延迟）。  
- 非旁路：流水 FIR，输入 ready 在内部管道允许时拉高；**不得改变样点速率含义**（1 in 1 out）。

### 2.4 内部子块

`dc_block` → `fir_systolic` → `axis_out`；bypass mux 在最前或最后（**约定：最先旁路，整条 FIR 冻结**）。

### 2.5 存储与带宽

- 系数 ROM：32×16b；延迟线 32×16b。  
- 可映射 Distributed RAM / BRAM；预算计入行缓存余量。

### 2.6 控制状态机要点

无重状态机；流水满后稳态 1 sample/clk（降低时钟时仍 1:1）。

### 2.7 验收检查点

- 与 Python 定点参考逐样点误差 < 1 LSB（非旁路）。  
- bypass 开关动态切换：切换后 1 窗内允许管道气泡，不得死锁。

### 2.8 非目标

- 自适应滤波；可变抽头运行时加载（V1 固定系数）。

---

## 3. 模块 window_buffer

### 3.1 职责

从连续流切出固定窗长样本；支持可编程 `WIN_LEN`∈{1024,2048,4096}、`WIN_HOP`；以 AXIS 输出一整窗（带 TLAST）；双缓冲或环形缓冲保证在 CNN 消费时仍可写入下一窗。

### 3.2 参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `DEPTH` | 4096 | 每通道最大 |
| `N_BANK` | 2 | 双缓冲 |

### 3.3 接口时序

- `s_axis`：连续样点（无 TLAST 要求）。  
- `m_axis`：窗输出；**窗内第 `WIN_LEN` 个样点 TLAST=1**；TUSER[15:0]=窗序号。  
- CSR：`WIN_LEN`,`WIN_HOP`,`CH_SEL`。  

**合法性：** `WIN_HOP` 必须整除关系满足 `1 ≤ HOP ≤ LEN` 且推荐 HOP∈{LEN, LEN*3/4, LEN/2}；非法写入置 `ERR_CODE=0x01`，拒绝更新运行参数直到写回合法值。

**无重叠（V1 承诺档）：** `HOP=LEN`：写满 A 库 → 弹出 A 库全部 → 同时写 B 库。  

**50% 重叠（可配但不承诺吞吐）：** 环形读指针回溯 `LEN-HOP`。

文字时序（双缓冲、无重叠）：

```
写指针填 bank0 至 LEN-1
发出 bank0 读出流（TVALID 受下游 ready）
同时写 bank1
bank0 读完且 bank1 满 → 交换
若两库皆满且下游未取完 → ovfl 错误（不得覆盖未读）
```

### 3.4 内部子块

`addr_gen` / `pingpong_mem` / `axis_reader` / `param_check`。

### 3.5 存储与带宽

- 2 × 4096 × 16b ≈ 16 KB（单通道）；双通道物理采集但仍单流进 CNN 时按 16–32 KB 计。  
- 计入架构「输入环形 ≤64 KB」。

### 3.6 控制状态机要点

`FILL0 / DRAIN0_FILL1 / DRAIN1_FILL0 / ERROR`。

### 3.7 验收检查点

- 已知斜坡输入：输出窗口内容与黄金切分一致。  
- 背压：下游停 1000 拍，上游继续填至双满 → 必须 err，不得静默覆盖。  
- hop=len 时窗间无重叠样点。

### 3.8 非目标

- 窗函数加权（Hann 等）— 若需要放在训练侧或后续。

---

## 4. 模块 cnn_engine

### 4.1 职责

执行基线 1D-CNN（Conv1→ReLU→Conv2→ReLU→Pool→Conv3→ReLU→GAP→FC）：weight-stationary；时间维 M 并行 + 核维 K 展开；INT16 MAC + INT32 累加；层间双缓冲；输出 10 类分数 AXIS。

### 4.2 参数（须与权重布局一致）

| 符号 | 基线值 |
| --- | --- |
| L1 | Cin=1, Cout=16, K=16, S=4, Rin=2048 → Rout=512 |
| L2 | 16→32, K=8, S=4 → 127 |
| Pool | K=2,S=2 → 63 |
| L3 | 32→64, K=3, S=1 → 61 |
| GAP | → 64 |
| FC | 64→10 |

并行度：`PE_M`（建议 8/16）、`PE_K_UNROLL`（建议 ≤K）、`PE_COUT`（通道并行，受 DSP 预算 ≤66）。

**延迟目标：** 基线 ≤500 μs @clk_pl（NFR-01）；不达挑战 250 μs 不阻塞 V1。

### 4.3 接口时序

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `s_axis_act` | in | 一窗激活；TLAST 结束 |
| `m_axis_score` | out | 10 拍分数（或 1 拍打包，**约定默认：连续 10 拍 TDATA=score[i]，第 10 拍 TLAST=1**） |
| `weight_port` | in | 见 weight_mem：按层基址只读 |
| `start/busy/done` | CSR 映射 | busy 期间忽略新窗或接受进入输入队列（深度 1） |
| `cyc_cnt` | out | 本窗从收齐到分数 TLAST 的 clk 数 |

**启动条件：** `eng_en && weight_ok &&` 收到完整窗。

**伪代码（层调度）：**

```
receive_window_to_bufA()
for layer in [conv1,conv2,pool,conv3,gap,fc]:
    run_layer(layer, buf_in, buf_out, wgt_base[layer])
    swap(buf_in, buf_out)   // 双缓冲
emit_scores()
```

### 4.4 内部子块

1. `in_buf` — 窗缓冲  
2. `line_buf` — 滑动窗口（K 深度）  
3. `mac_array` — DSP48 阵列，weight-stationary：权重驻留寄存器，激活滑动  
4. `quant_relu` — scale + 饱和 + ReLU  
5. `pool_unit` / `gap_unit` / `fc_unit`  
6. `feat_pingpong` — 层间特征 BRAM  
7. `sched_fsm` — 层/块调度  

### 4.5 存储与带宽

| 项 | 上限 |
| --- | --- |
| 特征双缓冲 | ≤260 KB |
| 行缓存 | ≤32 KB |
| DSP | ≤66（30%）目标 |

权重不内嵌本模块大数组，经 `weight_mem` 只读口；允许层开始时 burst 装载到 PE 局部寄存器（小）。

### 4.6 控制状态机要点

`IDLE → LOAD_WIN → L_CONV1 → L_CONV2 → L_POOL → L_CONV3 → L_GAP → L_FC → OUT_SCORE → IDLE`  
错误：`weight_ok=0` 启动 → `ERR_CODE=0x10`；计算溢出粘滞 `0x11`（可选）。

### 4.7 验收检查点

- 32 组向量 bit-exact（分数 0-bit）。  
- csyn：估计 latency ≤ 500e-6 * Fclk 周期数。  
- 资源：BRAM/DSP/LUT 在 NFR-06 内。  
- 背压：score 下游卡住时不覆盖输入队列（停或 err）。

### 4.8 非目标

- 运行时改拓扑；训练；Softmax（PS 侧可选）；50% 重叠吞吐保证。

---

## 5. 模块 weight_mem

### 5.1 职责

单套 INT16 权重 + 量化元数据常驻 BRAM；提供加载路径（PS 字写和/或 DMA）；向 cnn_engine 提供按地址只读口；**预留双 bank 热切换接口但不实现第二套存储**。

### 5.2 权重布局契约（禁止私改）

线性地址空间（单位：16-bit word），小端：

```
0x0000_0000: Conv1 weights  [Cout][Cin][K]   = 16*1*16
+ bias1 [16] + scale_mult1[16] + scale_shift1[16]   # shift 存 uint16
Conv2 weights 32*16*8 + bias2 + scales...
Pool: 无权重
Conv3 weights 64*32*3 + bias3 + scales...
GAP: recip_shift / recip_mult (2 words)
FC weights 10*64 + bias_fc[10] + scales_fc[10]
```

具体元素个数以训练导出 JSON `weight_map.json` 为准；**实施者必须消费同一导出脚本产物**，不得手写魔法偏移。总大小 ≈ 29K 参数 + 元数据 ≤ 80 KB。

### 5.3 接口时序

**加载口（V1 主路径：AXI-Lite 字写）：**

1. 写 `WEIGHT_WORDS`、可选 `WEIGHT_BASE`  
2. 连续写 `REG_WEIGHT_DATA`（每次 1×INT16 装在 data[15:0]，或每次 2 packed）**约定：data[15:0] 有效，逐 word 自增内部 wr_ptr**  
3. 写完后 `weight_ok=1`；中途 soft_rst 清 ok  

**可选 DMA 路径（预留）：** AXI-Full slave/master 将 DDR 镜像拷入；与字写互斥（`WEIGHT_CTRL.load_en`）。

**读口到引擎：**

```
input  [ADDR_W-1:0] rd_addr
input               rd_en
output [15:0]       rd_data   // 1 拍或 2 拍延迟，**固定为 1 拍同期读**（BRAM sync read）
```

**热切换预留：**

- 端口/寄存器：`bank_sel`, `bank_active`, `load_bank_id`  
- V1：`feat_hotswap=0`；仅 bank0 物理存在；`bank_sel=1` → 忽略或 `ERR_CODE=0x20`  

### 5.4 内部子块

`bram_bank0` / `wr_port_mux` / `rd_port` / `load_fsm` / `hotswap_stub`。

### 5.5 存储与带宽

≤80 KB BRAM；加载 <100 ms。

### 5.6 控制状态机要点

`EMPTY → LOADING → READY → (LOADING 覆盖重载)`；READY 时可读。

### 5.7 验收检查点

- 加载后随机抽 64 地址与文件一致。  
- 重载时间测量。  
- 头文件中热切换寄存器存在且 feat 位为 0。

### 5.8 非目标

- V1 双套常驻；加密权重。

---

## 6. 模块 axi_ctrl

### 6.1 职责

AXI4-Lite 从机；实现架构书完整寄存器 map；产生 `eng_en/capt_en/soft_rst/bypass` 等控制；汇总 status/IRQ；**禁止改变偏移与位域定义**。

### 6.2 参数

`C_S_AXI_ADDR_WIDTH=8`（≥0xA4）；`C_S_AXI_DATA_WIDTH=32`。

### 6.3 接口时序

标准 AXI4-Lite（AW/W/B/AR/R）；单拍；无 outstanding 要求（可 1）。  
`soft_rst`：写 `CTRL[2]=1` 保持 ≥16 clk，软件再清 0；或写 1 脉冲内部计时 16 clk。**约定：电平型，软件写 1 再写 0。**

### 6.4 内部子块

`axi_lite_slave` / `reg_file` / `irq_logic`。

### 6.5 存储与带宽

纯寄存器；无 BRAM。

### 6.6 控制状态机要点

AXI 握手标准；IRQ：`done_sticky & irq_en`。

### 6.7 验收检查点

- 写读回所有 RW 寄存器。  
- RO 寄存器写忽略。  
- ID 固定 `0x1DCN0101`。  
- 与驱动头文件 `regs.h` 一致（两实施者交付同一 `regs.h` 模板）。

### 6.8 非目标

- AXI-Full；复杂保护/MPU。

---

## 7. 模块 score_path / ps_handoff

### 7.1 职责

- **score_path（PL）：** 接收 cnn 的 10 分数 AXIS；写入只读寄存器快照 `REG_SCORE0..9`；可选转发 AXIS 给 DMA；产生 `irq`。  
- **ps_handoff（PS 边界）：** 驱动读取分数；argmax；FR-09 投票；告警与上报；**不在 PL 做投票**。

### 7.2 参数

`N_CLASS=10`；`SCORE_FMT=INT16`。

### 7.3 接口时序

```
分数到达：连续 10 拍 valid；拍 i → SCORE_i；第 10 拍 TLAST
同时 done_sticky≤1；若 irq_en → irq 脉冲 ≥2 clk
PS：读 SCORE；写 IER/STATUS 清 done
投票：软件环形保存最近 N 个 label；全相等则 alarm=1
```

### 7.4 内部子块

PL：`score_reg_bank` / `axis_to_reg` / `irq_pulse` / `axis_tee(optional)`  
PS：`uio_map` / `vote.c` / `mqtt_out`

### 7.5 存储与带宽

10×32b 寄存器；可选 DMA buffer 在 DDR。

### 7.6 控制状态机要点

PL：`WAIT_SCORE → CAPTURE → IRQ → WAIT_CLEAR`。

### 7.7 验收检查点

- 已知分数向量经寄存器读回一致。  
- 投票 N=3 注入序列验证误报抑制。  
- 断网落盘（FR-08）系统测试。

### 7.8 非目标

- PL 内 Softmax/交叉熵；云端协议细节（仅接口）。

---

## 8. 跨模块集成契约摘要

| 连接 | 契约要点 |
| --- | --- |
| FE→FIR→WIN | AXIS INT16；FIR 前无窗 TLAST |
| WIN→CNN | 每窗 LEN 拍 + TLAST；TUSER 窗号 |
| CNN↔WMEM | 同步 1 拍读；地址空间按 weight_map.json |
| CNN→SCORE | 10 拍 INT16 + TLAST |
| PS↔CTRL | 寄存器 map 冻结 |
| CDC | 仅 ADC FIFO 强制异步；其余优先单 clk_pl |

**错误码表：**

| 码 | 含义 |
| --- | --- |
| 0x00 | 无 |
| 0x01 | 窗参数非法 |
| 0x02 | 输入/窗溢出 |
| 0x10 | 权重未就绪 |
| 0x11 | 计算饱和粘滞（可选） |
| 0x20 | 热切换未实现 |
| 0x30 | ADC FIFO 溢出 |

---

## 9. BRAM 预算核对表（实施交付必填）

| 模块 | 设计预算 | 实施填写（实际） |
| --- | --- | --- |
| weight_mem | ≤80 KB | |
| cnn 特征+行缓存 | ≤292 KB | |
| window+adc FIFO | ≤64 KB | |
| 其它 | ≤4 KB | |
| **合计** | **≤440 KB（70%）** | |

超出 → **FAIL** 或有条件通过（附 tile 方案与责任人）。

---

## 10. 微架构签核检查表

| # | 项 | 要求 |
| --- | --- | --- |
| U1 | 七大模块均含职责/参数/接口/子块/存储/FSM/验收/非目标 | 是 |
| U2 | 寄存器 map 与架构书一致 | 是 |
| U3 | 量化顺序与向量 0-bit 契约 | 是 |
| U4 | NFR-01≤500μs、NFR-02 降重叠、BRAM≤70% 写死 | 是 |
| U5 | 热切换仅预留 | 是 |
| U6 | 两实施者无需横向交流即可对齐接口 | 是 |

**建议签核结论：** **PASS（建议用户确认后生效）**。

---

## 11. 修订历史

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| V1.0 | 2026-10-17 | 首版微架构契约 |

> **Phase 1 签核：PASS**（用户确认接受文档默认；2026-10-17 13:51 Asia/Shanghai）。可按 HANDOFF 分派双路隔离实施。
