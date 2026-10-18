#!/usr/bin/env python3
"""Export deterministic INT16 weight blob per scripts/weight_map.json (microarch §5.2)."""
from __future__ import annotations
import json, struct, pathlib, hashlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "scripts" / "weight_map.json"
OUT_BIN = ROOT / "vectors" / "weights.bin"
OUT_META = ROOT / "vectors" / "weights_meta.json"
OUT_H = ROOT / "_legacy_hls" / "weight_blob_size.h"

SEED = 0x1DC00101


def xorshift32(state: int) -> int:
    state &= 0xFFFFFFFF
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17) & 0xFFFFFFFF
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def gen_i16(state: int, lo: int = -16, hi: int = 16) -> tuple[int, int]:
    state = xorshift32(state)
    span = hi - lo + 1
    v = lo + (state % span)
    return state, int(v)


def main() -> None:
    m = json.loads(MAP_PATH.read_text())
    words: list[int] = []
    offsets: dict = {}
    state = SEED
    addr = 0

    for layer in m["layers"]:
        name = layer["name"]
        offsets[name] = {"base": addr, "sections": {}}
        for sec in layer.get("sections", []):
            sname = sec["name"]
            n = int(sec["words"])
            offsets[name]["sections"][sname] = {"offset": addr, "words": n}
            vals: list[int] = []
            if sname == "weights":
                for _ in range(n):
                    state, v = gen_i16(state, -8, 8)
                    vals.append(v)
            elif sname == "bias":
                for _ in range(n):
                    state, v = gen_i16(state, -32, 32)
                    vals.append(v)
            elif sname == "scale_mult":
                # keep dynamic range moderate: mostly 1..4
                for _ in range(n):
                    state, v = gen_i16(state, 1, 4)
                    vals.append(v)
            elif sname == "scale_shift":
                for _ in range(n):
                    vals.append(6)  # fixed >>6 after *mult
            elif sname == "recip_mult":
                # 2^20 / 61 ≈ 17246
                vals.append(17246)
            elif sname == "recip_shift":
                vals.append(20)
            else:
                raise SystemExit(f"unknown section {sname}")
            words.extend(vals)
            addr += n

    expected = int(m.get("total_words_expected", 0))
    if expected and len(words) != expected:
        raise SystemExit(f"word count {len(words)} != expected {expected}")

    OUT_BIN.parent.mkdir(parents=True, exist_ok=True)
    with OUT_BIN.open("wb") as f:
        for w in words:
            f.write(struct.pack("<h", int(w)))

    digest = hashlib.sha256(OUT_BIN.read_bytes()).hexdigest()
    meta = {
        "seed": SEED,
        "total_words": len(words),
        "bytes": len(words) * 2,
        "sha256": digest,
        "offsets": offsets,
        "feat_hotswap": 0,
        "map": str(MAP_PATH.relative_to(ROOT)),
    }
    OUT_META.write_text(json.dumps(meta, indent=2) + "\n")
    OUT_H.write_text(
        f"#pragma once\n#define WEIGHT_BLOB_WORDS {len(words)}\n"
        f"#define WEIGHT_BLOB_BYTES {len(words)*2}\n"
    )
    print(f"wrote {OUT_BIN} ({len(words)} words, sha256={digest[:16]}...)")


if __name__ == "__main__":
    main()
