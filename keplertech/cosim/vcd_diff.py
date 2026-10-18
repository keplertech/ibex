"""Find the earliest-diverging internal signals between rtl.vcd and naja.vcd.

Signals are matched by a normalized hierarchical name: najaeda flattens
generate scopes into instance names such as
`ibex_top_u_ibex_core_if_stage_i_gen_prefetch_buffer_prefetch_buffer_i`,
so both sides are reduced to an underscore-joined path.

Usage: vcd_diff.py rtl.vcd naja.vcd [max_report]
"""
import re
import sys


def parse(path):
    scope, ids, changes = [], {}, {}
    t = 0
    with open(path) as f:
        in_defs = True
        for line in f:
            if in_defs:
                tok = line.split()
                if not tok:
                    continue
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    code, name = tok[3], tok[4]
                    ids.setdefault(code, []).append(scope[1:] + [name])
                elif tok[0] == "$enddefinitions":
                    in_defs = False
                continue
            c = line[0]
            if c == "#":
                t = int(line[1:])
            elif c in "01xz":
                changes.setdefault(line[1:].strip(), []).append((t, c))
            elif c == "b":
                v, code = line[1:].split()
                changes.setdefault(code, []).append((t, v.lstrip("0") or "0"))
    return ids, changes


def norm(parts):
    parts = [re.sub(r"[\[\]().]", "_", p).strip("_") for p in parts]
    start = 0
    for i, p in enumerate(parts):
        if p.startswith("ibex_top_"):
            start = i
    s = "_".join(parts[start:])
    return re.sub(r"_+", "_", s)


def index(path):
    ids, changes = parse(path)
    out = {}
    for code, names in ids.items():
        for n in names:
            out.setdefault(norm(n), code)
    return out, changes


def value_at(ch, t):
    v = None
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    return v


ra, rc = index(sys.argv[1])
na, nc = index(sys.argv[2])
common = sorted(set(ra) & set(na))
print(f"rtl signals={len(ra)} naja signals={len(na)} matched={len(common)}")
times = sorted({t for ch in rc.values() for t, _ in ch})
first = []
for n in common:
    a, b = rc.get(ra[n], []), nc.get(na[n], [])
    for t in times:
        va, vb = value_at(a, t), value_at(b, t)
        if va != vb:
            first.append((t, n, va, vb))
            break
first.sort()
for t, n, va, vb in first[: int(sys.argv[3]) if len(sys.argv) > 3 else 30]:
    print(f"t={t:6d} cyc~{t // 10:4d}  {n}: rtl={va} naja={vb}")
