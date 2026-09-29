# FPGA 运行时可重构多项式 CRC 设计草案

## 0. 目标与边界

本文定义一个可实现的 FPGA CRC 模块方案：CRC 多项式和关联参数可由 CSR 在运行时更新，更新过程**不要求拉低 `sys_rst_n`**，也不要求重载 bitstream、DFX 或部分重配置。重构的对象是寄存器内容和由其生成的线性变换矩阵，不是 FPGA 逻辑结构。

基线实现使用一个时钟域的 `sys_clk`，接收 AXI-Stream 风格输入，使用 AXI-Lite 风格 CSR。设计覆盖 `CRC_W` 为 8、16、32、64 的常用实例；`CRC_W` 本身、数据并行度和存储深度是编译期参数，不能通过 CSR 改变。

本文是 **Design Draft，非 FROZEN**。最后的 [D4](#d4-风险与-tbd) 列出了需在芯片集成前冻结的项目。

---

## D1. 架构

### D1.1 CRC 数学和参数约定

#### 多项式

对宽度 `W = CRC_W`，使用生成多项式：

\[
G(x) = x^W + \sum_{i=0}^{W-1}p_i x^i
\]

`x^W` 为最高项。规范（canonical）内部计算固定采用：

- 正向、多项式最高位先移位；
- 余数寄存器 `R[W-1:0]` 中的 bit `i` 对应 \(x^i\)；
- 每个输入比特先与移出最高位异或；余数左移一位；若结果为 1，则与低 `W` 位系数向量 `p[W-1:0]` 异或。

这样内部只有一套递推和一套矩阵构建器。软件可在 `poly_format` 中选择两种**写入表示**：

| `poly_format` | `SHADOW_POLY_FULL[W-1:0]` 的含义 | 典型 CRC-32 低 W 位示例 |
|---|---|---|
| `NORMAL` | bit `i` 就是 \(p_i\) | `0x04C11DB7` |
| `REVERSED` | 正向低 W 位系数向量的 bit reflection | `0xEDB88320` |

无论表示格式如何，`SHADOW_POLY_FULL[W]` 都是独立的 monic 声明位，必须写为 1。硬件在矩阵构建开始前将 `REVERSED` 反射为规范正向向量。故 `REVERSED` 是软件接口格式，不会让数据通路切换到另一套 LSB-first LFSR。

有效 CRC 多项式至少必须满足：

1. `SHADOW_POLY_FULL[W] = 1`（存在 \(x^W\) 项）；
2. 规范化后的 `p[0] = 1`（存在常数项）；
3. `CRC_W` 与该综合实例一致。

违反上述任一条件时，本次 apply 被拒绝，当前 active 配置保持不变。`CRC_W` 无需也不应由软件写入。

#### `init`、反射和结果

每帧的初始余数为 `init[W-1:0]`。一帧的输入字节按照传输中的 byte 0、byte 1、… 顺序处理：

- `refin=0`：每个字节按 bit 7 至 bit 0 注入规范递推；
- `refin=1`：每个字节按 bit 0 至 bit 7 注入规范递推，等价于先 bit-reverse 该字节。

帧结束时，原始余数为 `raw_crc`。输出 `crc_data` 的定义为：

1. 若 `refout=1`，先对 `raw_crc` 的 `W` 位做 bit reflection；否则保持不变；
2. 与 `xorout[W-1:0]` 异或。

`xorout` 按最终输出位序解释，因此软件应写入期望输出表示下的掩码。上述约定可表达常见 CRC-8/16/32/64 变种；例如 CRC-32/ISO-HDLC 可作为**默认示例**使用 `W=32`、正向 `0x04C11DB7`、`init=0xFFFFFFFF`、`refin=1`、`refout=1`、`xorout=0xFFFFFFFF`，但不是唯一或硬锁模式。

#### 参数分类

| 项目 | 类型 | 原因 |
|---|---|---|
| `CRC_W`（8/16/32/64） | 编译期 | 决定寄存器、矩阵和 XOR 网络规模 |
| `LANES`（每拍 1/4/8 字节） | 编译期 | 决定流口宽度及要生成的矩阵集合 |
| 矩阵实现方式、流水级数、默认值 | 编译期 | 决定时序/资源结构 |
| `poly_full`、`poly_format` | CSR 运行时 | 决定反馈系数 |
| `init`、`xorout`、`refin`、`refout` | CSR 运行时 | 决定每帧初始化和最终编码 |
| `config_tag` | CSR 运行时 | 供软件把结果和配置版本关联 |

### D1.2 推荐默认架构：影子配置 + 运行时构建并行矩阵

推荐基线为“**并行矩阵数据通路 + 串行小 FSM 矩阵构建器**”：

1. `active_bank` 保存当前帧正在使用的标准化多项式、`init`、`xorout`、反射控制和 `config_epoch`。
2. CSR 写入只修改 `shadow_bank`；不会影响正在计算的帧。
3. 软件发出 `APPLY_REQ` 后，控制器对影子配置做快照和合法性检查。
4. 在安全边界，矩阵构建 FSM 根据快照多项式重建所有所需 byte-count 的线性变换矩阵，写入非活动 `matrix_bank`。
5. 构建完成后，`active_bank` 与新 `matrix_bank` 一次性切换；随后的帧才使用新配置。

对于一次处理 `n` 个数据比特的线性 CRC，状态更新写成：

\[
R_{next}=A_nR_{current}\oplus B_nD
\]

其中：

- `A_n` 为 `W × W` 的零输入状态变换矩阵；
- `B_n` 为 `W × n` 的输入影响矩阵；
- `D` 是按实际时间顺序排列的输入比特向量。

当 `LANES=L` 时，基线矩阵库保存 `n=8k`、`k=1..L` 的 `(A_n,B_n)`，使连续 `k` 个有效字节可一拍处理。`tkeep` 仅允许低 `k` 位连续为 1，因此不需要为任意稀疏 byte mask 生成矩阵。

构建算法不依赖固定多项式，且不生成 RTL：

1. 对每个 `k=1..L`，令 `n=8k`。
2. 依次以 `W` 个状态基向量作为初始 `R`，输入 `n` 个零比特，所得向量依次成为 `A_n` 的列。
3. 依次以 `n` 个单热输入序列作为 `D`，从零状态运行 `n` 个规范单比特递推，所得向量依次成为 `B_n` 的列。
4. 对每一列使用上节的单比特递推；输入单热位置与 `D` 的时间顺序严格一致。
5. 全部矩阵完成并通过内部完成计数检查后，才允许 bank swap。

实现可让构建 FSM 每个 `sys_clk` 执行一次 `W` 位单比特递推。该选择资源小、易验证；配置期间暂停新帧，而不会改变当前帧。保守的构建周期上界为：

\[
C_{build}=\sum_{k=1}^{L} 8k(W+8k)
\]

不含少量状态切换周期。例：`W=64, L=8` 时为 31,488 个 `sys_clk` 周期。若系统要求缩短切换空档，可让构建器一次推进多个比特或使用后述组合展开方案；对外的 apply 原子性不变。

矩阵存储量为：

\[
\sum_{k=1}^{L}W(W+8k)\text{ bits}
\]

例如 `W=64, L=8` 约为 55,296 bit，适合用 LUTRAM/BRAM 或寄存器阵列，具体取决于器件和矩阵读取结构。数据通路对选中矩阵的每一行做 AND-reduce/XOR-reduce，得到新的 `R`。`init` 不需要进入矩阵库，帧首拍直接将其作为 `R_current`。

推荐理由：它把“可变多项式”从最高速数据路径中移到一次性的后台构建阶段。稳定传输期间的逻辑是固定的 XOR 网络，运行时不会修改 LUT 配置。

### D1.3 备选架构比较

| 架构 | 方法 | 优点 | 局限/适用场景 |
|---|---|---|---|
| A. 可编程 tap 串行 LFSR | 每拍处理 1 bit，tap 向量来自 active CSR | 最小面积；重配仅换 tap；无需矩阵 | 吞吐量为 1 bit/clk。适合低速控制报文、验证原型或极小 FPGA |
| B. 运行时矩阵并行（推荐） | 如 D1.2，apply 时重建 `A/B`，正常时一拍处理 `LANES` 字节 | 高吞吐；无 bitstream 更新；配置和帧边界可原子化 | 有构建空档和矩阵存储；XOR 网络随 `W × (W+8L)` 增长 |
| C. 混合 byte-LFSR | 运行时生成 8-bit byte 变换；一个 beat 内串接 `LANES` 个 byte 变换 | 比完整 word 矩阵少存储，可一字节一字节复用 | 组合路径随 `LANES` 加长；高频下可能需要降低 `LANES` 或插入节拍 |

不建议用“所有候选多项式并行硬编码 + mux”的方式，因为它既不真正支持任意运行时系数，也会随候选集合迅速膨胀。也不需要 DFX/部分重配置：多项式是数据，tap/matrix 是数据派生物。

### D1.4 模块层级建议

```text
crc_reconfig_top
├── crc_axi_lite_cfg            CSR 地址译码、shadow 写入、W1C 状态
├── crc_reconfig_ctrl           APPLY_REQ、快照、合法性检查、bank swap 仲裁
├── crc_config_bank             shadow/candidate/active 参数与 config_epoch
├── crc_matrix_builder          单比特递推、A/B 列生成、inactive matrix_bank 写入
├── crc_stream_core
│   ├── crc_axis_frontend       tvalid/tready/tkeep/tlast 规则、帧边界
│   ├── crc_matrix_datapath     active 矩阵乘法、余数寄存器
│   └── crc_finalizer           refout、xorout、crc_data/crc_valid
└── crc_status_observer         sticky 位、计数器、活动配置可读回
```

`crc_reconfig_top` 对外仅暴露 CSR、流输入、CRC 结果和 `sys_clk/sys_rst_n`。构建器不得直接改写已选择的 `active` 矩阵 bank。

---

## D2. 接口与 CSR 映射

### D2.1 时钟与复位

- `sys_clk`：基线方案唯一时钟，服务于 CSR、构建器和流数据通路。
- `sys_rst_n`：异步有效低，仅用于逻辑上电初始化、清除瞬态状态和装载编译期默认 active 配置。

`sys_rst_n` **不是**配置 apply 的握手条件。正常运行中，软件在 `sys_rst_n=1` 时通过 `APPLY_REQ` 完成任意合法多项式切换；不得为了应用新多项式而要求复位。

若产品最终要求 CSR 与数据流不同时钟，基线不直接跨域：应在 `crc_reconfig_top` 外或控制器中添加请求/确认 toggle synchronizer、配置快照稳定窗口和数据流 async FIFO。跨域版本仍须以数据域确认的安全帧边界作为 bank swap 点，不能直接同步多位配置总线。

### D2.2 流接口

输入采用 AXI-Stream 子集，信号均在 `sys_clk` 域：

| 端口 | 方向 | 宽度 | 定义 |
|---|---:|---:|---|
| `s_axis_tvalid` | in | 1 | 输入 beat 有效 |
| `s_axis_tready` | out | 1 | 模块可接收 beat |
| `s_axis_tdata` | in | `8*LANES` | byte 0 位于最低 8 bit |
| `s_axis_tkeep` | in | `LANES` | 有效 byte mask |
| `s_axis_tlast` | in | 1 | 已接受 beat 是本帧最后一个 |
| `m_crc_valid` | out | 1 | 一帧 CRC 结果有效 |
| `m_crc_ready` | in | 1 | 下游接收结果 |
| `m_crc_data` | out | `CRC_W` | 已完成 `refout/xorout` 的 CRC |
| `m_crc_epoch` | out | 16 | 生成该结果的 active `config_epoch` |
| `m_crc_tag` | out | 16 | 生成该结果的 active `config_tag` |

一个输入 beat 仅在 `s_axis_tvalid && s_axis_tready` 时被接受。帧由第一个被接受的 beat 隐式开始，由带 `s_axis_tlast=1` 的被接受 beat 结束。

合法 `tkeep` 为 `(1<<k)-1`，其中 `1 <= k <= LANES`；字节 0 最先进入 CRC。任意非连续 mask 或全零 mask 是接口错误。对于这种罕见上游违约，采用 **Role A：drop + sticky**：

- 置位 `bad_tkeep_sticky` 和 `frame_drop_sticky`；
- 不使用该 beat 更新余数；当前帧剩余输入均被丢弃到接受到 `tlast`；
- 该帧不产生 `m_crc_valid`；
- 到 `tlast` 后回到空闲状态。状态位由软件 W1C 清除，或由 `sys_rst_n` 清除。

这不是多级恢复 FSM，也不会产出看似正常但已损坏的 CRC。

正常背压采用 `tready`，而不是在吞吐冲突时丢正常数据：

- `m_crc_valid=1` 且 `m_crc_ready=0` 时，单项结果寄存器满；`s_axis_tready=0`，避免接受下一帧后无处保存结果。
- 矩阵构建、候选配置切换或 `apply_busy=1` 时，`s_axis_tready=0`，保护新帧不被半新半旧配置处理。
- 正在计算一个合法帧时，数据通路可每拍接收一个 beat；末拍的结果寄存器可在下一拍置 valid。

选择 ready 背压是因为正常帧数据不可丢；drop+sticky 只用于已违反接口契约或重复控制请求等罕见异常。

### D2.3 CSR 接口和地址映射

CSR 可封装为 AXI-Lite 32-bit slave。常规 AXI-Lite `AW/W/B` 与 `AR/R` 握手适用；`WSTRB` 必须受尊重。多 word 参数没有“边写边生效”语义：软件写完完整 shadow 字段后再写 `APPLY_REQ`。

下表以 byte offset 表示。`N_W=ceil(W/32)`，`N_P=ceil((W+1)/32)`；多 word 向量按照 word 0 为最低有效 32 bit 的 little-endian word 顺序映射。

| Offset | 名称 | 访问 | 字段/语义 |
|---:|---|---|---|
| `0x000` | `ID_VERSION` | RO | IP 标识、寄存器版本 |
| `0x004` | `CAPS` | RO | `CRC_W`、`LANES`、矩阵模式、`N_W`、`N_P` |
| `0x008` | `STATUS` | RO/W1C | 见 D2.4；向 1 写清对应 sticky 位 |
| `0x00C` | `CONFIG_STATE` | RO | `frame_open`、`drop_frame`、`apply_busy`、`apply_pending`、`matrix_active_bank` |
| `0x010` | `APPLY` | WO | bit 0=`APPLY_REQ`；其他位保留，写 0 无影响 |
| `0x014` | `ACTIVE_EPOCH` | RO | 当前 active 配置版本号 |
| `0x018` | `BUILD_PROGRESS` | RO | 构建中的 `k`、列索引、bit 索引；空闲时为 0 |
| `0x020 + 4*i` | `SHADOW_POLY_FULL[i]` | RW | `i=0..N_P-1`，位 `j` 对应完整多项式声明位 `p_j` |
| `0x040 + 4*i` | `SHADOW_INIT[i]` | RW | `i=0..N_W-1` |
| `0x060 + 4*i` | `SHADOW_XOROUT[i]` | RW | `i=0..N_W-1` |
| `0x080` | `SHADOW_OPTIONS` | RW | bit 0=`refin`，bit 1=`refout`，bit 2=`poly_format`（0 normal，1 reversed） |
| `0x084` | `SHADOW_TAG` | RW | 软件定义的 16-bit 配置标签 |
| `0x0A0 + 4*i` | `ACTIVE_POLY_FULL[i]` | RO | 标准化后、当前 active 完整多项式 |
| `0x0C0 + 4*i` | `ACTIVE_INIT[i]` | RO | 当前 active `init` |
| `0x0E0 + 4*i` | `ACTIVE_XOROUT[i]` | RO | 当前 active `xorout` |
| `0x100` | `ACTIVE_OPTIONS` | RO | 当前 active `refin/refout`；`poly_format` 可读为提交格式 |
| `0x104` | `ACTIVE_TAG` | RO | 当前 active tag |
| `0x108 + 4*i` | `LAST_RAW_CRC[i]` | RO | 最近一次成功帧结束时的 raw remainder |
| `0x128` | `DIAG_COUNTERS` | RO | 可选：成功帧、丢弃帧、apply 成功计数的低位 |

地址范围之间应按最大受支持 `CRC_W` 预留，或在实际实现中将后续基址按 `N_W/N_P` 动态推导；二者选一后必须在 CSR 版本号中冻结。为便于软件驱动，推荐在首版直接预留到 `CRC_W=64`，即 `N_W=2`、`N_P=3`，未使用位读 0、写忽略。

`SHADOW_POLY_FULL[W]` 是明确存在的 monic 声明位，不能因 `W=32/64` 而被软件省略。例如 `W=32` 时，`SHADOW_POLY_FULL[0]` 写 `0x04C11DB7`，`SHADOW_POLY_FULL[1]` 的 bit 0 写 1；`W=64` 时则在第三个 word 的 bit 0 写 1。

### D2.4 状态和可观测性

`STATUS` 推荐定义以下 sticky 位（由写 1 清除，除非另有说明）：

| bit | 名称 | 置位条件 |
|---:|---|---|
| 0 | `poly_monic_error_sticky` | apply 快照中 `poly_full[W] != 1` |
| 1 | `poly_const_error_sticky` | 标准化后 `p[0] != 1` |
| 2 | `apply_reject_sticky` | 本次 apply 因任意合法性检查失败被拒绝 |
| 3 | `apply_midframe_sticky` | `APPLY_REQ` 到来时 `frame_open=1` |
| 4 | `apply_busy_sticky` | builder/切换已忙时又收到 `APPLY_REQ`，后一个请求被丢弃 |
| 5 | `bad_tkeep_sticky` | 接受了非法 `tkeep` |
| 6 | `frame_drop_sticky` | 一个输入帧因接口错误被丢弃 |
| 7 | `result_overrun_sticky` | 仅用于实现错误诊断；设计正确时不应置位 |
| 8 | `cfg_write_during_pending_sticky` | `apply_pending`/`apply_busy` 时写 shadow；允许写，但提示其不影响已快照 candidate |
| 9 | `matrix_build_error_sticky` | builder 的范围/完成计数自检失败，禁止切换 bank |

`apply_busy`、`frame_open`、`drop_frame` 不是 sticky 错误，放在 `CONFIG_STATE` 实时读取。`ACTIVE_*` 和 `m_crc_epoch/m_crc_tag` 让软件可确认某个结果确实使用了期望配置，而不是仅凭写 CSR 的时间猜测。

---

## D3. 时序、吞吐和运行时重构序列

### D3.1 正常数据时序

推荐默认配置 `LANES=8`（64-bit 输入），但 `LANES=1/4/8` 均可综合：

| 配置 | 最大接受速率 | 每字节处理周期 | 从接受末拍到 `m_crc_valid` |
|---|---:|---:|---:|
| `LANES=1` | 1 byte/`sys_clk` | 1 | 1 个 `sys_clk` |
| `LANES=4` | 4 byte/`sys_clk` | 1/4 | 1 个 `sys_clk` |
| `LANES=8` | 8 byte/`sys_clk` | 1/8 | 1 个 `sys_clk` |

表中速率以前端持续满足 `tvalid` 且不存在 `m_crc` 背压为前提。`tkeep` 为低 `k` 位连续 1 时选择 `k`-byte 矩阵，末拍不需要额外的逐字节循环。数据路径把余数寄存器更新为寄存器输出；因此结果的可见延迟为一拍。

基线推荐不在单帧反馈路径上插入普通流水级。若目标频率使 `W × (W+8L)` XOR-reduce 网络无法收敛，应优先：

1. 降低 `LANES`，或采用 D1.3 的 byte-LFSR 混合架构；
2. 使用经过验证的线性变换折叠/带上下文队列的流水架构；
3. 对矩阵做布线/逻辑分组优化。

不得简单在余数反馈链中插入寄存器后仍宣称每拍接受一个相邻 beat；否则后续 beat 会使用陈旧余数。若采用流水，吞吐、`tready` 和延迟必须在 `CAPS`/接口说明中重新声明。

### D3.2 配置提交状态机与无复位 apply

软件和硬件交互序列如下：

1. 软件任意顺序写 `SHADOW_POLY_FULL`、`SHADOW_INIT`、`SHADOW_XOROUT`、`SHADOW_OPTIONS`、`SHADOW_TAG`。
2. 软件写 `APPLY[0]=1`。硬件在该写握手被接受时原子快照全部 shadow 字段到 `candidate_bank`；之后对 shadow 的修改不影响该候选配置。
3. 控制器检查 candidate 的 `x^W`、常数项、保留位和格式字段。
4. 若非法，置对应 sticky 位和 `apply_reject_sticky`，丢弃 candidate，active 配置和输入服务均不变。
5. 若合法且当前没有帧，立即置 `apply_busy=1`，停止接收新的输入 beat，并构建 inactive `matrix_bank`。
6. 若合法但当前帧打开，置 `apply_pending=1` 和 `apply_midframe_sticky`；当前帧继续使用旧 active 配置直至已接受 `tlast`，不允许混合系数。
7. 当前帧结束后，控制器停止下一帧准入（`s_axis_tready=0`），清除 `apply_pending`、置 `apply_busy=1`，并开始构建。
8. builder 完成且自检通过时，在一个 `sys_clk` 边沿同时切换 active 参数 bank 和 matrix bank，`ACTIVE_EPOCH` 加 1，清除 `apply_busy`。
9. 随后重新允许 `s_axis_tready=1`。下一帧的第一个被接受 beat 必定使用新配置。

这定义为 **hold/apply-at-idle** 策略。帧中 apply 不丢弃当前正常帧，也不会让一帧的一部分使用旧多项式、另一部分使用新多项式。它没有复位步骤。

边界条件：

- `APPLY_REQ` 在 `apply_busy=1` 或 `apply_pending=1` 时：不排队第二个 candidate，置 `apply_busy_sticky` 并丢弃该请求。软件等待 busy 清零后重试。这是有意的简单控制平面契约，避免无界队列和恢复 FSM。
- 在 pending/busy 期间，shadow 寄存器仍可写；写入只影响下一次 apply，置 `cfg_write_during_pending_sticky` 供诊断。
- 结果接口可能仍持有旧帧的 `m_crc_valid`，同时 builder 运行；这安全，因为其 `epoch/tag` 已在帧开始时锁存。新帧仍被 `tready` 阻止。
- `sys_rst_n` 若被断言，会取消 pending/build、清空结果和帧状态，并恢复编译期默认 active 配置。这是复位的正常语义，不是 apply 的前置要求。

### D3.3 帧参数锁存规则

为防止寄存器读写与数据路径的时间竞争，`crc_stream_core` 在隐式帧首拍锁存：

- `frame_init`、`frame_xorout`、`frame_refin`、`frame_refout`；
- `frame_epoch`、`frame_tag`；
- 当前 active matrix bank 选择。

同一帧内仅使用这些锁存值。由于 D3.2 在 `frame_open` 时禁止 active bank swap，这一锁存既是防御性实现，也是对集成者的清晰约束。`m_crc_epoch`/`m_crc_tag` 输出锁存的帧属性，而非末拍时即时读取的 CSR。

### D3.4 不同实现的重构时延

| 架构 | apply 后对新帧的影响 | 配置重建量 |
|---|---|---|
| A. 串行 LFSR | 可在帧边界换 tap，通常 1 个空闲周期 | 无矩阵构建 |
| B. 推荐并行矩阵 | 阻塞新帧至 builder 完成 | 约 `C_build` 周期 |
| C. byte-LFSR 混合 | 阻塞新帧至 byte 变换生成完成 | 通常少于完整 word matrix；取决于生成策略 |

如果产品不能接受 B 的暂停，需在需求阶段明确可接受的资源代价：可做双 builder、加速构建或改用 A/C；不能通过“帧中立即改 tap”解决，因为那会损坏帧定义。

---

## D4. 风险与 TBD

### 已知实现风险

1. **矩阵位序错误**：`refin`、`refout`、`poly_format` 和 `D` 列序非常容易产生看似合理但不兼容的软件 CRC。实现验证必须针对已知向量比较多种宽度和反射组合，尤其是首/末 bit。
2. **XOR 网络时序**：`W=64, LANES=8` 的完整矩阵比 `W=8` 明显更深、更宽。综合后应检查 LUT 使用、扇出、布线和最差路径；必要时改用 C 或指定经过形式化验证的线性流水化。
3. **应用停顿预算**：按逐比特 builder，`W=64, LANES=8` 会暂停新帧约 31,488 个时钟。控制面软件必须容忍 `apply_busy`，或产品选择加速 builder。
4. **上游 AXIS 契约**：本设计用 `tready` 保证正常数据不丢。若上游不能遵守背压，则必须在模块前添加 FIFO；不能以忽略 `tready` 作为常规工作模式。
5. **非法配置语义**：拒绝 `p[0]=0` 是针对标准 CRC 生成多项式的明确产品选择。若未来必须支持非标准线性反馈变换，应新增 capability 和单独的数学/互操作定义，而不应悄悄放宽。

### TBD（冻结设计前确认）

| ID | 待确认项 | 影响 |
|---|---|---|
| TBD-1 | 首版 `CRC_W` 是单一综合值，还是一个同时支持 8/16/32/64 的最大 64 位实例？ | 面积、CSR `CAPS` 和软件驱动模型 |
| TBD-2 | `LANES`、目标器件与目标频率 | 选择推荐矩阵、byte-LFSR 或线性流水实现 |
| TBD-3 | 是否需要零长度帧 CRC 命令 | 需要增加显式 `EMPTY_FRAME_REQ` 及其和 apply 的仲裁 |
| TBD-4 | 是否必须保持完全标准 AXI4-Stream 的任意 `tkeep` 语义 | 若需要稀疏 mask，应规定压缩字节顺序或为各 mask 生成矩阵 |
| TBD-5 | AXI-Lite 与数据流是否始终同 `sys_clk` | 若否，需冻结跨域握手和 reset release 策略 |
| TBD-6 | builder 停顿上限 | 决定一次推进比特数、矩阵存储和控制器复杂度 |
| TBD-7 | sticky 位复位策略与错误遥测宽度 | 影响安全软件、寄存器版本和诊断覆盖 |

在这些 TBD 冻结前，D2 的 `APPLY_REQ` 原子快照、D3 的 hold/apply-at-idle 策略、以及“正常流量用 `tready`、异常契约违例用 drop+sticky”的原则保持不变。
 ### D2.1 时钟与复位
 
 - `sys_clk`：基线方案唯一时钟，服务于 CSR、构建器和流数据通路。
- `sys_rst_n`：异步有效低，仅用于逻辑上电初始化、清除瞬态状态和装载编译期默认候选配置。
 
 `sys_rst_n` **不是**配置 apply 的握手条件。正常运行中，软件在 `sys_rst_n=1` 时通过 `APPLY_REQ` 完成任意合法多项式切换；不得为了应用新多项式而要求复位。
 
复位释放后，控制器以编译期 `DEFAULT_*` 参数启动一次与普通 apply 相同的矩阵构建，期间 `s_axis_tready=0`。完成后该默认配置成为首个 active 配置。这样不要求把某个固定多项式的矩阵硬编码进 bitstream，也不会错误复用复位前的 matrix bank。

 若产品最终要求 CSR 与数据流不同时钟，基线不直接跨域：应在 `crc_reconfig_top` 外或控制器中添加请求/确认 toggle synchronizer、配置快照稳定窗口和数据流 async FIFO。跨域版本仍须以数据域确认的安全帧边界作为 bank swap 点，不能直接同步多位配置总线。
 
 ### D2.2 流接口
 - `APPLY_REQ` 在 `apply_busy=1` 或 `apply_pending=1` 时：不排队第二个 candidate，置 `apply_busy_sticky` 并丢弃该请求。软件等待 busy 清零后重试。这是有意的简单控制平面契约，避免无界队列和恢复 FSM。
 - 在 pending/busy 期间，shadow 寄存器仍可写；写入只影响下一次 apply，置 `cfg_write_during_pending_sticky` 供诊断。
 - 结果接口可能仍持有旧帧的 `m_crc_valid`，同时 builder 运行；这安全，因为其 `epoch/tag` 已在帧开始时锁存。新帧仍被 `tready` 阻止。
- `sys_rst_n` 若被断言，会取消 pending/build、清空结果和帧状态，并恢复编译期默认候选配置；复位释放后重新构建该默认配置的矩阵，完成前保持 `s_axis_tready=0`。这是复位的正常语义，不是 apply 的前置要求。
 
 ### D3.3 帧参数锁存规则
 