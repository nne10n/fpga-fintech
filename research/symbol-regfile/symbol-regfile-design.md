# Per-symbol Register File 设计方案

## 0. 文档状态与边界

**状态：Design Draft，未 FROZEN。** 本文是实现规格，不是 RTL 设计文件；本仓库不
包含可综合 RTL、testbench 或仿真脚本。

模块管理固定编号的 4096 个标的槽位 `symbol_id = 0..4095`。每个槽位有四个独立的
32 位寄存器 `reg_sel = 0..3`。唯一允许的数据访问粒度为完整 32 位 word：

- 同步 SRAM 风格 RAM 主机端口；
- AXI4-Lite 从端口，数据总线宽度为 32 位。

本文仅定义这两个端口；不引入 CPU、DMA、缓存、FIFO 或额外控制寄存器。

## 1. D1 — 架构与容量

### 1.1 容量计算

| 项目 | 计算 | 结果 |
| --- | --- | --- |
| 标的数 | 固定 | 4096 |
| 每标的寄存器数 | 固定 | 4 |
| 总 word 数 | `4096 × 4` | `16384` 个 32-bit word |
| 总 bit 数 | `16384 × 32` | `524288 bit` |
| 逻辑容量 | `16384 × 4 byte` | **64 KiB** |

该 64 KiB 是有效载荷，不包含 RAM wrapper 的实现余量、输出寄存器或 AXI 控制寄存器。

### 1.2 建议 bank 划分

采用 **4 个 bank，按 `reg_sel` 划分**：

| bank 编号 | 容量 | 保存内容 | RAM 行地址 |
| --- | ---: | --- | --- |
| `bank0` | `4096 × 32 bit` | 每个标的的 `reg_sel=0` | `symbol_id[11:0]` |
| `bank1` | `4096 × 32 bit` | 每个标的的 `reg_sel=1` | `symbol_id[11:0]` |
| `bank2` | `4096 × 32 bit` | 每个标的的 `reg_sel=2` | `symbol_id[11:0]` |
| `bank3` | `4096 × 32 bit` | 每个标的的 `reg_sel=3` | `symbol_id[11:0]` |

每个 bank 采用一个概念上的 `4096 × 32`、同步读、真双端口（TDP）的 vendor RAM
wrapper：端口 A 服务 RAM 主机，端口 B 服务 AXI-Lite。推荐实现时使用目标厂商
RAM catalog/IP/wrapper（例如等价的 BRAM TDP wrapper），而不是手写异步双时钟 FIFO。
此端口分配仅用于固定布线；本规格不使用 TDP 的并发双端口能力。

本方案**不锁定 FPGA 型号，也不锁定 BRAM 或 URAM**。`4096 × 32 = 131072 bit/bank`，
通常适合由一个或多个 BRAM 原语拼接；是否改用 URAM 取决于目标器件、可用 BRAM 和
时序报告。

选择按 `reg_sel` bank 的原因：

1. 4 个寄存器天然被分开，地址到 bank 的映射直接且固定。
2. 仅需 4 个相同深度的 wrapper，地址译码和物理约束简单。
3. 相比按 `symbol_id` 低位哈希成 8/16 bank，bank 数、mux、RAM 碎片和控制复杂度更低。
   在本规格确认的主机互斥访问条件下，不存在跨主机同 bank 冲突代价。

### 1.3 数据路径与模块层次建议

```text
symbol_regfile_top
├── symbol_regfile_ram_port      # RAM 端口检查、读返回定时
├── symbol_regfile_axil          # AXI4-Lite AW/W/AR 与 B/R 前端
├── symbol_regfile_core          # 地址解码、请求执行、sticky error 汇总
└── symbol_regfile_bank_array
    ├── symbol_regfile_bank0
    │   └── vendor_tdp_ram_4096x32
    ├── symbol_regfile_bank1
    │   └── vendor_tdp_ram_4096x32
    ├── symbol_regfile_bank2
    │   └── vendor_tdp_ram_4096x32
    └── symbol_regfile_bank3
        └── vendor_tdp_ram_4096x32
```

