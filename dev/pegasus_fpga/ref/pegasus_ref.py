"""Pegasus P_M 参考模型（golden model）。

结构定义严格取自 dwave-networkx pegasus_graph() 的构造规则
(dwavesystems/dwave-networkx, dwave/graphs/topologies/pegasus.py, offsets_index=0):
  顶点 (u, w, k, z): u∈{0,1}, w∈{0..M-1}, k∈{0..11}, z∈{0..M-2}
  外部边 external: (u,w,k,z) ~ (u,w,k,z+1)
  奇偶边 odd:      (u,w,2j,z) ~ (u,w,2j+1,z)
  内部边 internal: (0,w0,k0,z0) ~ (1,w1,k1,z1), 当且仅当
       w1 = z0 + (1 if k1 < S0[k0] else 0)
       z1 = w0 - (1 if k0 < S1[k1] else 0)
  主织构(main fabric)裁剪: w==0 时要求 k>=2, w==M-1 时要求 k<10
  线性索引: linear = ((u*M + w)*12 + k)*(M-1) + z
"""
from collections import Counter

S0 = (2, 2, 2, 2, 10, 10, 10, 10, 6, 6, 6, 6)   # offsets_index=0
S1 = (6, 6, 6, 6, 2, 2, 2, 2, 10, 10, 10, 10)


def in_fabric(u, w, k, z, M):
    if not (0 <= u <= 1 and 0 <= w < M and 0 <= k < 12 and 0 <= z < M - 1):
        return False
    if w == 0 and k < 2:
        return False
    if w == M - 1 and k >= 10:
        return False
    return True


def neighbors(u, w, k, z, M):
    """返回 (slot, (u,w,k,z)) 列表; slot 固定: 0-11 内部, 12/13 外部, 14 奇偶。
    slot 顺序与 FPGA 邻居生成器一一对应。"""
    out = []
    if u == 0:   # 垂直量子位: 内部邻居 k1 = j 遍历 0..11
        for j in range(12):
            w1 = z + (1 if j < S0[k] else 0)
            z1 = w - (1 if k < S1[j] else 0)
            if in_fabric(1, w1, j, z1, M):
                out.append((j, (1, w1, j, z1)))
    else:        # 水平量子位: 由对称性反解 (0,w0,k0,z0)
        for k0 in range(12):
            # w0 满足: w = z0? 反解: 本量子位是 (1,w1,k1,z1) = (1,w,k,z)
            # 内部边方程: w1 = z0 + (k1 < S0[k0]), z1 = w0 - (k0 < S1[k1])
            # => z0 = w1 - (k1 < S0[k0]), w0 = z1 + (k0 < S1[k1])
            z0 = w - (1 if k < S0[k0] else 0)
            w0 = z + (1 if k0 < S1[k] else 0)
            if in_fabric(0, w0, k0, z0, M):
                out.append((k0, (0, w0, k0, z0)))
    for dz, slot in ((-1, 12), (1, 13)):
        if 0 <= z + dz < M - 1 and in_fabric(u, w, k, z + dz, M):
            out.append((slot, (u, w, k, z + dz)))
    if k % 2 == 0:
        kn = k + 1
    else:
        kn = k - 1
    if in_fabric(u, w, kn, z, M):
        out.append((14, (u, w, kn, z)))
    return out


def linear(u, w, k, z, M):
    return ((u * M + w) * 12 + k) * (M - 1) + z


def build(M, fabric_only=True):
    nodes, edges = set(), set()
    for u in (0, 1):
        for w in range(M):
            for k in range(12):
                for z in range(M - 1):
                    if not in_fabric(u, w, k, z, M):
                        continue
                    nodes.add((u, w, k, z))
                    for _, n in neighbors(u, w, k, z, M):
                        if in_fabric(*n, M=M):
                            edges.add(tuple(sorted(((u, w, k, z), n))))
    return nodes, edges


if __name__ == "__main__":
    import sys
    ok = True
    for M, exp_nodes, exp_edges, tag in [(6, 680, 4484, "P6 (Boothby 2020)"),
                                         (16, 5640, 40484, "P16 Advantage 主织构")]:
        nodes, edges = build(M)
        deg = Counter(len(neighbors(*q, M)) for q in nodes)
        maxdeg = max(deg)
        # 边自检: 每条边的两端互为邻居
        for a, b in list(edges)[:20000]:
            assert b in [n for _, n in neighbors(*a, M)], (a, b)
        print(f"{tag}: M={M} nodes={len(nodes)} (期望 {exp_nodes})  edges={len(edges)} (期望 {exp_edges})  max_degree={maxdeg}")
        ok &= (len(nodes) == exp_nodes and len(edges) == exp_edges and maxdeg == 15)
    # 度分布细分: 内部/外部/奇偶
    M = 16
    nodes, _ = build(M)
    kinds = Counter()
    for q in nodes:
        for slot, _n in neighbors(*q, M):
            kinds["internal" if slot < 12 else "external" if slot < 14 else "odd"] += 1
    interior = [q for q in nodes if not (q[1] in (0, M - 1))]
    ki = Counter()
    for q in interior:
        for slot, _n in neighbors(*q, M):
            ki["internal" if slot < 12 else "external" if slot < 14 else "odd"] += 1
    n_int = len(interior)
    print(f"内部量子位({n_int}个)平均耦合数: internal={ki['internal']/n_int:.3f} external={ki['external']/n_int:.3f} odd={ki['odd']/n_int:.3f}")
    print("度15构成 = 12 internal + 2 external + 1 odd (内部量子位)")
    sys.exit(0 if ok else 1)
