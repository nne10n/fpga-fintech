#!/usr/bin/env python3
"""Generate ≥32 csim vectors: all-zero, all-+1, all--1, saturate, random, realistic."""
from __future__ import annotations
import json
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ref"))
from fixed_point_cnn import (  # noqa: E402
    load_weight_map, make_synthetic_weights, unpack_blob, infer_window,
)

SEED_WEIGHTS = 42
SEED_VECTORS = 20261017
WIN = 2048
N_CLASS = 10


def write_i16_csv(path: Path, arr: np.ndarray):
    path.write_text(",".join(str(int(x)) for x in arr.reshape(-1)) + "\n", encoding="utf-8")


def main():
    wmap_path = ROOT / "vectors" / "weight_map.json"
    if not wmap_path.exists():
        from export_weight_map import build_map
        wmap_path.write_text(json.dumps(build_map(), indent=2) + "\n")
    wmap = load_weight_map(wmap_path)
    blob = make_synthetic_weights(wmap, seed=SEED_WEIGHTS)
    blob_path = ROOT / "vectors" / "weights_synthetic.bin"
    blob_path.write_bytes(blob)
    arrays = unpack_blob(blob, wmap)
    net = wmap["network"]

    out_dir = ROOT / "vectors" / "cases"
    out_dir.mkdir(parents=True, exist_ok=True)

    cases = []
    rng = np.random.RandomState(SEED_VECTORS)

    def add(cid: str, kind: str, window: np.ndarray):
        scores = infer_window(window, arrays, net)
        write_i16_csv(out_dir / f"{cid}_in.csv", window)
        write_i16_csv(out_dir / f"{cid}_score.csv", scores)
        cases.append({"id": cid, "kind": kind, "win_len": WIN, "n_class": N_CLASS})
        print(f"  {cid}: kind={kind} scores={scores.tolist()}")

    # Required categories
    add("v00", "all_zero", np.zeros(WIN, dtype=np.int16))
    add("v01", "all_plus1", np.ones(WIN, dtype=np.int16))
    add("v02", "all_minus1", (-np.ones(WIN, dtype=np.int16)))
    add("v03", "saturate_pos", np.full(WIN, 32767, dtype=np.int16))
    add("v04", "saturate_neg", np.full(WIN, -32768, dtype=np.int16))

    # More structured
    add("v05", "ramp", np.arange(WIN, dtype=np.int32).astype(np.int16))  # wraps
    add("v06", "alt_pm", np.array([1 if (i % 2 == 0) else -1 for i in range(WIN)], dtype=np.int16))
    t = np.arange(WIN, dtype=np.float64)
    sine = (8000 * np.sin(2 * np.pi * 50 * t / 25600)).astype(np.int16)
    add("v07", "realistic_sine50", sine)
    add("v08", "realistic_sine120",
        (6000 * np.sin(2 * np.pi * 120 * t / 25600)).astype(np.int16))
    add("v09", "realistic_noise_burst",
        np.clip(rng.randn(WIN) * 2000 + sine * 0.3, -32768, 32767).astype(np.int16))

    # Random batch to reach ≥32
    for i in range(10, 32):
        w = rng.randint(-5000, 5001, size=WIN, dtype=np.int32).astype(np.int16)
        add(f"v{i:02d}", "random", w)

    # Extra extras for margin
    for i in range(32, 36):
        scale = 1000 * (i - 31)
        w = rng.randint(-scale, scale + 1, size=WIN, dtype=np.int32).astype(np.int16)
        add(f"v{i:02d}", "random_scaled", w)

    meta = {
        "seed_weights": SEED_WEIGHTS,
        "seed_vectors": SEED_VECTORS,
        "weight_blob": "weights_synthetic.bin",
        "weight_map": "weight_map.json",
        "note": "Synthetic weights; training export replaceable via weight_map.json layout.",
        "n_cases": len(cases),
        "cases": cases,
    }
    (ROOT / "vectors" / "manifest.json").write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Generated {len(cases)} vectors under {out_dir}")


if __name__ == "__main__":
    main()