`symbol_regfile_core` 对每个有效请求产生 `{bank_sel, row_addr}`。每个请求只使能一个
bank；跨主机请求不会在时间上重叠，因此 core 不包含双主机 bank 仲裁。

### 1.4 已确认（CONFIRMED）— 系统访问互斥假设

以下约束已由系统确认，是本设计草案的接口契约，而非待确认项：

1. RAM 主机在任一上升沿最多提交一个访问，`ram_we` 只用于在读和写之间二选一；不存在
   同拍读写。
2. AXI-Lite 在任一时段只进行一个方向的事务：读事务自 AR 握手至 R 握手完成，写事务自
   第一个 AW 或 W 握手至 B 握手完成；两者绝不重叠。
3. RAM 主机与 AXI-Lite 主机绝不同时访问本模块。系统必须确保 `ram_en=1` 的周期不与
   AXI 请求执行周期重叠，也不与 AXI 已接受但尚未完成的事务重叠。

因此，虽然每个 bank 固定将 RAM 接至端口 A、AXI-Lite 接至端口 B，但并发双端口活动
属于 out of scope，且假定永不发生。实现不得依赖厂商 RAM 的跨端口同周期读写、同地址
碰撞或 `READ_FIRST`/`WRITE_FIRST`/`NO_CHANGE` 等 collision mode 来定义功能。违反此
系统契约的输入序列不属于本规格的行为范围。

### 1.5 时钟与复位

- 所有端口、控制逻辑及四个 RAM wrapper 使用唯一的 `sys_clk`。
- `sys_rst_n` 是异步、低有效复位。AXI 的 `axil_aresetn` 是该信号的同名协议视图，
  必须直接连接为 `sys_rst_n`，不得形成第二个复位域。
- 复位时所有 AXI `READY/VALID` 输出为低，未完成 AXI 请求被取消；`err_sticky` 和
  `err_cause_sticky` 被清零。
- 存储阵列不做复位清零。复位后 16384 个数据 word 的值为 RAM wrapper/器件定义的
  未指定值；软件或 RAM 主机必须在读取前写入所需初值。
- 无 CDC。本模块不接受独立的 AXI 或 RAM 时钟；若系统不能提供相同 `sys_clk`，应在
  模块外部完成 CDC，方案待另行设计。

## 2. D2 — 接口与地址契约

除 `sys_rst_n` 外，所有输入均在 `sys_clk` 上升沿采样；所有输出相对于上升沿更新。
信号名均为 English snake_case。

### 2.1 顶层公共与错误观测端口

| 方向 | 信号 | 位宽 | 定义 |
| --- | --- | ---: | --- |
| input | `sys_clk` | 1 | 唯一时钟。 |
| input | `sys_rst_n` | 1 | 异步低有效复位。 |
| output | `err_sticky` | 1 | 任一 `err_cause_sticky` 位为 1 时为 1；只能由 `sys_rst_n=0` 清零。 |
| output | `err_cause_sticky[2:0]` | 3 | `[0]` 非法地址，`[1]` AXI 地址未对齐，`[2]` AXI `wstrb` 非 `4'hf`。只能由复位清零。 |

错误处理的铁律：检测到错误时**丢弃该访问、置位对应 sticky 位、保持该位直到
`sys_rst_n` 断言**。合法访问、读状态或任何“恢复”FSM 均不得清除此状态；本设计不设置
错误恢复 FSM。

### 2.2 RAM 主机端口（同步 SRAM 风格）

| 方向 | 信号 | 位宽 | 定义 |
| --- | --- | ---: | --- |
| input | `ram_en` | 1 | `1` 表示在该上升沿提交一个访问。 |
| input | `ram_we` | 1 | 在 `ram_en=1` 时，`1`=写，`0`=读。 |
| input | `ram_addr[14:0]` | 15 | **word 地址**，不是 byte 地址。`[14]` 必须为 0。 |
| input | `ram_wdata[31:0]` | 32 | 写数据；只在有效写时采样。 |
| output | `ram_rdata[31:0]` | 32 | 读数据，固定一拍返回；无 `ram_rvalid`。 |

