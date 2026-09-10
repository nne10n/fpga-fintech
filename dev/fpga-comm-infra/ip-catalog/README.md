# ip-catalog

开写前骨架。可综合核只允许例化本目录已登记的 FIFO/RAM。

| 规则 | 说明 |
| --- | --- |
| CDC | 仅异钟边界登记并例化 `tx_afifo` |
| 同钟 | **禁止**为同钟通路发明 async FIFO / 假 CDC |
| 本步 S1/S2 | `sys_clk` / `sys_rst_n` 单钟；**不**例化 `tx_afifo` |

清单见 [CATALOG.md](./CATALOG.md)。
