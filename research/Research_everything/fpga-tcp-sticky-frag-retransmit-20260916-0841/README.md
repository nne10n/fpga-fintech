# FPGA 处理 TCP 黏包、碎包与重传/乱序重组

- **Slug:** `fpga-tcp-sticky-frag-retransmit-20260916-0841`
- **Date (Asia/Shanghai):** 2026-09-16 08:41
- **Tags:** FPGA, TCP, TOE, 黏包, 半包, 重传, 乱序, 低延迟, 分帧, 行情
- **Summary:** **三层禁混称**——L4 按 seq 流重组、应用层消息分帧（黏包/半包）、重传分 RX 容忍与 TX 引擎。低延迟交易默认 **FPGA 只做 RX 重组+应用分帧，TX 重传不上 FPGA**；乱序过深或 `MAX_MSG` 超 URAM 时换 DRAM 或卸回软核/Host。

## 范围

- **In:**
  - FPGA 内 **拼、拆、等缺段、触发重发/上报缺口**（机制层）
  - L4 流重组；应用分帧（长度前缀/分隔符/定长）；RX dup 容忍 vs TX RTO 引擎
  - 与 strip L2–L4 partial 路径的边界
- **Out:**
  - 完整 Linux **用户态**栈重写；策略报单
  - 未核实 ns；完整 RTL top/core
  - 完整 TLS；RFC793 逐条抄录
  - **把 IP 分片当成 TCP/应用碎包**

## Links

- [详尽报告](./report.md)
- [一页纸速览](./onepager.md)
- [出处清单](./sources.md)
