# SV cnn_engine simulation note (impl-glm53)

| Field | Value |
| --- | --- |
| Date | 2026-10-17 Asia/Shanghai |
| Simulator | Verilator 5.032 (+ Icarus 12.0 installed) |
| DUT | `rtl/cnn_engine.sv` + `rtl/cnn_pkg.sv` |
| Result | **32/32 PASS** 0-bit vs `vectors/*.golden.bin` |
| Command | `make sv_bitexact` |
| Cycles/window | 2059 (2048 AXIS + 1 compute eval + 10 score beats) |

Compute currently uses behavioral layer tasks inside `ST_COMPUTE` (bit-exact math identical to golden). PE-array scheduling for timing/NFR-01 is follow-on work; do not treat 1-cycle `ST_COMPUTE` as achievable silicon latency.