RAM 地址的有效编码如下：

| `ram_addr` bit | 含义 |
| --- | --- |
| `[14]` | 保留，必须为 `0`；为 `1` 时是非法地址。 |
| `[13:2]` | `symbol_id[11:0]`。 |
| `[1:0]` | `reg_sel[1:0]` / `bank_sel`。 |

等价关系为：

```text
word_index[13:0] = { symbol_id[11:0], reg_sel[1:0] }
ram_addr          = { 1'b0, word_index[13:0] }
bank_sel          = ram_addr[1:0]
row_addr          = ram_addr[13:2]
```

`ram_en=1 && ram_addr[14]=1` 时访问不触及存储器，置位
`err_cause_sticky[0]`。若该非法访问为读，则在正常读返回时刻将
`ram_rdata` 驱动为 `32'h0000_0000`；若为写，则数据被丢弃。

本端口没有 `ready`，因此 RAM 请求绝不因 AXI 活动被反压。D1.4 要求系统在 RAM 访问
期间不发起或保持 AXI 事务。主机只能每周期提交一个完整 32 位读或写，且不支持 byte
enable、突发或非 32 位访问。

### 2.3 AXI4-Lite 从端口

AXI 接口工作于 `sys_clk`/`sys_rst_n`，32-bit 数据、32-bit 地址、单 beat，且不支持
burst。`axil_awprot[2:0]`、`axil_arprot[2:0]` 被采样但不参与访问权限判断。

| 通道 | 输入信号 | 输出信号 |
| --- | --- | --- |
| 写地址 | `axil_awaddr[31:0]`, `axil_awprot[2:0]`, `axil_awvalid` | `axil_awready` |
| 写数据 | `axil_wdata[31:0]`, `axil_wstrb[3:0]`, `axil_wvalid` | `axil_wready` |
| 写响应 | `axil_bready` | `axil_bresp[1:0]`, `axil_bvalid` |
| 读地址 | `axil_araddr[31:0]`, `axil_arprot[2:0]`, `axil_arvalid` | `axil_arready` |
| 读数据 | `axil_rready` | `axil_rdata[31:0]`, `axil_rresp[1:0]`, `axil_rvalid` |

采用标准握手：`VALID && READY` 的上升沿完成该通道传输；`BVALID`/`RVALID` 一旦置位，
对应数据和响应必须保持稳定直到 `BREADY`/`RREADY` 握手。

为使存储端口数量确定，AXI 前端的最大未完成量为：

- 全接口至多一个事务：写事务可分别暂存一个 AW 和一个 W，二者到齐后等待执行，直至
  B 通道握手；或者 AR 握手后等待执行，直至 R 通道握手；
- 写事务与读事务不得同时被接受、暂存、执行或等待响应。已暂存但尚未配对的 AW 或 W
  也会阻塞 AR 接收；
- 事务未完成时，其他方向的 `READY` 必须为低。AXI 主机必须遵守 `READY`，不得假定
  无条件接受。

为避免实现者对“资源可用”产生不同解释，`READY` 的精确定义如下。所有式子均隐含
`sys_rst_n=1`；复位期间三者均为 0。

```text
wr_busy       = 自第一个 AW 或 W 被接受起，到该写事务的 B 握手止
wr_addr_valid = 当前 wr_busy 事务已经保存 AW
wr_data_valid = 当前 wr_busy 事务已经保存 W
rd_busy       = 自 AR 被接受起，到该读事务的 R 握手止

axil_awready = !rd_busy && (!wr_busy || (!wr_addr_valid && wr_data_valid))
axil_wready  = !rd_busy && (!wr_busy || ( wr_addr_valid && !wr_data_valid))
axil_arready = !rd_busy && !wr_busy && !(axil_awvalid || axil_wvalid)
```

