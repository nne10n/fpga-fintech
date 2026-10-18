# 1D-CNN FPGA — 实施交接约束（双路独立对照）

| 项目 | 内容 |
| --- | --- |
| 文档编号 | QDR-1DCNN-FPGA-HANDOFF |
| 版本 | V1.0 |
| 日期 | 2026-10-17（Asia/Shanghai） |
| 主理人 | 文档作者 / 签核方 |
| 实施方 | **实施者 A：zcoder(glm5.3)**；**实施者 B：zcoder(deepseek)** |
| 目的 | 在**相同文档约束**下独立落地，禁止横向交流，以便对比产物质量 |

---

## 1. 必须遵守的同一文档集（只读基线）

实施开始前，双方各自独立阅读并仅依据下列文件（版本以路径内容为准）：

| # | 绝对路径 | 角色 |
| --- | --- | --- |
| 1 | `/workspace/1dcnn-fpga/docs/Phase0-FPGA需求规格书-定稿.md` | 需求与冻结项 |
| 2 | `/workspace/1dcnn-fpga/docs/Phase1-系统架构说明书.md` | 系统架构、CDC、寄存器 map |
| 3 | `/workspace/1dcnn-fpga/docs/Phase1-模块微架构设计.md` | 模块契约与测试向量约定 |
| 4 | `/workspace/1dcnn-fpga/docs/1dcnn-fpga-立项背景与需求说明书.md` | 背景参考（冲突时以 Phase0/1 定稿为准） |
| 5 | 本文件 `HANDOFF-实施约束.md` | 协作与交付约束 |

**冲突裁决优先级：** HANDOFF 协作规则 > Phase0 冻结项 > Phase1 微架构接口契约 > Phase1 架构 > 立项背景书。

---

## 2. 禁止横向交流（强制）

1. 实施者 A 与实施者 B **不得**交换：源码、中间设计、参数扫结果、私有测试向量、问题解答、口头约定。
2. 疑问只能向**主理人**提出；主理人若修订文档，必须以**书面修订同一文档集**方式通知双方，不得只答复单方。
3. 不得阅读对方工作区目录；工作区必须物理隔离，建议路径：
   - A：`/workspace/1dcnn-fpga/impl-glm53/`
   - B：`/workspace/1dcnn-fpga/impl-deepseek/`
4. 共享只读区：`/workspace/1dcnn-fpga/docs/` 与（若有）`/workspace/1dcnn-fpga/golden/` 黄金向量（由主理人/算法侧放置）。

违反本条的产物不进入质量对照评分。

---

## 3. 实施范围（V1）

### 3.1 必须做

- 模块：`adc_frontend`, `preprocess_fir`, `window_buffer`, `cnn_engine`, `weight_mem`, `axi_ctrl`, `score_path`（及 PS 侧 `ps_handoff` 最小驱动/投票骨架）。
- 路线：Vitis HLS 参数化 INT16 IP + 必要 RTL 粘合（前端 PHY 可用 RTL）。
- 基线网络 §4.2；BN 训练侧已融合假设。
- 单套权重 + 热切换**接口预留**（寄存器位存在，`feat_hotswap=0`）。
- 性能承诺：NFR-01 基线 ≤500 μs；NFR-02 ≥2 窗/s（无重叠）；BRAM ≤70%。

### 3.2 明确不做（写入非目标即可）

- 50% 重叠连续实时推理承诺。
- 双套权重常驻与热切换功能。
- 瘦网络替换、多引擎实例化（可留参数挂钩，勿当 V1 交付）。
- 完整云平台、EMC、DPU/FINN 实现。

---

## 4. 禁止改动的接口约定（破坏即不合格）

下列内容**未经主理人改文档并通知双方前不得变更**：

| 类别 | 冻结内容 |
| --- | --- |
| 寄存器 | Phase1 架构书 §5.3 偏移、位域、ID=`0x1DCN0101` |
| AXIS | INT16 激活；valid/ready；窗 TLAST 在 window→cnn；分数 **10 拍** + 末拍 TLAST |
| 量化顺序 | 先 MAC→scale/shift→饱和 INT16→ReLU（见微架构 §0.3） |
| 权重布局 | 必须遵循同一 `weight_map.json` / 导出脚本；禁止私有重排 |
| 复位 | `rst_n` 低有效 |
| 时钟 | 热路径单 `clk_pl`；ADC 异步 FIFO CDC |
| 错误码 | 微架构 §8 表 |
| 分数交付 | 至少实现 `REG_SCORE0..9` 快照 |

