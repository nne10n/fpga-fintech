# 一维卷积神经网络（1D-CNN）FPGA 加速器
## Phase 1 — 系统架构说明书

| 项目 | 内容 |
| --- | --- |
| 文档编号 | QDR-1DCNN-FPGA-ARCH-P1 |
| 版本 / 状态 | **V1.0 待签核** |
| 编写日期 | 2026-10-17（Asia/Shanghai） |
| 上游 | `Phase0-FPGA需求规格书-定稿.md` V1.0 |
| 下游 | `Phase1-模块微架构设计.md`、两路独立实施 |
| 器件 | XC7Z020 级别；ZYNQ7020 + AD7606 级 |

---

## 1. 架构目标与原则

1. **PS/PL 分工清晰**：PL 热路径做采集→预处理→窗切分→INT16 推理；PS 做配置、权重加载、投票告警、上报落盘。
2. **权重常驻 BRAM，层间不回 DDR**：仅输入窗与分数向量跨 PS–PL（或 ADC→PL）。
3. **weight-stationary + M 并行 + K 展开**：匹配 7 系列 1 MAC/DSP/周期。
4. **接口契约优先**：两名实施者互不通气时，仅凭本架构 + 微架构文档即可产出兼容 IP。
5. **V1 降重叠**：性能承诺 ≥2 窗/秒无重叠；50% 重叠不承诺；瘦网络/多引擎为挂钩扩展。
6. **BRAM ≤70% 硬预算**；单套权重；热切换仅预留接口。

---

## 2. 系统上下文

```
                 ┌─────────────────────────────────────────────────────────┐
  振动传感器 ×2  │  AD7606 级子卡          ZYNQ7020 (XC7Z020)               │
  ──────────────►│  SPI/并行 ──► PL: adc_frontend → preprocess_fir          │
                 │                    → window_buffer → cnn_engine         │
                 │                    → score_path                          │
                 │              AXI-Stream / 内部流                          │
                 │              ▲ AXI-Lite (axi_ctrl)                        │
                 │              │ weight_mem ← PS DMA/拷贝加载               │
                 │              ▼                                            │
                 │           PS: Linux — 驱动、投票、MQTT/REST、落盘、健康监控 │
                 └─────────────────────────────────────────────────────────┘
```

**数据流单向主路径（V1）：** ADC → adc_frontend → preprocess_fir → window_buffer → cnn_engine ↔ weight_mem → score_path → ps_handoff → PS 应用。

**控制流：** PS 经 AXI-Lite 写使能、窗参、权重基址/加载触发、旁路位；读状态与计数器。

---

## 3. 模块层级

### 3.1 层级图

```
system_1dcnn_node
├── PL subsystem: pl_infer_pipeline
│   ├── adc_frontend          # AD7606 适配 + CDC FIFO
│   ├── preprocess_fir        # DC 去除 + FIR（可旁路）
│   ├── window_buffer         # 可编程窗长/重叠；V1 默认 overlap=0
│   ├── cnn_engine            # 参数化 1D-CNN 核心
│   ├── weight_mem            # 单套 INT16 权重 BRAM + 加载口
│   ├── axi_ctrl              # AXI-Lite 寄存器文件
│   └── score_path            # 分数向量打包 + 可选 DMA/IRQ
└── PS subsystem: ps_runtime
    ├── weight_loader         # 从 SD/QSPI → weight_mem
    ├── ps_handoff / driver   # mmap 寄存器 + 分数读取
    ├── vote_alarm            # FR-09
    └── uplink_store          # FR-08
```

### 3.2 模块职责一览

| 模块 | 所属 | 职责摘要 | 风险等级 |
| --- | --- | --- | --- |
| adc_frontend | PL | 协议适配、采样对齐、异步 FIFO、溢出检测 | 中（CDC） |
| preprocess_fir | PL | DC / FIR，旁路直通 | 低 |
| window_buffer | PL | 环形/双缓冲切窗，overlap 可编程 | 中（地址算） |
| cnn_engine | PL | 卷积流水、ReLU/Pool/GAP/FC | **高** |
| weight_mem | PL | 权重存储与加载；热切换预留 | 中（BRAM） |
| axi_ctrl | PL | 寄存器 map、软复位、IRQ | 低 |
| score_path | PL | 输出 AXIS/FIFO → PS | 低 |
| ps_handoff | PS/边界 | 驱动契约、投票边界 | 中（SW） |

---

## 4. 时钟与复位架构

### 4.1 时钟域

