# 一维卷积神经网络（1D-CNN）FPGA 加速器示例工程
## 立项背景与需求说明书（V1.0 草案）

| 项目 | 内容 |
| --- | --- |
| 文档编号 | QDR-1DCNN-FPGA-001 |
| 版本 / 状态 | V1.0 草案（待评审） |
| 编写日期 | 2026-10-17 |
| 目标读者 | 算法工程师、FPGA/嵌入式工程师、项目决策者 |
| 场景定位 | 工业时序信号（振动 / 电流）在线监测与故障诊断 |
| 平台定位 | AMD Zynq-7000（低成本，XC7Z020 级别） |
| 交付形态 | 立项文档 + 需求规格；代码骨架在本阶段仅给出接口约定与关键伪代码，不要求可综合 |

---

## 1. 背景与动机

### 1.1 业务问题

旋转机械（电机、泵、风机、齿轮箱）的故障诊断正在从"定期巡检 + 离线分析"转向"在线监测 + 边缘实时判定"。当前主流做法是把采集数据上传到网关或云端，用 1D-CNN 等深度模型做分类。该方案在工业现场有三类难以回避的问题：

第一是**确定性延迟与带宽成本**。振动通道典型采样率 12.8–25.6 kHz，多通道长期上传对现场网络（尤其无线/窄带）压力大；一旦断链，监测与保护功能同时失效。第二是**数据出厂区受限**，工艺与设备状态数据往往涉及保密要求。第三是**云端推理的能耗与运维成本**，在测点数量多的产线上会随规模线性增长。

因此需要把推理下沉到采集侧，形成"传感—预处理—推理—告警"闭环的边缘节点。这带来核心矛盾：模型侧是浮点、动态范围大、算子密集的 1D-CNN；边缘侧要求微秒到毫秒级固定延迟、瓦级功耗、离线自治和可长期供货的器件。

### 1.2 为什么选 FPGA（相对 MCU / NPU / GPU）

| 方案 | 延迟确定性 | 功耗 | 单点成本 | 可编程/演进 | 适配本项目 |
| --- | --- | --- | --- | --- | --- |
| MCU（Cortex-M4/M7 + CMSIS-NN） | 中（ms 级抖动） | 极低 | 低 | 软件 | 轻量模型可行，扩展多通道/更高采样率时算力不足 |
| 专用 NPU SoC（如端侧 AI 芯片） | 高 | 低 | 低 | 受限（算子白名单） | 1D-CNN 非常规网络常被拒；无法自定义预处理流水线 |
| 边缘 GPU / Jetson | 低（ms–十 ms） | 高（5–15 W） | 高 | 软件 | 单测点过度设计，散热与供电要求高 |
| Zynq-7000 SoC FPGA | 高（硬件流水，固定周期） | 中低（0.5–2 W 逻辑侧） | 中（板卡 ¥1k–2k） | 强（PL 可重构 + PS 跑 Linux） | **本项目的选型目标** |

Zynq-7000 的价值不在于"算力最大"，而在于**PS（ARM 双核，跑采集、协议、存储）+ PL（硬件流水，做定长推理与实时预处理）在同一颗芯片、同一时钟域内协同**，同时避免了外挂 PCIe、跨芯片 DMA 与文件系统一致性等工程复杂度；器件为成熟量产型号，供货与长期可维护性优于新起 AI 芯片。

### 1.3 为什么以"示例工程"形式立项

一是团队内在 HLS/AXI 流水化与定点量化上的能力参差不齐，需要一个贯穿"PyTorch 训练 → 量化 → HLS 加速器 → PS 驱动 → 上板评测"的完整可复用范例；二是形成一条**可迁移的工程模板**——换网络结构、换传感器接口时只需改参数与前端，不必重做体系。后续实际产品（如多通道振动监测节点）在此模板上做定制即可。

---

## 2. 技术路线调研结论

### 2.1 学界与工业界的实现现状（要点）

