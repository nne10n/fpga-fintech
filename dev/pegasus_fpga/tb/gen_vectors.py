"""生成 tb_pegasus.v 的验证向量, 并驱动 iverilog 仿真。"""
import random
import subprocess
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ref"))
from pegasus_ref import neighbors, linear, build, in_fabric

HERE = os.path.dirname(os.path.abspath(__file__))
M = 16
random.seed(2026)

nodes, edges = build(M)
lin_of = {q: linear(*q, M) for q in nodes}
by_lin = {v: k for k, v in lin_of.items()}

# ---- 邻居向量: 全部 5640 个主织构量子位 (源地址用 TB 的打包字段编码 u<<12|w<<8|k<<4|z) ----
with open(os.path.join(HERE, "vectors_nb.txt"), "w") as f:
    f.write(f"{len(nodes)}\n")
    for q in sorted(nodes, key=lambda x: lin_of[x]):
        u, w, k, z = q
        f.write(f"{(u << 12) | (w << 8) | (k << 4) | z}\n")
        nb = {slot: n for slot, n in neighbors(*q, M)}
        for slot in range(15):
            if slot in nb:
                f.write(" ".join(map(str, nb[slot])) + "\n")
            else:
                f.write("-1 -1 -1 -1\n")

# ---- 耦合判定向量: 所有边(两个方向) + 等量随机非边对 + 少量自身对 ----
pairs = []
for a, b in list(edges):
    pairs.append((a, b)); pairs.append((b, a))
node_list = sorted(nodes)
while len(pairs) < 2 * len(edges) + 100000:
    a, b = random.choice(node_list), random.choice(node_list)
    pairs.append((a, b))
nbr_sets = {q: {n for _, n in neighbors(*q, M)} for q in node_list}
for q in node_list[:400]:
    pairs.append((q, q))          # 自身: 期望不耦合
with open(os.path.join(HERE, "vectors_cp.txt"), "w") as f:
    f.write(f"{len(pairs)}\n")
    for a, b in pairs:
        gold = 1 if b in nbr_sets.get(a, set()) else 0
        f.write(f"{a[0]} {a[1]} {a[2]} {a[3]} {b[0]} {b[1]} {b[2]} {b[3]} {gold}\n")

# ---- 仿真 ----
r = subprocess.run(
    ["iverilog", "-g2005", "-o", os.path.join(HERE, "tb_pegasus.vvp"),
     os.path.join(HERE, "tb_pegasus.v"),
     os.path.join(HERE, "..", "rtl", "pegasus_topo.v")],
    capture_output=True, text=True)
print(r.stdout, r.stderr)
if r.returncode:
    sys.exit(1)
r = subprocess.run(["vvp", os.path.join(HERE, "tb_pegasus.vvp")],
                   capture_output=True, text=True, cwd=HERE)
print(r.stdout, r.stderr)
sys.exit(0 if "ALL PASS" in r.stdout else 1)