| 域名 | 典型频率 | 来源 | 用途 |
| --- | --- | --- | --- |
| `clk_adc` | 由 AD7606 转换时序派生（或板载晶振分频） | 外部 / PL MMCM | adc_frontend 采样侧 |
| `clk_pl` | **100–150 MHz**（目标 150 MHz，底线 100） | PS FCLK0 或 PL MMCM | 预处理、窗、CNN、权重、AXI 从机逻辑 |
| `clk_axi` | 与 `clk_pl` 同相或同源 | AXI GP 时钟 | axi_ctrl；若与 clk_pl 同源可合并为单域 |
| `clk_ps` | Cortex-A9 域 | PS 内部 | 驱动与应用（不进 PL 时序） |

**V1 推荐简化：** 将 preprocess / window / cnn / weight / score / axi 全部置于 **`clk_pl` 单域**；仅 `adc_frontend` 存在 `clk_adc` ↔ `clk_pl` 的 CDC。

### 4.2 复位

| 复位名 | 极性 | 类型 | 作用范围 |
| --- | --- | --- | --- |
| `rst_pl_n` | **低有效** | 异步断言、同步释放（在 clk_pl） | 全 PL 同步逻辑 |
| `soft_rst` | 高有效（寄存器位） | 同步，经 axi_ctrl | 流水线清空、计数器清零；**不清权重 BRAM**（除非另有 `weight_clear`） |
| `rst_adc_n` | 低有效 | 在 clk_adc 同步释放 | adc 侧状态机与 FIFO 写侧 |

上电顺序建议：PS 启动 → 配置 PL → 释放 `rst_pl_n` → 加载权重 → 配置窗参 → 使能采集与推理。

### 4.3 CDC 清单（完整）

| # | 路径 | 源域 | 目的域 | 机制 | 备注 |
| --- | --- | --- | --- | --- | --- |
| CDC-01 | ADC 采样数据 | clk_adc | clk_pl | **异步 FIFO**（FWFT，深度≥16，可配至 256） | 每通道独立或打包宽字；必须有 almost_full→停采/丢弃策略可配置 |
| CDC-02 | ADC 溢出/状态标志 | clk_adc | clk_pl | 2FF 同步或 FIFO 侧带状态字 | 粘滞错误位经 axi_ctrl 可见 |
| CDC-03 | AXI-Lite 写/读 | clk_axi / PS | clk_pl | 若时钟同源则无 CDC；不同源则用 Xilinx AXI clock converter | V1 优先同源 |
| CDC-04 | score → PS | clk_pl | PS | AXI-HP/DMA 或 GP 轮询 FIFO；跨时钟用 DMA 官方路径或 BRAM 双口+中断 | 推荐：AXIS → AXI-DMA → DDR，再由 PS 读 |
| CDC-05 | 中断 `irq_score` | clk_pl | PS | 电平/脉冲经 PS IRQ，满足 UG585 同步要求 | 脉冲宽 ≥2 clk_pl |

**禁止：** 在 clk_adc 与 clk_pl 之间对多 bit 计数器直接 2FF；必须用 Gray 码或 FIFO。

---

## 5. 接口契约总表

### 5.1 顶层端口（逻辑视图）

| 端口组 | 方向 | 协议 | 位宽/要点 |
| --- | --- | --- | --- |
| ADC 物理 | in | SPI 或并行（参数 `ADC_IF_TYPE`） | 16-bit × 2ch 同步 |
| `s_axi_*` | slave | **AXI4-Lite** | 32-bit data；地址空间见 §5.3 |
| `m_axis_score_*` | master | **AXI4-Stream** | `TDATA` 至少 32-bit（打包 INT16 分数或 INT32）；`TVALID/TREADY/TLAST` |
| `m_axi_weight_*` 或内部 load port | optional master/slave | 权重加载 | V1：PS 经 Lite 字写或 DMA→weight_mem；微架构定一种主路径并保留另一种预留 |
| clocks/resets | in | — | clk_pl, rst_pl_n, clk_adc, rst_adc_n |
| `irq_pl` | out | 电平/脉冲 | 窗完成 / 错误 |

### 5.2 内部 AXI-Stream 链路契约

**统一约定（两实施者必须一致）：**

| 属性 | 约定 |
| --- | --- |
| 激活样点 | **INT16**，two's complement |
| 握手 | 标准 AXIS：`TVALID`/`TREADY`；传输当拍双方同高 |
| 打包 | 单通道流：每拍 1 个 INT16（`TDATA[15:0]`）；双通道可选 `TDATA[31:0]={ch1,ch0}`，由参数 `PACK_CH` 选择，**默认 V1：`PACK_CH=0` 单流（通道选择寄存器）** |
| `TLAST` | 窗边界：每个完整窗最后一个样点拉高 |
| `TUSER` | 可选：窗序号[15:0]、通道 ID[7:0]；宽度固定 24-bit，未用填 0 |
| 背压 | 下游 `TREADY=0` 时上游必须停；window_buffer 不得在背压下覆盖未读窗（溢出置错） |

