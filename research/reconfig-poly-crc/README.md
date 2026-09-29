# Runtime-Reconfigurable Polynomial CRC for FPGA
 
## Scope

本仓库提供 FPGA 可运行时重构 CRC 多项式的**设计方案**。目标是在不重置系统、不重载 bitstream、也不使用 DFX/部分重配置的条件下，通过 CSR/AXI-Lite 更新 CRC 多项式及相关参数。

- 设计输入/输出：流式数据接口、CSR 配置接口与状态可观测性。
- 支持宽度：编译期选择 `CRC_W`，覆盖常见的 8、16、32、64 位实现。
- 运行时可变：`poly`、`init`、`xorout`、`refin`、`refout` 与多项式表示格式。
- 不包含：RTL、testbench、仿真脚本、约束文件或部分重配置方案。

完整设计见 [docs/reconfig-poly-crc-design.md](docs/reconfig-poly-crc-design.md)。

## Status

**Design Draft — NOT FROZEN**

寄存器地址、默认参数、目标频率及跨时钟域需求仍可按集成平台调整；已定义的配置生效原子性和帧中重配策略应作为实现基线。

## Local use

本仓库当前是设计文档交付物，无可执行软件工程或需要启动的服务。