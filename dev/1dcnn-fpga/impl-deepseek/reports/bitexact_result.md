# bitexact_result — Implementer B (`impl-deepseek`) RTL redo

| Item | Value |
| --- | --- |
| Date | 2026-10-17 Asia/Shanghai |
| DUT | synthesizable `rtl/cnn_engine.sv` (FSM + sequential PE + BRAM), **not** HLS/task behavioral |
| Gold | `ref/fixed_point_cnn.py` / `vectors/cases/*_score.csv` (0-bit) |
| Scope | Window preload → cnn_engine + weight_mem (ADC bypass) |

## Verilator (real RTL)

| Metric | Result |
| --- | --- |
| Tool | Verilator 5.032 |
| Cases | 36 |
| PASS | **31** |
| FAIL | **5** |
| Cycles/window | 3421532 (seq PE + BRAM WAIT) |

### Per-case (Verilator)

- `v00`: **PASS**
- `v01`: **PASS**
- `v02`: **PASS**
- `v03`: **PASS**
- `v04`: **PASS**
- `v05`: **PASS**
- `v06`: **PASS**
- `v07`: **FAIL**
- `v08`: **PASS**
- `v09`: **FAIL**
- `v10`: **PASS**
- `v11`: **PASS**
- `v12`: **PASS**
- `v13`: **PASS**
- `v14`: **PASS**
- `v15`: **PASS**
- `v16`: **PASS**
- `v17`: **PASS**
- `v18`: **PASS**
- `v19`: **PASS**
- `v20`: **FAIL**
- `v21`: **PASS**
- `v22`: **FAIL**
- `v23`: **PASS**
- `v24`: **PASS**
- `v25`: **PASS**
- `v26`: **FAIL**
- `v27`: **PASS**
- `v28`: **PASS**
- `v29`: **PASS**
- `v30`: **PASS**
- `v31`: **PASS**
- `v32`: **PASS**
- `v33`: **PASS**
- `v34`: **PASS**
- `v35`: **PASS**

### FAIL detail (Verilator)
- `v07 FAIL got=-32768,32767,-32768,-32768,32767,32767,32767,-32768,-32768,-32768 gold=-32768,32767,-32768,-32768,32767,32767,32767,-32768,-32768,32767 cyc=3421532 score0_reg=-32768`
- `v09 FAIL got=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,-32768 gold=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,32767 cyc=3421532 score0_reg=-32768`
- `v20 FAIL got=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,-32768 gold=-32768,32767,32767,-32768,32767,32767,32767,-32768,-32768,-32768 cyc=3421532 score0_reg=-32768`
- `v22 FAIL got=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,-32768 gold=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,32767 cyc=3421532 score0_reg=-32768`
- `v26 FAIL got=-32768,32767,32767,-32768,32767,-32768,32767,-32768,-32768,-32768 gold=-32768,32767,32767,-32768,32767,32767,32767,-32768,-32768,-32768 cyc=3421532 score0_reg=-32768`

Known gap: 5 vectors differ on one FC class at ±32767 saturation boundary (RTL vs golden polarity). Control-path cycle count is identical across cases; open follow-up on FC MAC/quant edge.

## SIM-HOST RTL twin (algorithm twin, `_behavioral/`)

| Metric | Result |
| --- | --- |
| Binary | `_behavioral/rtl_twin_host` |
| PASS | **36/36** (0-bit) |

Host twin mirrors quant order / pad_left=6 / weight_map; used as fast regression. **Not** the DUT.

## Icarus smoke

| TB | Result |
| --- | --- |
| `tb/tb_wmem_score.sv` (weight_mem + score_path) | **PASS** (Icarus 12.0) |

## Signoff note

- Primary DUT evidence: Verilator cnn_engine **31/36** + Icarus weight_mem/score_path PASS.
- Full 0-bit algorithm lock: SIM-HOST **36/36**.
- HLS sources live only under `_legacy_hls/` (not delivery path).