链路命名：

```
adc_frontend.m_axis     → preprocess_fir.s_axis
preprocess_fir.m_axis   → window_buffer.s_axis
window_buffer.m_axis    → cnn_engine.s_axis_act
cnn_engine.m_axis_score → score_path.s_axis
score_path.m_axis       → (DMA / PS)
```

### 5.3 AXI-Lite 寄存器 Map（axi_ctrl）基址相对 0x0000

**字地址，32-bit，小端；未列位为保留写忽略读 0。**

| 偏移 | 名称 | R/W | 复位值 | 说明 |
| --- | --- | --- | --- | --- |
| 0x000 | `REG_ID` | RO | 0x1DCN0101 | Magic + 版本 |
| 0x004 | `REG_CTRL` | RW | 0 | [0] eng_en [1] capt_en [2] soft_rst [3] fir_bypass [4] irq_en [8] weight_load_kick（脉冲） |
| 0x008 | `REG_STATUS` | RO | 0 | [0] busy [1] done_sticky [2] err_sticky [3] fifo_ovfl [4] weight_ok |
| 0x00C | `REG_IER` / 清断 | RW1C | 0 | 写 1 清对应 STATUS sticky |
| 0x010 | `REG_WIN_LEN` | RW | 2048 | 合法：1024/2048/4096 |
| 0x014 | `REG_WIN_HOP` | RW | 2048 | hop=len→无重叠；hop=len/2→50%；V1 性能承诺仅 hop=len |
| 0x018 | `REG_FS_SEL` | RW | 1 | 0=12.8k 1=25.6k（前端分频/配置） |
| 0x01C | `REG_CH_SEL` | RW | 0 | 通道选择 / 使能 mask（V1：bit0/1） |
| 0x020 | `REG_WEIGHT_BASE` | RW | 0 | PS 侧镜像基址或加载源标识（预留） |
| 0x024 | `REG_WEIGHT_WORDS` | RW | 0 | 加载字数（INT16 计） |
| 0x028 | `REG_WEIGHT_CTRL` | RW | 0 | [0] load_en [1] **bank_sel（预留热切换）** [2] bank_active_ro 映射到 STATUS |
| 0x02C | `REG_WEIGHT_DATA` | WO | — | 可选：字写入权重端口（若不用 DMA） |
| 0x030 | `REG_CYC_CNT` | RO | 0 | 最近一窗推理周期数（clk_pl） |
| 0x034 | `REG_WIN_CNT` | RO | 0 | 累计完成窗数 |
| 0x038 | `REG_ERR_CODE` | RO | 0 | 错误码（见微架构） |
| 0x03C | `REG_IRQ_STATUS` | RO | 0 | 中断源 |
| 0x040 | `REG_SCORE_BASE` | RW | 0 | 分数 DDR 缓冲地址（若 DMA）预留 |
| 0x044–0x07C | `REG_RSVD_*` | RW | 0 | **热切换与多引擎扩展预留** |
| 0x080–0x0A4 | `REG_SCORE0..9` | RO | 0 | 可选：最近窗 10 类 INT16/INT32 分数快照 |

**热切换预留（F0-2）：** `bank_sel`、第二套 `WEIGHT_BASE_B`（放在 RSVD）、`bank_active` 只读位必须存在于文档与头文件；V1 硬件可仅实现 bank0，写 bank_sel=1 时置 `err` 或忽略并置「未实现」状态位 `STATUS[5]=feat_hotswap=0`。

### 5.4 复位极性与默认

- 所有模块用户逻辑：`rst_n` **低有效**。
- AXIS 复位后：`TVALID=0`。
- 寄存器复位值见表；`soft_rst` 不改变 `REG_ID` 与权重内容。

---

## 6. 存储与带宽架构

### 6.1 片上存储分配（对应 NFR-06）

| 块 | 估计 | 宿主模块 |
| --- | --- | --- |
| 权重 + scale 元数据 | ≤80 KB | weight_mem |
| 层间双缓冲特征 | ≤260 KB | cnn_engine |
| 输入环形 + 暂存 | ≤64 KB | window_buffer / adc FIFO |
| 行缓存 k≤16 | ≤32 KB | cnn_engine |
| **合计** | **≤440 KB** | |

### 6.2 跨边界带宽

- 输入：2×25.6 kSPS ×2B ≈ 100 KB/s → 远低于 AXI-HP。
- 分数：10×2B ×2 窗/s ≈ 40 B/s → 可轮询。
- 权重加载：58 KB / <100 ms → <0.6 MB/s → GP 字写或一次 DMA 即可。

