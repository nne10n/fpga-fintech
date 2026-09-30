# FPGA 动态加载调研概要

首先应区分两类“动态加载”：

1. **全量重配置**：运行时加载完整位流，整个 FPGA 暂停并重新初始化。
2. **动态部分重配置（DPR/PR）**：只替换指定区域，其余静态逻辑继续运行。AMD 称为 **DFX（Dynamic Function eXchange）**。

## 核心架构

```text
应用/调度器
   ↓
位流仓库 → 完整性、签名及兼容性校验
   ↓
重配置控制器
   ├─ 隔离动态区域接口
   ├─ 停止事务并保存必要状态
   ├─ 加载部分位流
   ├─ 校验配置结果
   └─ 初始化模块并恢复接口
   ↓
ICAP / PCAP / MCAP / JTAG / 外部配置口
```

设计被划分为：

- **静态区**：配置控制器、总线、存储器接口、时钟、监控逻辑。
- **可重配置区 RP**：运行时可替换的物理区域。
- **可重配置模块 RM/Persona**：可装入 RP 的不同功能。
- **隔离逻辑**：重配置期间固定输出并阻止非法总线事务。

## 标准加载流程

1. 停止向动态模块提交任务。
2. 等待 AXI/Avalon 等总线事务完成。
3. 保存模块状态（如业务需要）。
4. 关闭或隔离区域接口、时钟及中断。
5. 校验位流的设备型号、静态 Shell 版本、区域编号和签名。
6. 通过内部或外部配置接口写入位流。
7. 检查 CRC、配置状态和超时。
8. 复位并初始化新模块。
9. 恢复接口和业务；失败时回滚到安全模块。

理论加载时间可近似为：

\[
T_{load}=\frac{S_{bitstream}}{B_{effective}}+T_{isolation}+T_{initialization}
\]

实际瓶颈往往是存储读取、驱动复制、接口带宽利用率及认证解密，而不只是配置端口标称带宽。

## 厂商方案

| 方案 | AMD | Altera/Intel |
|---|---|---|
| 技术名称 | DFX | Partial Reconfiguration |
| 工具 | Vivado | Quartus Prime Pro |
| 区域定义 | RP、Pblock | Design Partition、Logic Lock |
| 动态模块 | RM | Persona |
| 接口隔离 | DFX Decoupler、AXI Shutdown Manager | Freeze Bridge |
| 控制方式 | DFX Controller、ICAP、PCAP、MCAP | PR Controller、内部或外部 Host |
| 验证 | `pr_verify` | PR 编译与兼容性检查 |
| 高级能力 | Abstract Shell、多个 RP | 多层级部分重配置 HPR |

Linux 提供统一的 **FPGA Manager + FPGA Bridge + FPGA Region** 框架。Region API 会依次锁定资源、关闭 Bridge、加载镜像并重新开启 Bridge，可通过 `FPGA_MGR_PARTIAL_RECONFIG` 标识部分重配置。

## 主要应用

- AI、通信或图像算法按需切换
- 不同协议、编解码器复用同一片逻辑资源
- 云端 FPGA 加速器租户或任务切换
- 现场功能升级
- 故障模块替换和容错恢复
- 降低器件规模、成本及静态功耗

不适合频繁到毫秒以下切换的小功能；此类需求通常用寄存器参数化、多路复用或软核实现更经济。

## 关键风险

- **时序收敛困难**：RP 边界固定，布线和资源选择受限。
- **接口兼容性**：所有 RM 必须具有完全一致的边界接口。
- **状态丢失**：触发器及局部 RAM 状态通常不会自动迁移。
- **事务破坏**：未排空 AXI/Avalon 请求可能造成死锁或数据错误。
- **位流错配**：加载到错误设备、Shell 或区域可能破坏系统。
- **安全问题**：位流必须具备认证、防回滚和访问控制；加密不等同于认证。
- **可观测性不足**：动态模块装载失败后调试难度较高。
- **设备差异**：部分位流认证、加密和可用配置端口依器件系列而异，不能跨型号假设。

## 建议的 PoC

选择一个具有明显输入输出的模块，例如：

- RM-A：直通
- RM-B：数据取反
- RM-C：FIR 或 AES 运算

静态区保留处理器接口、DMA、BRAM、隔离器、版本寄存器和加载控制器。验证：

- 静态区在重配置期间持续运行
- 总线无挂死、无非法输出
- 位流错配能够被拒绝
- 加载失败可以恢复到空白或安全 RM
- 测量位流大小、加载时间、停机时间和吞吐变化

## 初步结论

FPGA 动态加载在技术上已经成熟，但真正困难的是**系统级生命周期管理**，而不是写入位流本身。工程实现应优先保证：

1. 固定且版本化的 Shell/RP 接口；
2. 完整的隔离、排空和复位状态机；
3. 硬件支持的位流认证及防回滚；
4. 明确的失败回滚路径；
5. 自动化生成、兼容性检查和板级测试。

参考资料：

- [AMD Vivado DFX 用户指南 UG909](https://docs.amd.com/r/en-US/ug909-vivado-partial-reconfiguration)
- [Altera Quartus Partial Reconfiguration 指南](https://docs.altera.com/r/docs/683834/current)
- [Linux FPGA 子系统简介](https://docs.kernel.org/driver-api/fpga/intro.html)
- [Linux FPGA Programming API](https://docs.kernel.org/driver-api/fpga/fpga-programming.html)
