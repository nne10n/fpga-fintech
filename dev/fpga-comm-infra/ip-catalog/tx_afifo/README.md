# tx_afifo

**状态：** 已登记，本步不实现、不例化。

用途：MAC TX 时钟与 `sys_clk` 不同时的写/读跨钟 FIFO。

本步 S2 `udp_mcast_tx` 与 S1 `tcp_pay_strip` 均在 `sys_clk` 单钟域（G1 A4）。同钟通路：

- 不得例化本 IP
- 不得用 async FIFO 冒充同钟弹性缓冲
- 角色 A 的 MAC pause 不回灌生产者，用丢弃+计数，而不是假 CDC

真正异钟 MAC 接入时：先在本目录补可综合实现，再在异钟边界例化。