因此空闲时 AW 与 W 可同拍接收；已先接收 AW 时只接收 W，已先接收 W 时只接收 AW；
AW/W 均已保存、bank 正在执行或 `BVALID=1` 时，两者均不接收。写事务未完成时
`ARREADY=0`；读事务未完成时 `AWREADY=WREADY=0`。空闲周期若上游违反互斥假设并同时
驱动 `ARVALID` 与任一 `AWVALID`/`WVALID`，写方向优先被接受，`ARREADY=0`。因此接口
不会接受并行读写，也不需要 AXI 读写仲裁或 round-robin 令牌。

AXI 响应编码固定为：

| 条件 | `bresp` / `rresp` | 是否访问 bank |
| --- | --- | --- |
| 合法完整 32-bit 访问 | `2'b00` (`OKAY`) | 是 |
| 非法地址、未对齐地址或 `wstrb != 4'hf` | `2'b11` (`DECERR`) | 否，访问被丢弃 |
| 其他 | 不产生 `SLVERR` | — |

写地址和写数据允许任意先后到达。其配对后的合法性以该 AW 的地址和该 W 的
`wstrb` 共同判定；非法写仍必须产生一次 `BVALID` + `DECERR`。

### 2.4 AXI-Lite 地址图

`axil_awaddr` 和 `axil_araddr` 是该从端口的**本地 byte offset**。系统互连将本模块
映射到的绝对 base address 不属于本模块，见 D4 TBD。

| byte offset 范围 | 对齐要求 | 映射 |
| --- | --- | --- |
| `0x0000_0000` 至 `0x0000_fffc` | `addr[1:0] == 2'b00` | 有效 32-bit 寄存器 word。 |
| 其他任何值 | — | 非法地址，`DECERR`，丢弃并置 `err_cause_sticky[0]`。 |

有效 word 的精确位域：

| AXI byte 地址 bit | 含义 |
| --- | --- |
| `[31:16]` | 必须为 0；否则非法地址。 |
| `[15:4]` | `symbol_id[11:0]`。 |
| `[3:2]` | `reg_sel[1:0]` / `bank_sel`。 |
| `[1:0]` | 必须为 `2'b00`；否则未对齐。 |

```text
byte_offset = (symbol_id * 16) + (reg_sel * 4)
word_index  = byte_offset[15:2] = { symbol_id[11:0], reg_sel[1:0] }
bank_sel    = byte_offset[3:2]
row_addr    = byte_offset[15:4]
```

例：`symbol_id=12'h123`、`reg_sel=2` 对应 RAM word 地址 `15'h048e`，对应 AXI
byte offset `32'h0000_1238`。

地址检查彼此独立：AXI 地址既越界又未对齐时，`err_cause_sticky[0]` 和 `[1]` 均置位；
响应仍是单个 `DECERR`。合法对齐写只有 `axil_wstrb == 4'hf` 才执行，其他任意 strobe
组合置位 `[2]` 并返回 `DECERR`，从而禁止 byte/halfword 写。

## 3. D3 — 时序、吞吐与访问约束

### 3.1 RAM 端口时序

RAM 端口为固定一拍同步读。以下 `E0`、`E1` 均表示 `sys_clk` 上升沿：

```text
读：
             E0                         E1
ram_en       1  (ram_we=0)              X
ram_addr     A，采样                    X
ram_rdata    旧值 / 不关心              mem[A] 有效

写：
             E0                         E1
ram_en       1  (ram_we=1)              X
ram_addr     A，采样                    X
ram_wdata    D，采样                    X
存储器       在 E0 提交 mem[A] := D     后续读可见 D
```

连续读允许每拍一个请求；`ram_rdata` 在每个上升沿后对应前一拍采样的读地址。写周期不承诺
有意义的 `ram_rdata`。同一端口的写后下一拍读同一地址，必须返回新写入值。