轻量 1D-CNN + FPGA 的组合在 ECG 心律分类、轴承/齿轮故障诊断上已有较多公开实现，共同特征明显：网络深度 3–8 层、卷积核长度 3–16、输入窗 187–2048 点、参数量在 2.8K–75K 级；片上单窗延迟从数微秒到 60+ 毫秒不等（取决于并行度与是否含软件预处理），LUT/BRAM 占用差异极大，功耗普遍落在 0.3–2 W。例如面向 ECG 的 1D-CNN 加速器在保持 99% 级软件精度的前提下做模型压缩后上 FPGA 实现实时心律分类（[Interface Comput 2025](https://dl.acm.org/doi/abs/10.1007/s11554-025-01642-w)）；一维深度可分离卷积网络（DSC-CNN，核长 7、输入 1600 点、约 1.1 万参数、DoReFa 量化）在 FPGA 上以 50 MHz 运行、功耗约 527 mW、准确率 96.12%（[MDPI Sensors 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11644920/)）；面向 CWRU 轴承的轻量可部署网络 BearingPGA-Net 在 Kintex-7 上用动态定点量化把模型压到约 2.8K 参数、平均 F1 > 98%（[arXiv 2307.16363](https://arxiv.org/pdf/2307.16363)、[代码](https://github.com/asdvfghg/BearingPGA-Net)）；HLS 参数化卷积加速器模板也被证明可在小面积上兼顾吞吐（[arXiv 2602.04044](https://arxiv.org/html/2602.04044v1)）。

这些工作的共性经验有五条，其中第 1、5 条直接影响本项目的指标设定：

1. **瓶颈是 BRAM 容量，不是 DSP。** XC7Z020 只有 140×36 Kb = 4.9 Mb ≈ **630 KB** BRAM。公开实现普遍先撞 BRAM：7Z020 上 INT16 YOLOv2 用掉 **70.0% BRAM / 57.3% DSP**（[Sensors 25(20):6359](https://pmc.ncbi.nlm.nih.gov/articles/PMC12568313/)）；7Z020 上 LeNet 与 CIFAR CNN 的 HLS 实现 **BRAM 均 100% 饱和**（[JESA 59(1) 2026](https://doi.org/10.18280/jesa.590115)）；BearingPGA-Net 在 LUT 容量为其 4 倍的 Kintex-7 上 BRAM 仍占 58.2%。
2. **网络量级可以非常小。** CWRU 上 2.8K–75K 参数、35K–800K MAC 即可达 >98% F1（BearingPGA-Net 2.83K 参数 / ≈39K MAC / F1 99.08；KDSCNN 5.89K 参数 / ≈35K MAC；WDCNN 66.79K 参数 / ≈0.81M MAC / F1 98.39）。
3. **7Z020 上已有同行评审的 1D-CNN 实现，但集中在生理信号**：Liu 等（[JRTIP 2025](https://doi.org/10.1007/s11554-025-01642-w)，HLS，13,726 LUT / 9 DSP / 5.5 BRAM @50 MHz，63 ms/次，软件 99.59%→片上 96.55%）；Fradi 等（[TechSci 2024](https://doi.org/10.18280/ts.410114)，Pynq-Z2，8 层 1D-CNN、187×1 输入，MIT-BIH 99.03%，仅 1,477 LUT(2.78%) / 3 DSP(1.36%)，1.8–7 ms/信号，比 ARM 软实现约 10×）。**"振动/电流 + XC7Z020"这一具体组合尚无同行评审基线**，本工程的差异化价值正在此处。
4. **精度损失可控但有前提**：16-bit 定点在 7 系列上损失极小（YOLOv2 −0.2%；BearingPGA 32→16 bit F1 97.39→97.12，−0.27 pp）；低比特必须配合重训练/QAT，DoReFa 不重训练会掉 3.8 pp（[Sensors 24(23):7831](https://doi.org/10.3390/s24237831)），剪枝+INQ 掉 3.04 pp（Liu）。**CWRU 上纯 INT8 的逐位宽精度扫描：未见公开数据。**
5. **免乘法路线在 7 系列上有实证吸引力**：把权重量化为 2 的幂可用移位代替乘法，CWRU 10 类实现用掉 **0 片 DSP**、9,689 LUT / 8.5 BRAM、权重位宽总量 −87.5%、功耗 342–616 mW（[Sensors 23(23):9437](https://doi.org/10.3390/s23239437)）；二值化 DSC 在 Cyclone V 上做到 0 DSP、617 nJ/次（[Sensors 24(22):7207](https://doi.org/10.3390/s24227207)）。

### 2.1.1 公开实现对标表（用于指标合理性论证）

| 文献 | 器件 | 网络 | 数据 | 精度（软件→片上） | 资源 | 时钟 / 延迟 | 功耗 | 数据类型 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [JRTIP 2025](https://doi.org/10.1007/s11554-025-01642-w) | **XC7Z020** | LW-1D-CNN（残差+DSC，HLS） | 心律失常 | 99.59→96.55% | 13,726 LUT / 9 DSP / 5.5 BRAM | 50 MHz / 63 ms | 1.78 W | 剪枝+INQ |
| [TechSci 2024](https://doi.org/10.18280/ts.410114) | **XC7Z020**(Pynq-Z2) | 8×Conv1D(16f) + 2 FC，输入 187 | MIT-BIH | 99.03%（ARM 98.39%） | 1,477 LUT(2.8%) / 3 DSP(1.4%) | — / 1.8–7 ms | 未报告 | PS+PL 协同 |
| [Sensors 2025 20:6359](https://pmc.ncbi.nlm.nih.gov/articles/PMC12568313/) | **XC7Z020** | YOLOv2（2D，资源标定参照） | 交通目标 | −0.2% vs FP32 | LUT 49.2% / **BRAM 70.0%** / DSP 57.3% | 100 MHz | 未报告 | INT16（1 MAC/DSP） |
| [JESA 2026](https://doi.org/10.18280/jesa.590115) | **XC7Z020**(Pynq-Z1) | LeNet / CIFAR CNN（HLS） | MNIST/CIFAR | 98.33% / 74–75.2% | LUT 66–67% / **BRAM 100%** | 150–266 FPS | 0.57 / 0.86 W | 16-bit 定点 |
| [Redalyc 2020](https://www.redalyc.org/journal/911/91164537008/html/) | **XC7Z020**(Arty Z7-20) | LeNet-5 | MNIST | 97.59% | 153 DSP | 100 MHz / 441 图/秒 | 未报告 | 12-bit 定点 |
| [arXiv 2307.16363](https://arxiv.org/abs/2307.16363) | Kintex-7 XC7K325T | FFT 前端 + 单层 1D-CNN | CWRU/HIT | F1 99.08 / 97.12(16bit) | LUT 74.4% / DSP 22.0% / BRAM 58.2% | 100 MHz / 1000 窗 5.77 μs（原文口径，量纲存疑） | 0.67 W | 32→16 bit |
| [Sensors 2024 23:7831](https://doi.org/10.3390/s24237831) | Virtex-7 VC707 | 1D-DSC，核 7，输入 1600 | PU 电流 | 98.27→96.12% | 片上存储 774 Kb | 50 MHz / ≈10.5 ms | 527 mW | DoReFa + 分级定点 |
| [Sensors 2023 23:9437](https://doi.org/10.3390/s23239437) | VC707 | 免乘法 1D/2D CNN | CWRU 10 类 | 97.16→95.12% | 9,689 LUT / **0 DSP** / 8.5 BRAM | 5 / 140 MHz | 342 / 616 mW | 权重 2^k |

**结论**：同量级轻量 1D-CNN 折算到 XC7Z020，工程上可实现的合理落点是 **单窗 0.5–5 ms、功耗 <1.5 W、LUT <50%、BRAM <80%、DSP <60%**；本文 §3.2 的指标据此设定，而非照搬上述文献的绝对值（器件与网络均不同）。

### 2.2 可选实现路线对比

| 路线 | 优点 | 缺点 / 风险 | 典型资源与性能 | Zynq-7000 可得性 | 工具链风险 |
| --- | --- | --- | --- | --- | --- |
| A. 纯 RTL 手写 | 完全可控、面积/延迟最优、可深度定制前端 | 开发周期长、验证成本高、改网络要重做 | 视规模，单核卷积 30–100 DSP | ✅ 无限制 | 低 |
| **B. Vitis HLS 自定义 1D-CNN IP（选定）** | C++ 快速迭代、`PIPELINE/DATAFLOW/ARRAY_PARTITION` 足以拿到好结果、易做 bit-exact 验证 | 需自己设计调度与存储层次、超深网络效率下降 | 40–120 DSP、100–150 MHz、数十至数百 μs/窗 | ✅ 支持 7 系列 | 低（Vivado/Vitis HLS 长期支持 7 系列） |
| C. Vitis AI DPU | 官方端到端量化部署、软件栈成熟 | **不支持 Zynq-7000**（仅 UltraScale+/Versal）；Conv1d 需改写为 Conv2d(H=1)/FC；小通道 1D 网络 DPU 利用率低 | B 系列 DPU 数千 LUT + 数十~上百 DSP | ❌ 明确不支持（[AMD 社区答复](https://adaptivesupport.amd.com/s/question/0D54U00006cp0G8SAI/vitis-ai-support-for-zedboard?language=zh_CN)、[Vitis AI 3.0 集成文档](https://xilinx.github.io/Vitis-AI/3.0/html/docs/workflow-system-integration.html)） | 高（平台不符即不可用） |
| D. FINN + Brevitas | 二值/低比特网络吞吐极高、全自动 RTL 生成 | 算子集合固定、非常规前端难嵌；**Pynq-Z1/Z2 已随 Vivado 2024.2 退出官方支持**；Docker/依赖版本历史包袱重 | 低比特下 LUT 主导、DSP 极少 | ⚠️ 当前版本不再官方支持 7000（[FINN Getting Started](https://finn-dev.readthedocs.io/en/latest/getting_started.html)、[讨论 #1663](https://github.com/Xilinx/finn/discussions/1663)） | 高（流程脆弱） |
| E. hls4ml | PyTorch/ONNX 直出 HLS 工程、社区活跃、支持 Conv1D | 面向粒子物理/简单 CNN，长序列 1D 流水与自定义预处理支持有限；上板 overlay 受 PYNQ 版本牵制 | Dense/小型 CNN 数十~百 LUT/DSP | ⚠️ VivadoAccelerator 支持 `pynq-z2` 但依赖 PYNQ（[文档](https://fastmachinelearning.org/hls4ml/advanced/accelerator.html)、[Conv 论文](https://cds.cern.ch/record/2751704/files/fulltext.pdf)） | 中 |
| F. MATLAB HDL Coder | 与现有算法团队模型衔接顺、DDR 访问示例完备 | 许可成本高、代码可读性弱、优化自由度低于 HLS | 卷积 IP 可上 Zynq（[官方示例](https://www.mathworks.com/help/hdlcoder/ug/deploy-hls-ip-core-for-image-convolution-on-zynq-with-ddr-access.html)） | ✅ | 低 |

### 2.3 选型结论

**主选路线：B —— Vitis HLS 实现可参数化的定点（INT16 基线）一维卷积加速器 IP，PS(ARM)+Linux 负责采集、调度与告警，PL 负责定点推理与实时预处理。** 决策要点：

1. 平台约束直接排除 C（DPU 不支持 Zynq-7000），D/E 在低成本 7000 板上的工具链可持续性不足，A 的验证成本不匹配"示例工程"的目标与工期。
2. 1D-CNN 网络规模小（万级参数），HLS 完全能吃下，且**权重常驻 BRAM + 流水卷积核**即可拿到百微秒级固定延迟，不需要 DPU 这类通用调度器；反过来，**在 7 系列上 DPU/低比特框架的核心优势（INT8 双倍 DSP 吞吐）本就不存在**，进一步削弱了引入脆弱工具链的动机。
3. HLS 路线的所有关键设计（数据通路、缓冲、量化、调度）都是**可迁移知识**，未来升级到 UltraScale+ 时同一套 IP 可继续复用，也可平滑切到 DPU 做对照实验——这正是示例工程最需要的教学价值。
4. 保留一条**对照基线**：用 hls4ml 生成同一网络的工程做交叉验证（非交付必需，用于评估自研 IP 的优劣）。

**器件与开发板基线（以官方 DS190 / UG585 为准，逐项核对）**：XC7Z020-1CLG400（Z-7020 级别）

| 项目 | 数值 | 对本项目的含义 |
| --- | --- | --- |
| 逻辑 | 85K 逻辑单元 ≈ 53,200 LUT / 106,400 FF | LUT 余量充足（对标实现普遍 <75%） |
| Block RAM | 140 × 36 Kb = 4.9 Mb ≈ **630 KB** | **首要瓶颈**：权重 + 层间特征图 + 双缓冲 + DMA 缓存都要从这里出 |
| DSP | 220 个 DSP48E1（18×25） | 7 系列单级 25×18 乘法：**INT16 与 INT8 均为 1 MAC/DSP/周期**（2×INT8 是 UltraScale+ 特性；276 GMACs 峰值指标依赖对称 FIR 预加器，本网络卷积不对称，不可套用） |
| PS | 双核 Cortex-A9 @667 MHz，L2 512 KB，OCM 256 KB | 预处理/协议/落盘足够，浮点推理不够 |
| PS-PL | 4×AXI_HP 64-bit @150 MHz（每口 R+W 2,400 MB/s）、2×GP 32-bit、ACP | 只有输入窗与分数跨边界，带宽完全够用 |
| DDR | DDR3/DDR3L 32-bit @1066 → 理论 4,264 MB/s；单口实际受互连限制 ≈2,840 MB/s，控制器效率 ≈75% | 权重镜像与数据缓存放 DDR，热路径留在 BRAM |
| 硬核接口 | **Z-7010/Z-7020 无 PCIe**；XADC 为 2×12-bit/1 MSPS | 无 PCIe 顾虑；**振动采集必须外接 ADC**（≥16-bit、≥100 kSPS 同步采样） |

开发板候选：正点原子 / ALINX / 米联客等 ZYNQ7020 板 + AD 子卡（AD7606 或 ADS8028 级别）。数据出处：[DS190（官方）](https://docs.amd.com/v/u/en-US/ds190-Zynq-7000-Overview)、[UG585 表 22-2（官方）](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM)、[UG585 v1.7 镜像](https://class.ece.iastate.edu/cpre488/resources/ug585-Zynq-7000-TRM.pdf)。注意 DS191 只覆盖 Z-7030/7045/7100，XC7Z020 的 DC/AC 特性对应另一份手册，电气逐条数值本次未能核实。

---

## 3. 需求规格

### 3.1 功能需求

| 编号 | 需求 | 优先级 | 验收依据 |
| --- | --- | --- | --- |
| FR-01 | 支持 2 通道同步振动输入（16-bit，采样率 12.8/25.6 kHz 可配），并可扩展至 4/8 通道 | P0 | 采集连续 30 min 无丢样 |
| FR-02 | 可编程窗长与窗移：窗长 1024/2048/4096 点（与训练侧一致），重叠率 0/25/50% 可配 | P0 | 配置后自动重算吞吐并更新告警 |
| FR-03 | PL 内实现固定系数预处理：直流去除、抗混叠/带通 FIR（可旁路） | P1 | 与 Python 参考实现误差 < 1 LSB（定点后） |
| FR-04 | 实现可参数化 1D-CNN 推理：Conv1D 层数 3–5，核长 3–16，通道 8–64，stride 1/2/4、dil=1、ReLU、MaxPool(2)、GlobalAvgPool、末层 FC | P0 | 支持 §4.2 基线网络及 ±20% 超参变体 |
| FR-05 | 权重/偏置以 **INT16 基线**（INT8/混合精度为压缩变体）+ INT32 累加定点格式存于片上 BRAM，加载时间 < 100 ms | P0 | 掉电重启后可从 QSPI/SD 重新加载 |
| FR-06 | 支持 ≥ 10 类故障输出（正常、内圈/外圈/滚动体故障各含轻微/严重、不平衡、松动等），输出为分数向量 + argmax 标签 | P0 | 标签与训练脚本一致 |
| FR-07 | 支持模型热切换（双权重组），切换期间不停采集 | P1 | 切换 < 200 ms 且无窗丢失 |
| FR-08 | PS 侧提供 REST/gRPC 或 MQTT 上报接口（本地闭环，可离线），并落盘环形缓冲（最近 24 h 告警） | P1 | 断网时本地可查，恢复后补传 |
| FR-09 | 提供阈值与滑窗投票策略：连续 N 窗同判才告警，抑制偶发误报 | P0 | 误报率满足 NFR-05 |
| FR-10 | 运行时可观测：每窗推理周期数、PL 利用率计数器、错误状态寄存器（AXI-Lite 只读 + PS 轮询） | P1 | 日志可回溯 |
| FR-11 | 一键部署脚本：HLS 出 IP → Vivado block design → XSA → Vitis 平台 → PetaLinux rootfs → 应用二进制 | P0 | 干净环境 ≤ 2 h 完成全流程 |
| FR-12 | 提供训练侧配套：PyTorch 模型定义、BN/ReLU 融合、定点化（INT16 基线 + 可选 QAT INT8/混合精度）、逐层量化参数导出（scale/zero-point 或移位表示）、C 测试向量生成 | P0 | 生成的向量可用于 bit-exact 比对 |
| FR-13 | 每个判定结果必须携带工况标签（负载档 / 转速档）与置信度；跨工况样本单独统计精度 | P1 | 报表按工况分列（对应 §5.2 泄漏风险） |

### 3.2 非功能需求

| 编号 | 指标 | 目标值 | 底线值 | 说明 |
| --- | --- | --- | --- | --- |
| NFR-01 | 单窗推理延迟（2048 点基线网络，§4.2） | 目标 ≤ 500 μs / 挑战 ≤ 250 μs | ≤ 1 ms | 硬实时、固定周期；M2 用 `csyn` II 报告冻结档位 |
| NFR-02 | 吞吐（含预处理与调度开销） | 基线形态：≥ 2 窗/秒（2 通道 @25.6 kHz、窗长 2048、无重叠） | ≥ 1.5 窗/秒 | **明确不承诺 50% 重叠连续推理**；需更高窗口密度时按"瘦网络 / 多引擎 / 降重叠"三选一降档，评审决定 |
| NFR-03 | 判定延迟：窗采样完成 → 标签输出 | ≤ 300 ms | ≤ 2 s | 2048 点 @25.6 kHz 的**窗本身就有 80 ms 采集期**，因此"20 ms 端到端"在本窗口尺寸下物理上不成立，已从需求中移除；告警实际时延另含 FR-09 投票（N 窗），需在 M0 与 NFR-02 吞吐档位一起确认 |
| NFR-04 | 诊断准确率（CWRU 划分测试集） | ≥ float32 基线 −0.5 pp | −1.0 pp | 见 §5.2 基线口径 |
| NFR-05 | 误报率 / 漏报率 | 误报 ≤ 0.5 次/天/测点；漏报 ≤ 1% | 误报 ≤ 2 次/天 | 由 FR-09 策略保证 |
| NFR-06 | PL 资源占用 | **BRAM ≤ 70%（≤440/630 KB）**、LUT ≤ 40%、DSP ≤ 30%（≤66/220） | BRAM ≤ 80%、LUT ≤ 60%、DSP ≤ 50% | BRAM 为受约束项（对标实现普遍 70–100%），DSP 余量留给并行度扩展 |
| NFR-07 | 时钟与 STA | PL 主时钟 100–150 MHz，实现后 WNS ≥ 0 且余量 ≥ 100 ps | 100 MHz | -1 速度等级 |
| NFR-08 | 功耗 | PL 逻辑 + DDR ≤ 1.0 W（推理稳态） | ≤ 1.5 W | 板级实测或 Vivado 功耗报告 |
| NFR-09 | 可靠性 | 连续 72 h 无故障；单事件翻转(SEU)非关键；看门狗复位可用 | 24 h | 工业现场基础要求 |
| NFR-10 | 可维护性 | 网络超参改动仅通过 HLS 模板参数 + 训练侧导出脚本完成，不改核心数据通路 | — | 示例工程的教学性指标 |
| NFR-11 | 文档与可复现 | 结构图、接口表、量化说明、上板手册、逐步复现脚本齐备 | — | 交付验收项 |

### 3.3 约束与假设

**硬约束**：器件限于 Zynq-7000（7 系列，-1 或 -2 速度等级）；工具链限于 Vivado + Vitis HLS + PetaLinux/Vitis 平台流，不引入 UltraScale+/Versal 专属 IP；不使用 PCIe；板载 DDR3 容量 ≥ 512 MB；软件许可优先使用社区/学术可用版本。

**假设**：现场信号为转速平稳或缓慢变化（不做阶次跟踪，如需则另立阶段）；训练数据以 CWRU/公开数据集 + 少量实测数据为主，允许离线训练；单节点独立运行，无多节点协同；对模型可解释性不做硬性要求（但保留特征图落盘调试能力）。

**明确排除（Out of scope）**：变流器/电机控制闭环、无线组网协议栈、云端平台开发、DPU/FINN 路线实现（仅做技术对照记录）、封装与 EMC 认证。

---

## 4. 系统方案概述（供需求评审对齐）

### 4.1 数据通路

```
ADC(2ch 16b) ──SPI/并口──► PL 前端(FIFO + FIR 预处理 + 环形缓冲/双缓冲)
                                     │ AXI4-Stream (int16 激活)
                                     ▼
                        1D-CNN 加速器（HLS, weight-stationary, INT16）
                        Conv1 → ReLU → Pool → Conv2 → … → GAP → FC
                                     │ AXI4-Stream (分数向量)
                                     ▼
                        PS(Cortex-A9, Linux): 投票/告警/MQTT/落盘/健康监控
                        ▲ AXI4-Lite（寄存器：使能、窗参数、权重基址、状态计数）
```

设计要点：卷积核采用**权重常驻 + M 维并行 + K 维展开**的流水结构，每层输出经片上 BRAM 双缓冲传递（不回到 DDR），只有输入窗和最终分数跨 PS-PL 边界；BN 在训练侧折入卷积权重，运行时零开销；层间统一按 per-channel scale 做定点缩放，累加器 32-bit，激活按选定位宽饱和。

### 4.2 基线网络与算力预算

网络刻意采用**前端快速降采样**结构（对标 [Sensors 22(15):5793](https://doi.org/10.3390/s22155793) 的 k=16/s=4 + k=8/s=4 做法），把时间维尽早压下来，因为本设计的成本驱动项是 `M×Cin×K×Cout` 中的 `M`（时间长度），而不是 DSP 数量。

| 层 | 配置 | 输出形状 | MAC 数 | 参数(INT16) |
| --- | --- | --- | --- | --- |
| Conv1 | k=16, c=16, s=4 | 512×16 | 524 k | 4.2 KB |
| Conv2 | k=8, c=32, s=4 | 127×32 | 1.04 M | 16.6 KB |
| Pool | k=2, s=2 | 63×32 | ~0 | — |
| Conv3 | k=3, c=64, s=1 | 61×64 | 468 k | 37.2 KB |
| GAP | — | 64 | 61 | — |
| FC | 64 → 10 | 10 | 640 | 1.28 KB |
| 合计 | 输入 2048×1 | — | **≈2.04 M MAC / 窗** | **≈29 K 参数 ≈58 KB** |

算力与延迟折算（工程估算，非文献值）：7 系列 1 MAC/DSP/周期，@150 MHz、64 DSP → 9.6 GMAC/s → 理论下限 **213 μs/窗**；按流水效率 η=0.6–0.8 折算 **266–355 μs**，满足 NFR-01 目标值 ≤250 μs 需并行度提到 ~96 DSP 或 η≥0.85，故把 ≤500 μs 设为**基线目标**、≤250 μs 为**挑战目标**、≤1 ms 为**底线**，M2 用 HLS `csyn` 的 II 报告冻结。吞吐侧：25.6 kHz、窗长 2048、50% 重叠 → 25 窗/秒的需求对应 40 μs/窗，**远超单引擎能力**——这是本项目必须明确的产品边界：实时做法只能是"降重叠（1 窗/秒~8 窗/秒）+ 多引擎分时复用 + 网络瘦身（对标 35K–800K MAC 量级的公开轻量模型）"，具体档位见 NFR-02 与风险表。

**位宽决策**：基线取 **INT16 权重/激活 + INT32 累加**。依据三条：7 系列 INT8 相对 INT16 几乎不省 DSP（本设计 DSP 非瓶颈，BRAM 才是）；16-bit 定点精度损失有公开证据（YOLOv2 −0.2%、BearingPGA −0.27 pp）；CWRU 上纯 INT8 逐位宽精度扫描**未见公开数据**，风险不可预估。INT8/混合精度与"权重 2^k 免乘法"（可把 DSP 需求压到 0–30 片，[Sensors 2023](https://doi.org/10.3390/s23239437)）作为 M4 的**压缩变体**，进入前提是完成 QAT 且精度门限（NFR-04）通过。

### 4.3 存储预算（BRAM 是主战场）

| 用途 | 预算 | 说明 |
| --- | --- | --- |
| 权重常驻（58 KB）+ 量化元数据 | ≤ 80 KB | 单套权重；双权重组热切换（FR-07）需 ×2，须评估 |
| 层间特征图双缓冲 | ≤ 260 KB | Conv2 输出 127×32×2B×2 ≈ 16 KB；按最大层配置 + 4/8 通道扩展预留 |
| 输入环形缓冲 + DMA 暂存 | ≤ 64 KB | 2 通道 × 4096 点 × 2B |
| 行缓存/移位窗口 | ≤ 32 KB | k=16 的滑窗 |
| 合计 | **≤ 440 KB / 630 KB（70%）** | 与 NFR-06 一致；超出即触发"分块流式（tile）"降档方案 |

> 参数量与上面量级的网络（29K 参数）**远小于**公开轻量模型上限，进一步印证设计压力来自流水调度与特征图缓冲，而非常驻权重容量。

---

## 5. 验证与验收准则

### 5.1 分层验证链

第一级，**算法侧**：PyTorch float32 基线（10 折交叉验证，按 §5.2 的物理段切分，报告均值±方差）→ INT16 定点（含可选 INT8/2^k 变体）模型，记录逐层量化误差与最终精度差。第二级，**bit-exact 一致性**：导出 32 组测试向量（含边界值、全零、饱和样本），要求 HLS C 仿真、C/RTL 协同仿真与 PyTorch 定点参考实现三者在定点层逐级完全一致，最终分数向量误差为 0 bit。第三级，**综合与时序**：HLS 资源/II 报告 → Vivado 实现后利用率与 WNS 满足 NFR-06/07。第四级，**上板性能**：用 ILA/时间戳寄存器实测每窗周期数，验证 NFR-01~03；72 h 连续运行验证 NFR-09；功耗表测 NFR-08。第五级，**场景级**：在留出实测数据上验证 NFR-04/05 的误报/漏报指标。

### 5.2 精度基线口径

以 CWRU 为公开基准，口径固定为：**12 k DE 通道、0–3 HP 四档负载（约 1797/1772/1750/1730 rpm）、损伤直径 0.007/0.014/0.021 in × 球/内圈/外圈 + 正常 = 10 类、窗长 2048 点**，与 §4.2 基线网络一致。同时构建 **内部留出集**（现场实测、与训练工况不同负载/转速）作为主验收依据——公开集分数只用于横向对比。

必须显式处理的口径风险：该领域多数文献按**片段随机切分**（如每类每工况 320 训练 / 80 测试），同一物理窗口的相邻片段会同时出现在训练与测试集，造成同源泄漏、99%+ 的数字普遍偏乐观；10 折交叉验证的折间波动可达 ±2–4 pp（[Sensors 2023 免乘法 CNN](https://doi.org/10.3390/s23239437) 报告 91.38–95.48%）。因此本工程的验收要求：**按"物理段/时间块"切分而非按窗随机切分**、跨负载工况单独一栏、报告 accuracy + macro-F1 + 每类 P/R/F1 + 10 折均值±方差、并给出 SNR −10/−6/−4/−2/0/+2 dB 的鲁棒性曲线；所有对比实验固定随机种子、窗长与重叠设置一致。

### 5.3 交付物清单

需求与设计文档（含本文件的评审定稿版）、训练与量化脚本仓库、HLS IP 源码与测试平台、Vivado block design 与约束文件、Vitis/PetaLinux 平台与 PS 应用、上板操作手册（step-by-step，含常见错误）、性能与资源实测报告、可复现的 CI 脚本（HLS csim/csynth + RTL 仿真）、演示视频（可选）。

---

## 6. 里程碑与工作量

| 阶段 | 内容 | 出口准则 | 周期（1 算法 + 1 FPGA + 0.5 系统） |
| --- | --- | --- | --- |
| M0 立项与需求冻结 | 本文件评审、指标锁定、开发板与 AD 子卡采购 | 评审通过、指标表签字 | 2 周 |
| M1 算法与量化基线 | 网络定型、BN 融合、INT16 定点化（+ 可选 QAT INT8/2^k 变体）、测试向量导出 | 精度达 NFR-04，向量与脚本可用 | 4 周 |
| M2 HLS 核心与一致性 | 参数化卷积引擎、数据流架构、bit-exact 达标 | §5.1 验证链前两级全通过，资源满足 NFR-06，II/延迟档位冻结 | 6 周 |
| M3 系统集成 | Block design、AXI 接口、驱动、前端 FIR/环形缓冲 | 上板跑通端到端，延迟/吞吐达底线值 | 4 周 |
| M4 场景验证与优化 | 实测数据、并行度调优、功耗/可靠性、MQTT 与策略 | 全部 NFR 达标 | 4 周 |
| M5 文档与模板化 | 复现脚本、设计手册、可迁移模板说明 | 他人 2 天内可独立完成复现 | 2 周 |

关键路径在 M2（bit-exact 与流水效率），M1 与 M2 必须并行启动并共享同一份量化参数导出接口。

---

## 7. 风险登记表

| 风险 | 影响 | 概率 | 缓解措施 | 责任 |
| --- | --- | --- | --- | --- |
| 定点位宽选择失误（INT8 无 CWRU 公开精度数据；不重训练的低比特会掉 3–4 pp） | NFR-04 不达标 | 中 | 基线锁 INT16（有 −0.2~−0.27 pp 公开证据）；INT8/2^k 免乘仅作压缩变体，须 QAT + 精度门限放行 | 算法 |
| **BRAM 饱和**（7Z020 仅 630 KB，对标实现 70–100%） | NFR-06、多通道扩展 | 高 | §4.3 预算 ≤70% 并逐级 review；超出即启用分块流式（tile）+ 层缓冲复用；热切换双权重组需单独评审 | FPGA |
| 吞吐档位与产品需求错配（重叠窗实时推理超能力） | 可用性 | 高 | NFR-02 明确不承诺 50% 重叠；M0 评审锁定"降重叠 / 瘦网络 / 多引擎"三选一 | 管理者 |
| 流水效率 η 低于预期，延迟落不进预算 | NFR-01/02 | 中 | M2 前用 HLS 报告预估 II 做决策；提前定义降档方案（减通道/减层） | FPGA |
| 层间缓冲导致 BRAM 紧张（多通道扩展） | NFR-06 | 中 | 双缓冲 + 按层复用；超出时改为分块流式（tile）策略 | FPGA |
| 定点与浮点不一致排查耗时 | 进度 | 高 | 严格分层比对 + 逐层 dump 工具，M1 就建立向量导出规范 | 系统 |
| Zynq-7000 供货/工具链版本迁移（Vivado 对 7 系列支持节奏） | 长期维护 | 低-中 | 锁定工具版本；设计保持对 UltraScale+ 可移植；文档记录版本矩阵 | 系统 |
| 只做公开数据集导致指标虚高 | 产品可用性 | 高 | §5.2 双基线口径，现场留出集为主验收 | 算法 |
| 开发板/AD 子卡到货延迟 | 进度 | 中 | M0 第一周内下单；M1/M2 可先在全链路仿真（无板）完成 | 采购 |
| 团队 HLS 经验不足 | 质量/进度 | 中 | 保留 hls4ml 对照组；M2 前安排 2 天 HLS 实操培训 | 管理者 |

---

## 8. 参考资料

- [FPGA-based 1D-CNN accelerator for real-time arrhythmia classification](https://dl.acm.org/doi/abs/10.1007/s11554-025-01642-w)
- [A One-Dimensional Depthwise Separable CNN hardware implementation (Sensors 2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11644920/)
- [BearingPGA-Net: lightweight deployable bearing fault diagnosis with FPGA acceleration](https://arxiv.org/pdf/2307.16363) · [仓库](https://github.com/asdvfghg/BearingPGA-Net)
- [A Parameterizable Convolution Accelerator for Embedded FPGAs (HLS)](https://arxiv.org/html/2602.04044v1)
- [Optimizing FPGA-based Accelerator Design for Deep CNN (Yanglayer)](https://ceca.pku.edu.cn/media/lw/b73586e2ac7b5f8d63e8e584f398f17f.pdf)
- [Vitis AI 3.0：DPU IP Details and System Integration](https://xilinx.github.io/Vitis-AI/3.0/html/docs/workflow-system-integration.html) · [Vitis AI FAQ](https://xilinx.github.io/Vitis-AI/3.0/html/docs/reference/faq.html) · [AMD 社区：Vitis AI 不支持 Zynq-7000](https://adaptivesupport.amd.com/s/question/0D54U00006cp0G8SAI/vitis-ai-support-for-zedboard?language=zh_CN)
- [FINN Getting Started（板卡与工具版本支持）](https://finn-dev.readthedocs.io/en/latest/getting_started.html) · [FINN 讨论 #1663：板卡支持调整](https://github.com/Xilinx/finn/discussions/1663) · [FINN 框架论文](https://www.researchgate.net/publication/311791725_FINN_A_Framework_for_Fast_Scalable_Binarized_Neural_Network_Inference)
- [hls4ml VivadoAccelerator 后端](https://fastmachinelearning.org/hls4ml/advanced/accelerator.html) · [Fast convolutional neural networks on FPGAs with hls4ml](https://cds.cern.ch/record/2751704/files/fulltext.pdf) · [hls4ml 论文](https://arxiv.org/html/2512.01463v1)
- [DPU on PYNQ](https://github.com/Xilinx/DPU-PYNQ) · [Benchmarking Quantized NNs on FPGAs with FINN](https://hal.science/hal-03085342/document)
- [AMD Vitis HLS 产品页](https://www.amd.com/zh-cn/products/software/adaptive-socs-and-fpgas/vitis/vitis-hls.html) · [Zynq-7000 DS190 概览（官方）](https://docs.amd.com/v/u/en-US/ds190-Zynq-7000-Overview) · [DS190 Mouser 镜像 PDF](https://www.mouser.com/datasheet/2/903/ds190_Zynq_7000_Overview-1595492.pdf) · [Zynq-7000 TRM UG585（PS-PL 带宽表 22-2）](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM) · [UG585 v1.7 镜像](https://class.ece.iastate.edu/cpre488/resources/ug585-Zynq-7000-TRM.pdf)
- [MATLAB HDL Coder：Zynq 上部署图像卷积 IP（含 DDR 访问）](https://www.mathworks.com/help/hdlcoder/ug/deploy-hls-ip-core-for-image-convolution-on-zynq-with-ddr-access.html)
- [Efficient FPGA-Based CNN Accelerator（开源参考实现）](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator) · [Vitis-AI-Tutorials](https://github.com/xilinx/vitis-ai-tutorials)

**指标对标补充来源**

- 7Z020 实现：[Liu, JRTIP 2025](https://doi.org/10.1007/s11554-025-01642-w) · [Fradi, TechSci 2024](https://doi.org/10.18280/ts.410114) · [Kim, Sensors 2025 20:6359（INT16 YOLOv2 资源标定）](https://pmc.ncbi.nlm.nih.gov/articles/PMC12568313/) · [Slimani, JESA 59(1) 2026（BRAM 100% 饱和）](https://doi.org/10.18280/jesa.590115) · [González, Redalyc 2020（Arty Z7-20）](https://www.redalyc.org/journal/911/91164537008/html/)
- 振动/电流 1D-CNN：[BearingPGA-Net](https://arxiv.org/abs/2307.16363) · [1D-DSC（PU 电流，位宽-精度扫描）](https://doi.org/10.3390/s24237831) · [免乘法 CNN（CWRU，0 DSP）](https://doi.org/10.3390/s23239437) · [bDSCNN（二值，极低能量）](https://doi.org/10.3390/s24227207) · [Hakim 4 层 1D-CNN（CWRU，SNR 鲁棒性口径）](https://doi.org/10.3390/s22155793) · [WDCNN（CWRU 经典基线）](https://doi.org/10.3390/s17020425) · [DKDL-Net（蒸馏）](https://doi.org/10.1038/s41598-025-06734-y)
- 未能核实（引用需谨慎）：[SSRN 混合精度 QAT 预印本](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6985527)（全文 403，数值未取到）；XC7Z020 的 DC/AC 逐条电气值（对应 DS187 而非 DS191，本次抓取被拦截）；"振动/电流 + XC7Z020 + INT8"的直接同行评审基线（未检索到）。

> 数据说明：本文器件参数取自 [DS190](https://docs.amd.com/v/u/en-US/ds190-Zynq-7000-Overview) 与 [UG585](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM) 口径，选型定稿前应以具体型号 + 速度等级逐条复核；上表论文级资源/延迟数字用于**指标合理性论证**，不直接作为设计输入。文中所有算力折算（GMAC/s、单窗延迟）均为本文的工程估算，标注为估算处需在 M2 用 HLS 报告重新确认。
