# 架构说明：最小硬件 TCP 发单核（v1）

## 目标

实现 **单连接 TCP 客户端** 的 TX/会话侧：在 FPGA 内保持一条 TCP 会话，预载二进制订单模板，触发后发出 TCP 段。面向教学与可仿真的 production-shaped 核心，**不是** Exegy/Celoxica 等厂商 IP 的克隆。

## 时钟与接口假设

| 项目 | 选择 |
|------|------|
| 数据宽度 | AXI-Stream **64-bit** |
| 字节序 | 线上首字节在 `tdata[7:0]`（Xilinx 风格） |
| 时钟 | 任意同源时钟；文档按 ~**156.25 MHz**（10GbE 量级）理解延迟 |
| 边界 | 停在以太网帧 AXIS；无 MAC/PHY |

## 模块划分

```
           Host CSR / 发单 API
                  │
           ┌──────▼──────┐
           │ order_buffer │  预载订单字节 + length
           └──────┬──────┘
                  │ payload read
┌─────────┐  ┌────▼────┐  ┌─────────────┐
│ eth RX  │─►│ tcp SM  │─►│ tcp_frame_tx│──► m_axis (TX frames)
│ parse   │  │ client  │  │ build+csum  │
└────▲────┘  └─────────┘  └─────────────┘
     │
  s_axis (RX frames)
```

1. **`eth_ipv4_tcp_rx`**：整帧缓冲后按 MAC + 五元组过滤，校验 IPv4 / TCP（含伪首部）校验和，输出 `seg_*`。
2. **`tcp_client_sm`**：`CLOSED → SYN_SENT → ESTABLISHED → FIN_WAIT_1 → TIME_WAIT/CLOSED`；跟踪 `snd_una/snd_nxt/rcv_nxt`；**一次 outstanding** 数据段。
3. **`tcp_frame_tx`**：组 Ethernet/IPv4/TCP 头、算校验和、经 AXIS 发出。
4. **`order_buffer`**：发单 API 的载荷 RAM。

## 延迟取向：为何选 Store-and-Forward

v1 对 **TX** 与 **RX** 都采用 **store-and-forward**：

- TCP/IPv4 校验和覆盖整段；小订单（≤ MSS，本核默认 256B）缓冲代价只有几十拍 @64b。
- 教学上校验和与字段布局更清晰，仿真易对拍。
- 真正 HFT 热路径会倾向 **cut-through + 增量校验和/预计算模板**，把可变字段（seq/ack/csum）在尾部打孔写入；那是 v2 优化，不是 v1 正确性前提。

## 显式不做（v1）

- 多连接、监听端、同时打开
- 窗口缩放、SACK、URG、拥塞控制、RTO/快重传（可后续 stub）
- ARP 动态解析（静态 `cfg_remote_mac` / TB 注入）
- FIX/OUCH/ITCH 等真实交易所协议
- MAC/PHY、PTP、组播

## 玩具订单格式（发单载荷）

不解析语义，仅作为 TCP payload 透明发送。测试使用示例：

| 偏移 | 长度 | 含义（约定） |
|------|------|----------------|
| 0 | 1 | `type`（例：1=限价） |
| 1 | 1 | `side`（1=买，2=卖） |
| 2 | 4 | `qty`（大端 u32） |
| 6 | 4 | `price`（大端 u32） |
| 10 | … | 填充至 `order_len` |

## 校验和

- IPv4：首部 16 位一补码，计算时校验和字段视为 0。
- TCP：伪首部（src/dst IP、零、protocol=6、TCP 长度）+ TCP 头 + 载荷；测试故意翻转字节以捕获 off-by-one。
