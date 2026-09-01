# FPGA 行情卡（md-card）— M2 `dec_szse_bin`

M1 `udp_strip` + M2 可配字段 Binary 解码（`dec_bin_generic` / `dec_szse_bin`）。  
仿真：Verilator ≥ 5.036 + cocotb。

## 仿真

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

make sim          # udp_strip + dec_szse_bin 全绿
make sim-udp      # 仅剥头
make sim-dec      # 仅深 Binary 解码
```

波形：`make sim WAVES=1`（FST）。

**不要**改 `rtl/md_pkg.sv` 的 `event_t` 位布局。  
M2 不实现 `arb_nway` / `sym_cam` / `mcast`。证券代码 ASCII 不进 `event_t`（`symbol_id=0`，CAM 后续）。

## Synthetic Binary 偏移（TB，非交易所 PDF）

| off | len | field |
|-----|-----|-------|
| 0 | 2 | msg_type |
| 2 | 2 | body_len（DUT 忽略，仅用固定偏移） |
| 4 | 4 | seq |
| 8 | 6 | code ASCII（不写入 event） |
| 14 | 8 | px u64 |
| 22 | 4 | qty u32 |
| 26 | 1 | side |
| 27 | 8 | order_id |
| 35 | 1 | ch_hint（DUT 用 type LUT，可忽略） |

## 计数

| 模块 | 计数器 | 含义 |
|------|--------|------|
| udp_strip | drop_not_udp / drop_opt / drop_filter / frames_ok | 见 M1 |
| dec_* | msg_ok / msg_bad | 成功事件 / 短帧·溢出·反压丢弃 |
