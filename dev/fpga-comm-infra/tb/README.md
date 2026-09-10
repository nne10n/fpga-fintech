# tb

cocotb + Icarus（`SIM=icarus`，`-g2012`）。

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r tb/requirements.txt
make -C tb/udp_mcast_tx    # S2
make -C tb/tcp_pay_strip   # S1
```

依赖：`iverilog`、`make`、`python3`。不要提交 `.venv/` 或 `sim_build/`。