### 3.2 AXI-Lite 最短时序

以下时序的“合法”指地址对齐且范围正确，写还要求 `wstrb=4'hf`。AXI 前端不做组合
read bypass，因而响应最早发生于 bank 发起后一拍。

```text
合法读：
E0: ARVALID && ARREADY，锁存 AR
E1: 该 AR 发往目标 bank 的端口 B
E2: RVALID=1, RDATA=读取值, RRESP=OKAY
E2..: 保持 RVALID/RDATA/RRESP，直至 RREADY 握手

合法写（AW 与 W 均已在 E0 前或 E0 到齐）：
E0: 锁存并配对 AW/W
E1: 写入目标 bank 的端口 B
E2: BVALID=1, BRESP=OKAY
E2..: 保持 BVALID/BRESP，直至 BREADY 握手

非法读 / 非法完整写：
E0: 接收 AR，或完成 AW/W 配对并判定非法；置对应 sticky 位
E1: 分别给出 RVALID+DECERR+零数据，或 BVALID+DECERR
```

`ARREADY`、`AWREADY`、`WREADY` 只在对应的一项暂存资源可用时置位，因此上图的 E0
可因已有 AXI 事务未完成而延后。由于 D1.4 确认 RAM 主机与 AXI-Lite 主机不重叠，E1
不会发生 RAM bank 冲突；合法 AXI 请求均在其排定的 E1 发往 bank。

### 3.3 双主机 bank 仲裁：N/A

这是 D1.4 已确认的系统假设的直接结果：RAM 主机与 AXI-Lite 主机从不在时间上重叠，
无论目标 bank 或 `row_addr` 是否相同。因此不存在同 bank 双主机冲突，RAM 优先、
公平仲裁和由 RAM 持续访问造成的 AXI 无界等待均不适用。端口 A/B 的固定接线不表示
允许并发访问；任何并发双端口操作都属于 out of scope。

## 4. D4 — 风险、假设与 TBD

### 已知风险与实现约束

1. **数据复位值未知。** 不复位 RAM 阵列避免引入 16384 word 的清零流程。系统初始化
   必须写入数据后再读。
2. **资源取决于器件。** 四个 `4096 × 32` TDP 实例的实际 BRAM/URAM 消耗、拼接方式和
   可用配置必须遵循目标厂商 wrapper。由于 D1.4 排除并发双端口活动，跨端口 collision
   mode 不是功能依赖。
3. **单时钟是前提。** 外部时钟域到 `sys_clk` 的 CDC 不是本模块职责，也不能以手写
   多时钟异步 FIFO 隐式加入。
4. **主机互斥是系统集成约束。** 若未来需要 RAM 与 AXI-Lite 并发访问，必须先定义仲裁、
   RAM 反压或缓冲契约，以及目标 RAM 的跨端口 collision 行为；这会改变本规格。

### TBD（实现前必须确认）

| TBD | 原因 / 决策影响 |
| --- | --- |
| 系统互连给 AXI-Lite 的绝对 base address | 本文只定义本地 `0x0000_0000..0x0000_ffff` aperture；系统地址译码责任须明确。 |
| 目标 FPGA 厂商、具体器件和 approved RAM wrapper | 决定 BRAM/URAM 选择、实例数量、初始化与综合属性；当前仅作 BRAM TDP 的推荐。 |
| AXI 复位期间上游 master 的事务取消/重试约定 | 本模块在 `sys_rst_n=0` 时不接收请求且丢弃未完成事务；集成规范需保证上游按 AXI 复位语义重试。 |
| 是否需要对 `err_cause_sticky` 做芯片级状态采集 | 当前通过顶层 sideband 输出观测，不占用 64 KiB aperture；若需 AXI 可读状态窗口，将是新增地址空间的规格变更。 |

在以上 TBD 冻结前，不应将本文转换为 RTL 或为特定 FPGA part 锁定实现。