允许差异化的部分：HLS 内并行度扫参、FIR 微结构、ADC SPI vs 并行具体状态机编码、DMA 可选路径是否启用（寄存器快照为必选）。

---

## 5. 交付物清单（每路实施者各自提交）

在各自 `impl-*` 根目录提交：

```
impl-<name>/
├── README.md                 # 构建步骤、工具版本、如何跑 csim
├── include/regs.h            # 必须与冻结 map 一致
├── hls/                      # CNN 及相关 HLS 源与 tcl
├── rtl/                      # 前端/粘合 RTL（若有）
├── tb/                       # 测试平台
├── vectors/                  # csim 用向量（或指向 golden 的说明）
├── reports/
│   ├── hls_csynth_summary.md # II/latency/资源
│   ├── resource_estimate.md  # BRAM/DSP/LUT/FF 对照 NFR-06 表
│   └── bitexact_result.md    # 32 组比对结果
└── ps/
    ├── driver/               # 最小 mmap/UIO
    └── vote_alarm.c          # FR-09 骨架
```

### 5.1 源码树

- 可综合/可 csim；目录清晰；无秘密密钥、无 API key。
- 顶层模块名建议：`system_1dcnn_pl`（可不同，但 README 声明）。

### 5.2 csim 向量

- ≥32 组；含全零/饱和/随机/至少 1 组真实窗。
- 顶层 0-bit 对齐定点黄金分数；报告通过数/失败 ID。

### 5.3 资源估计表

必须包含（可综合后填实测，综前填估计并标注）：

| 资源 | 预算 | 本实现 |
| --- | --- | --- |
| BRAM | ≤70%（≤440KB） | |
| LUT | ≤40% | |
| DSP | ≤30%（≤66） | |
| 估计窗延迟 | ≤500 μs | |

---

## 6. 验收与对照评分（主理人用）

| 维度 | 权重建议 | 说明 |
| --- | --- | --- |
| 接口合规 | 高 | regs.h / AXIS / 权重布局 |
| bit-exact | 高 | 0-bit 通过率 |
| 资源 | 高 | BRAM 优先 |
| 延迟 | 中 | NFR-01 |
| 代码清晰与可复现 | 中 | README / 脚本 |
| 超范围改接口 | 一票否决 | |

两路均未完成时，不比较相对质量，只记各自完成度。

---

## 7. 签核与问题升级

1. 实施中发现文档矛盾：停改接口，向主理人提单 → 文档修订 → 双方同步新版本。  
2. 不得「临时私有约定」绕过文档。  
3. Phase 2 起按 FPGA skill 逐级仿真签核；无证据不通过。

---

## 8. 主理人交接检查表

| # | 项 | 状态 |
| --- | --- | --- |
| H1 | Phase0/1 四份文档已落盘 | 是（本交接时） |
| H2 | 冻结项 F0-1..5 已写入 Phase0 | 是 |
| H3 | 双路隔离路径已规定 | 是 |
| H4 | 禁止改动的接口表已列出 | 是 |
| H5 | 交付物清单完整 | 是 |

---

## 9. 修订历史

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| V1.0 | 2026-10-17 | 首版交接约束 |

## 实施语言约束（2026-10-17 重发）

用户重发方案要求：

1. **必须使用** FPGA 全流程 skill（`/home/box/agent-data/workflows/fpga/SKILL.md`）及相关 RTL 风格 skill。
2. **交付主体为可综合 Verilog / SystemVerilog**；Vitis HLS C++ 不得作为本轮交付主体（可移入 `_legacy_hls/` 仅作对照）。
3. 其余隔离规则、文档优先级、冻结项不变。

## 可综合性约束（2026-10-17）

交付 RTL **必须可综合**（面向 Vivado / 综合工具）：

1. 禁止用 `task`/`function` 内嵌套多层 `for` 在单拍内完成整网推理冒充计算通路。
2. 卷积/池化/GAP/FC 须为显式 FSM + 寄存器数据通路（PE/累加器/地址发生器），周期行为可仿真度量。
3. 仿真 bit-exact 通过 **不能** 替代可综合性；行为级整网模型仅可放 `_behavioral/` 作对照，不得作为 DUT 交付主体。
4. 允许的 SV 子集：`always_ff` / `always_comb`、同步复位 `sys_rst_n`、参数化；避免综合不友好的动态结构。