**结论：** V1 无 DDR 带宽风险；风险在 BRAM 布局与 CNN 调度。

---

## 7. 控制与数据流时序（文字）

### 7.1 单窗推理（无重叠）

1. PS 写窗参、旁路、使能 `capt_en`/`eng_en`。
2. adc_frontend 持续推样点；preprocess 输出 AXIS。
3. window_buffer 累计 `WIN_LEN` 点后拉 `TLAST`，输出一窗并可选继续填下一窗（hop=`WIN_LEN` 时无重叠拷贝）。
4. cnn_engine 收齐窗后 `busy=1`，按层计算，结束时 `m_axis_score` 输出 10 类 + `TLAST`，`CYC_CNT` 更新，`done_sticky=1`，可选 IRQ。
5. score_path 交付 PS；PS 投票（FR-09）后告警。

### 7.2 背压与实时性

- V1 ≥2 窗/s：窗采集期 2048/25600 ≈ **80 ms**；推理预算 ≤1 ms（底线）远小于采集期 → **单引擎足够**，流水气泡可接受。
- 若 `cnn_engine` 背压导致 window 溢出 → `fifo_ovfl`/`err`，不得静默丢窗而不置位。

---

## 8. 风险模块与缓解

| 模块 | 风险 | 缓解 |
| --- | --- | --- |
| cnn_engine | II/延迟不达标；BRAM 超支 | M2 用 csyn 冻结并行度 M；tile 降档预案 |
| weight_mem | 位宽/排布与训练导出不一致 | **统一权重文件布局契约**（见微架构 §weight_mem） |
| window_buffer | hop/len 非法组合 | 寄存器写入校验 + err_code |
| adc_frontend | CDC 亚稳/溢出 | 异步 FIFO + 粘滞状态；30 min 丢样测试 |
| 量化一致性 | bit-exact 失败 | 统一 scale 应用顺序与饱和规则 |

---

## 9. 扩展挂钩（不进 V1 实施范围）

### 9.1 瘦网络扩展

- 挂钩点：`cnn_engine` 顶层参数 `N_LAYERS / C_OUT[] / K[] / STRIDE[]`；权重体积缩小。
- 寄存器：`REG_NET_PROFILE`（RSVD）选择 profile ID。
- 验收：同接口契约，换权重与参数即可。

### 9.2 多引擎扩展

- 挂钩点：实例化 N 路 `cnn_engine` + 通道调度器；`REG_ENGINE_MASK`。
- 权重：共享 weight_mem（只读多口）或复制（BRAM 翻倍 → **须重签 NFR-06**）。
- 用途：提高重叠窗吞吐，而非 V1 必需。

### 9.3 双套热切换（FR-07 功能）

- 挂钩点：weight_mem 双 bank；`bank_sel`；切换时不停 `capt_en`。
- V1：仅寄存器与软件路径预留，`feat_hotswap=0`。

---

## 10. 软件 / PS 边界（ps_handoff）

| 项 | 契约 |
| --- | --- |
| 驱动 | UIO 或平台驱动 mmap AXI-Lite；可选 DMA 引擎绑 score AXIS |
| 启动序 | 见 §4.2；权重加载完成后 `weight_ok=1` 才允许 `eng_en` |
| 分数 | 优先读 `REG_SCORE0..9` 快照 **或** DMA buffer；两种实施须支持至少一种，文档声明 |
| 投票 | **纯 PS**：连续 N 窗 argmax 相同才告警；N 与阈值可配文件 |
| 工况标签 | PS 侧附加（FR-13），不进 PL |

---

## 11. 架构签核检查表

| # | 检查项 | 状态 |
| --- | --- | --- |
| A1 | 模块层级完整且与微架构模块一一对应 | 是 |
| A2 | 时钟/复位极性明确 | 是 |
| A3 | CDC 清单无遗漏（含 IRQ） | 是 |
| A4 | AXIS/Lite 契约位宽与握手写明 | 是 |
| A5 | 寄存器 map 含热切换预留 | 是 |
| A6 | BRAM≤70% 预算表 | 是 |
| A7 | V1 不做 50% 重叠承诺已写明 | 是 |
| A8 | 扩展挂钩不污染 V1 范围 | 是 |

**建议签核结论：** **PASS（建议用户确认后生效）** — 条件：确认 V1 默认 `PACK_CH=0`（单通道流入 CNN）及分数交付方式优先「寄存器快照 + 可选 DMA」。

---

## 12. 修订历史

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| V1.0 | 2026-10-17 | 首版架构；对齐 Phase0 冻结项 |

> **Phase 1 签核：PASS**（用户确认接受文档默认；2026-10-17 13:51 Asia/Shanghai）。可按 HANDOFF 分派双路隔离实施。
