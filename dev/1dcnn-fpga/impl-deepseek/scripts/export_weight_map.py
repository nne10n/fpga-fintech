#!/usr/bin/env python3
"""Export exact INT16 linear weight layout (microarch §5.2). Little-endian words."""
from __future__ import annotations
import json
from pathlib import Path

# Baseline network shapes
CONV1 = dict(cout=16, cin=1, k=16)
CONV2 = dict(cout=32, cin=16, k=8)
CONV3 = dict(cout=64, cin=32, k=3)
FC = dict(cout=10, cin=64)

def section(name: str, offset: int, nwords: int, shape=None, dtype="int16"):
    return {
        "name": name,
        "offset_words": offset,
        "nwords": nwords,
        "dtype": dtype,
        "shape": shape,
    }

def build_map():
    regions = []
    off = 0

    def add(name, nwords, shape=None, dtype="int16"):
        nonlocal off
        regions.append(section(name, off, nwords, shape, dtype))
        off += nwords

    # Conv1: w[Cout][Cin][K] + bias + scale_mult + scale_shift
    add("conv1_w", CONV1["cout"] * CONV1["cin"] * CONV1["k"],
        [CONV1["cout"], CONV1["cin"], CONV1["k"]])
    add("conv1_bias", CONV1["cout"], [CONV1["cout"]])
    add("conv1_scale_mult", CONV1["cout"], [CONV1["cout"]])
    add("conv1_scale_shift", CONV1["cout"], [CONV1["cout"]], dtype="uint16")

    add("conv2_w", CONV2["cout"] * CONV2["cin"] * CONV2["k"],
        [CONV2["cout"], CONV2["cin"], CONV2["k"]])
    add("conv2_bias", CONV2["cout"], [CONV2["cout"]])
    add("conv2_scale_mult", CONV2["cout"], [CONV2["cout"]])
    add("conv2_scale_shift", CONV2["cout"], [CONV2["cout"]], dtype="uint16")

    add("conv3_w", CONV3["cout"] * CONV3["cin"] * CONV3["k"],
        [CONV3["cout"], CONV3["cin"], CONV3["k"]])
    add("conv3_bias", CONV3["cout"], [CONV3["cout"]])
    add("conv3_scale_mult", CONV3["cout"], [CONV3["cout"]])
    add("conv3_scale_shift", CONV3["cout"], [CONV3["cout"]], dtype="uint16")

    # GAP: recip_shift / recip_mult (2 words) per microarch §5.2
    add("gap_recip_shift", 1, [1], dtype="uint16")
    add("gap_recip_mult", 1, [1], dtype="int16")

    # FC: w[10][64] + bias + scale_mult + scale_shift
    # (scales_fc expanded to mult+shift for same quant order as Conv)
    add("fc_w", FC["cout"] * FC["cin"], [FC["cout"], FC["cin"]])
    add("fc_bias", FC["cout"], [FC["cout"]])
    add("fc_scale_mult", FC["cout"], [FC["cout"]])
    add("fc_scale_shift", FC["cout"], [FC["cout"]], dtype="uint16")

    return {
        "version": 1,
        "endian": "little",
        "word_bits": 16,
        "total_words": off,
        "total_bytes": off * 2,
        "network": {
            "conv1": {**CONV1, "rin": 2048, "rout": 512, "stride": 4, "pad_total": 12},
            "conv2": {**CONV2, "rin": 512, "rout": 127, "stride": 4, "pad_total": 0},
            "pool": {"k": 2, "stride": 2, "rin": 127, "rout": 63},
            "conv3": {**CONV3, "rin": 63, "rout": 61, "stride": 1, "pad_total": 0},
            "gap": {"rin": 61, "rout": 64},
            "fc": {**FC},
        },
        "quant_order": "MAC -> (acc*scale_mult)>>scale_shift -> saturate_int16 -> ReLU",
        "regions": regions,
        "note": "Synthetic training export placeholder; replace blob via same layout.",
    }

def main():
    root = Path(__file__).resolve().parents[1]
    out = root / "vectors" / "weight_map.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    m = build_map()
    out.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out} total_words={m['total_words']} ({m['total_bytes']} bytes)")

if __name__ == "__main__":
    main()
