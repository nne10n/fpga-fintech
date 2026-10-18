#!/usr/bin/env python3
"""Generate ≥32 test windows (INT16) under vectors/."""
from __future__ import annotations
import json, struct, pathlib, math

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "vectors"
WIN = 2048
SEED = 0xA5A5C001


def xs(s: int) -> int:
    s &= 0xFFFFFFFF
    s ^= (s << 13) & 0xFFFFFFFF
    s ^= (s >> 17) & 0xFFFFFFFF
    s ^= (s << 5) & 0xFFFFFFFF
    return s & 0xFFFFFFFF


def write_vec(path: pathlib.Path, data: list[int]) -> None:
    with path.open("wb") as f:
        for v in data:
            f.write(struct.pack("<h", int(v)))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    cases = []

    # 0 all-zero
    cases.append(("v00_allzero", [0] * WIN))
    # 1 all +1
    cases.append(("v01_allplus1", [1] * WIN))
    # 2 all -1
    cases.append(("v02_allminus1", [-1] * WIN))
    # 3 saturate +full
    cases.append(("v03_sat_pos", [32767] * WIN))
    # 4 saturate -full
    cases.append(("v04_sat_neg", [-32768] * WIN))
    # 5 ramp
    cases.append(("v05_ramp", [((i % 2048) - 1024) for i in range(WIN)]))
    # 6 alternating
    cases.append(("v06_alt", [100 if (i & 1) == 0 else -100 for i in range(WIN)]))
    # 7 impulse
    impulse = [0] * WIN
    impulse[0] = 1000
    impulse[100] = -1000
    cases.append(("v07_impulse", impulse))
    # 8..27 random (≥20)
    s = SEED
    for n in range(20):
        buf = []
        for _ in range(WIN):
            s = xs(s)
            # map to roughly -512..511
            buf.append(int((s % 1024) - 512))
        cases.append((f"v{8+n:02d}_rand", buf))
    # 28 realistic-ish: damped sinusoid + noise (bearing-ish)
    s = xs(s)
    real = []
    for i in range(WIN):
        t = i / 25600.0
        sig = 800.0 * math.sin(2 * math.pi * 120.0 * t)
        sig += 200.0 * math.sin(2 * math.pi * 480.0 * t) * math.exp(-3.0 * t)
        s = xs(s)
        noise = (s % 41) - 20
        v = int(max(-32768, min(32767, round(sig + noise))))
        real.append(v)
    cases.append(("v28_realistic", real))
    # 29 sparse spikes
    sparse = [0] * WIN
    for i in range(0, WIN, 64):
        sparse[i] = 500
    cases.append(("v29_sparse", sparse))
    # 30 mid-scale const
    cases.append(("v30_const128", [128] * WIN))
    # 31 mid-scale neg
    cases.append(("v31_const-64", [-64] * WIN))

    assert len(cases) >= 32
    for name, data in cases:
        assert len(data) == WIN
        path = OUT / f"{name}.bin"
        write_vec(path, data)
        manifest.append({"id": name, "file": path.name, "len": WIN})

    (OUT / "manifest.json").write_text(json.dumps({"count": len(manifest), "cases": manifest}, indent=2) + "\n")
    print(f"wrote {len(cases)} vectors to {OUT}")


if __name__ == "__main__":
    main()
