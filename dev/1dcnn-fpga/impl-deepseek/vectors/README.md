# Test vectors

- `weight_map.json` — exact INT16 linear layout (microarch §5.2)
- `weights_synthetic.bin` — seed=42 synthetic export (replaceable)
- `cases/vXX_in.csv` / `vXX_score.csv` — window + golden scores
- `manifest.json` — case list and seeds

No separate `/workspace/1dcnn-fpga/golden/` tree was present; this directory is the golden for Implementer B.
