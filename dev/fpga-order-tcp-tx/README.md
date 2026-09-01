# 最小硬件 TCP 发单核（FPGA / SystemVerilog）

面向 **HFT 风格 tick-to-trade 的 TX/会话侧** 教学与可仿真核心：在 FPGA 内维护 **一条** TCP 客户端连接，预载二进制订单，脉冲触发后发出带正确校验和的 TCP 段。

作者相关：坤 仇。许可证：MIT。

> 本仓库实现的是干净、可仿真的 open 设计，**不是** Exegy nxTCP / Celoxica GXA 等厂商 IP 的复制。

## 它是什么

- SystemVerilog RTL：`rtl/`
- Verilator + cocotb 测试：`tb/`
- 架构说明：`docs/architecture.md`

**线侧**：AXI-Stream 64-bit 以太网帧（首字节在 `tdata[7:0]`）。无 MAC/PHY。  
**时钟**：仿真用任意周期；文档按 ~156.25 MHz / 10GbE 量级理解。  
**应用**：玩具二进制订单载荷 + `order_send` 发单脉冲（非 FIX/OUCH）。

## 快速仿真

依赖：Linux、`make`、Python 3.10+、**Verilator ≥ 5.036**（cocotb 2.x 要求）。

若系统 Verilator 过旧，可安装到仓库本地前缀（本环境已用 `/workspace/.local`）：

```bash
# 示例：从源码安装到 .local（已有则可跳过）
# git clone -b v5.036 https://github.com/verilator/verilator.git
# cd verilator && autoconf && ./configure --prefix=$PWD/../.local && make -j$(nproc) && make install
```

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

make sim
```

`Makefile` 会优先使用 `.local/bin/verilator`。

波形（FST）：

```bash
make sim WAVES=1
# 产物通常在 sim_build/ 或当前目录的 dump.fst（视 Verilator/cocotb 版本）
```

`make sim` 为零交互、CI 友好入口。

## 测试覆盖（必须全绿）

| 测试 | 内容 |
|------|------|
| `test_handshake` | SYN → SYN-ACK → ACK，进入 ESTABLISHED |
| `test_payload_send` | 发单产生正确端口/seq/flags/校验和/载荷 |
| `test_ack_and_resend_ready` | 对端 ACK 后可再发（单段 outstanding） |
| `test_csum_error_dropped` | RX 校验和错误不当作 ACK |
| `test_fin_close` | 本端 FIN 单向关闭 |

## 目录

```
rtl/           可综合 RTL
tb/            cocotb + Python TCP peer/BFM
docs/          架构说明
Makefile       make sim
LICENSE        MIT
```

## 主机接口（要点）

| 信号 | 方向 | 说明 |
|------|------|------|
| `cfg_local_mac/ip/port` 等 | in | 端点与静态对端 MAC（ARP 由 TB/软件提供） |
| `connect_req` / `close_req` | in | 会话开关（脉冲） |
| `tcp_state` / `established` | out | 状态 |
| `order_we/addr/wdata` | in | 字节写入订单缓冲 |
| `order_len_we/wdata` | in | 设置发送长度 |
| `order_send` | in | 发单脉冲 |
| `order_send_ready/done` | out | 可发 / 已被 ACK |
| `m_axis_*` | out | TX 以太网帧 |
| `s_axis_*` | in | RX 以太网帧 |

参数：`MAX_PAYLOAD`（默认 256）、`ISS`、`RCV_WND`。

## v1 明确不做

- 多连接、listen、同时打开、URG、窗口缩放、SACK
- 拥塞控制、RTO、快重传
- 动态 ARP、MAC/PHY、真实交易所协议
- 完整 RFC793

细节见 [docs/architecture.md](docs/architecture.md)。
