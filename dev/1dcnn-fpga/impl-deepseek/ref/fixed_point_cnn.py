#!/usr/bin/env python3
"""
Fixed-point 1D-CNN golden model (bit-exact contract).
Quant order (microarch §0.3):
  acc = bias_c  (INT32)
  acc += act * wgt  (INT16 x INT16 -> INT32)
  acc_scaled = (acc * scale_mult_c) >> scale_shift_c
  act_out = saturate_int16(acc_scaled)
  act_out = ReLU(act_out)   # after saturate
"""
from __future__ import annotations
import json
import struct
from pathlib import Path
from typing import Dict, List, Tuple
import numpy as np

INT16_MIN, INT16_MAX = -32768, 32767


def sat_i16(x: np.ndarray) -> np.ndarray:
    return np.clip(x, INT16_MIN, INT16_MAX).astype(np.int16)


def relu_i16(x: np.ndarray) -> np.ndarray:
    return np.maximum(x, 0).astype(np.int16)


def load_weight_map(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def regions_by_name(wmap: dict) -> Dict[str, dict]:
    return {r["name"]: r for r in wmap["regions"]}


def unpack_blob(blob: bytes, wmap: dict) -> Dict[str, np.ndarray]:
    """Unpack little-endian INT16 words into named arrays."""
    words = np.frombuffer(blob, dtype="<i2")
    reg = regions_by_name(wmap)
    out = {}
    for name, r in reg.items():
        sl = words[r["offset_words"] : r["offset_words"] + r["nwords"]]
        if r.get("dtype") == "uint16":
            arr = sl.view(np.uint16).copy() if sl.flags.writeable else np.array(sl, dtype=np.uint16)
            # reinterpret signed buffer as uint16
            arr = np.frombuffer(sl.tobytes(), dtype="<u2").copy()
        else:
            arr = sl.copy()
        if r.get("shape"):
            arr = arr.reshape(r["shape"])
        out[name] = arr
    return out


def pack_weights(arrays: Dict[str, np.ndarray], wmap: dict) -> bytes:
    total = wmap["total_words"]
    buf = np.zeros(total, dtype=np.int16)
    reg = regions_by_name(wmap)
    for name, r in reg.items():
        a = arrays[name].astype(np.int16).reshape(-1)
        assert a.size == r["nwords"], (name, a.size, r["nwords"])
        buf[r["offset_words"] : r["offset_words"] + r["nwords"]] = a
    return buf.astype("<i2").tobytes()


def make_synthetic_weights(wmap: dict, seed: int = 42) -> bytes:
    """Deterministic synthetic INT16 weights (replaceable training export)."""
    rng = np.random.RandomState(seed)
    reg = regions_by_name(wmap)
    arrays = {}
    for name, r in reg.items():
        n = r["nwords"]
        shape = r["shape"] or [n]
        if "shift" in name or name.endswith("_shift"):
            # modest shifts 8..12
            arrays[name] = rng.randint(8, 13, size=shape, dtype=np.uint16).astype(np.int16)
        elif "scale_mult" in name or name == "gap_recip_mult":
            arrays[name] = rng.randint(1000, 4000, size=shape, dtype=np.int16)
        elif name == "gap_recip_shift":
            # mean over 61 ≈ (sum * recip_mult) >> recip_shift
            # use recip_mult=1, shift≈0 is wrong; use mult=1<<16 / 61, shift=16
            arrays[name] = np.array([16], dtype=np.int16)
        elif "bias" in name:
            arrays[name] = rng.randint(-64, 65, size=shape, dtype=np.int16)
        else:
            arrays[name] = rng.randint(-64, 65, size=shape, dtype=np.int16)
    # Fix GAP reciprocal properly: avg = sum/61
    # (sum * recip_mult) >> recip_shift ≈ sum/61
    # recip_mult = round((1<<16)/61) = 1074, shift=16
    arrays["gap_recip_shift"] = np.array([16], dtype=np.int16)
    arrays["gap_recip_mult"] = np.array([1074], dtype=np.int16)
    return pack_weights(arrays, wmap)


def conv1d_layer(
    x: np.ndarray,
    w: np.ndarray,
    bias: np.ndarray,
    smult: np.ndarray,
    sshift: np.ndarray,
    stride: int,
    pad_total: int,
    apply_relu: bool = True,
) -> np.ndarray:
    """
    x: [T, Cin] int16
    w: [Cout, Cin, K] int16
    returns [Tout, Cout] int16
    """
    T, Cin = x.shape
    Cout, Cin_w, K = w.shape
    assert Cin == Cin_w
    if pad_total > 0:
        left = pad_total // 2
        right = pad_total - left
        xp = np.zeros((T + pad_total, Cin), dtype=np.int16)
        xp[left : left + T] = x
    else:
        xp = x
        left = 0
    Tp = xp.shape[0]
    Tout = (Tp - K) // stride + 1
    out = np.zeros((Tout, Cout), dtype=np.int16)
    for oc in range(Cout):
        for t in range(Tout):
            acc = np.int32(bias[oc])
            base = t * stride
            for ic in range(Cin):
                for k in range(K):
                    acc += np.int32(xp[base + k, ic]) * np.int32(w[oc, ic, k])
            sh = int(sshift[oc])
            scaled = (np.int64(acc) * np.int64(smult[oc])) >> sh
            v = int(np.clip(scaled, INT16_MIN, INT16_MAX))
            if apply_relu:
                v = max(0, v)
            out[t, oc] = np.int16(v)
    return out


def maxpool1d(x: np.ndarray, k: int = 2, stride: int = 2) -> np.ndarray:
    T, C = x.shape
    Tout = (T - k) // stride + 1
    out = np.zeros((Tout, C), dtype=np.int16)
    for t in range(Tout):
        base = t * stride
        out[t] = np.max(x[base : base + k], axis=0)
    return out


def gap(x: np.ndarray, recip_mult: int, recip_shift: int) -> np.ndarray:
    """Global average pool over time → [C] int16."""
    T, C = x.shape
    out = np.zeros(C, dtype=np.int16)
    for c in range(C):
        acc = np.int32(0)
        for t in range(T):
            acc += np.int32(x[t, c])
        scaled = (np.int64(acc) * np.int64(recip_mult)) >> int(recip_shift)
        out[c] = np.int16(np.clip(scaled, INT16_MIN, INT16_MAX))
    return out


def fc_layer(
    x: np.ndarray,
    w: np.ndarray,
    bias: np.ndarray,
    smult: np.ndarray,
    sshift: np.ndarray,
) -> np.ndarray:
    """x:[Cin], w:[Cout,Cin] → scores[Cout] int16 (no ReLU on FC)."""
    Cout, Cin = w.shape
    assert x.shape[0] == Cin
    out = np.zeros(Cout, dtype=np.int16)
    for oc in range(Cout):
        acc = np.int32(bias[oc])
        for ic in range(Cin):
            acc += np.int32(x[ic]) * np.int32(w[oc, ic])
        scaled = (np.int64(acc) * np.int64(smult[oc])) >> int(sshift[oc])
        out[oc] = np.int16(np.clip(scaled, INT16_MIN, INT16_MAX))
    return out


def infer_window(window: np.ndarray, arrays: Dict[str, np.ndarray], net: dict) -> np.ndarray:
    """
    window: [2048] int16 (Cin=1)
    returns scores [10] int16
    """
    x = window.astype(np.int16).reshape(-1, 1)  # [T,1]
    n1 = net["conv1"]
    y = conv1d_layer(
        x, arrays["conv1_w"], arrays["conv1_bias"],
        arrays["conv1_scale_mult"], arrays["conv1_scale_shift"],
        stride=n1["stride"], pad_total=n1["pad_total"], apply_relu=True,
    )
    assert y.shape == (512, 16), y.shape

    n2 = net["conv2"]
    y = conv1d_layer(
        y, arrays["conv2_w"], arrays["conv2_bias"],
        arrays["conv2_scale_mult"], arrays["conv2_scale_shift"],
        stride=n2["stride"], pad_total=n2["pad_total"], apply_relu=True,
    )
    assert y.shape == (127, 32), y.shape

    y = maxpool1d(y, k=2, stride=2)
    assert y.shape == (63, 32), y.shape

    n3 = net["conv3"]
    y = conv1d_layer(
        y, arrays["conv3_w"], arrays["conv3_bias"],
        arrays["conv3_scale_mult"], arrays["conv3_scale_shift"],
        stride=n3["stride"], pad_total=n3["pad_total"], apply_relu=True,
    )
    assert y.shape == (61, 64), y.shape

    g = gap(
        y,
        int(arrays["gap_recip_mult"].reshape(-1)[0]),
        int(arrays["gap_recip_shift"].reshape(-1)[0]),
    )
    assert g.shape == (64,)

    scores = fc_layer(
        g, arrays["fc_w"], arrays["fc_bias"],
        arrays["fc_scale_mult"], arrays["fc_scale_shift"],
    )
    assert scores.shape == (10,)
    return scores


def load_arrays_from_blob(blob_path: Path, wmap_path: Path) -> Tuple[dict, Dict[str, np.ndarray]]:
    wmap = load_weight_map(wmap_path)
    blob = blob_path.read_bytes()
    assert len(blob) == wmap["total_bytes"]
    return wmap, unpack_blob(blob, wmap)
