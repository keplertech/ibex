"""Load and elaborate ibex_top with najaeda; dump a structural summary.

Run with najaeda on PYTHONPATH:
  python3 naja_load.py [default|opentitan|<config>]
"""
import collections
import json
import os
import sys
import time

from najaeda import netlist, __version__, git_hash

HERE = os.path.dirname(os.path.abspath(__file__))
# Usage: naja_load.py [config]   (config: "default" -> ibex_top.f,
#                                  otherwise ibex_top_<config>.f)
CONFIG = sys.argv[1] if len(sys.argv) > 1 else "default"
FLIST = os.path.join(
    HERE, "ibex_top.f" if CONFIG == "default" else f"ibex_top_{CONFIG}.f")
OUT = os.path.join(HERE, "results", CONFIG)
os.makedirs(OUT, exist_ok=True)
# The file lists use paths relative to their own directory (-F); the loader reads
# its flist with -f (relative to the working directory), so go through a shim.
SHIM = os.path.join(OUT, "flist.f")
with open(SHIM, "w", encoding="utf-8") as shim:
    shim.write(f"-F {FLIST}\n")

print(f"najaeda {__version__} ({git_hash()}) config={CONFIG}")
cfg = netlist.SystemVerilogConfig(
    flist=SHIM,
    top="ibex_top",
    diagnostics_report_path=os.path.join(OUT, "naja_sv_diagnostics.log"),
)
t0 = time.time()
top = netlist.load_system_verilog([], cfg)
load_s = time.time() - t0
print(f"Loaded top '{top.get_name()}' in {load_s:.2f}s")

# Walk the hierarchy: count instances per model and leaf primitives.
model_count = collections.Counter()
leaf_count = collections.Counter()
hier = []
depth_max = 0


def walk(inst, depth):
    global depth_max
    depth_max = max(depth_max, depth)
    for child in inst.get_child_instances():
        model = child.get_model_name()
        model_count[model] += 1
        if child.is_leaf():
            leaf_count[model] += 1
        else:
            hier.append(("  " * depth) + f"{child.get_name()} : {model}")
            walk(child, depth + 1)


walk(top, 1)

top_terms = [(t.get_name(), str(t.get_direction()), t.get_width())
             for t in top.get_terms()]
summary = {
    "najaeda_version": __version__,
    "najaeda_git_hash": git_hash(),
    "config": CONFIG,
    "top": top.get_name(),
    "load_seconds": round(load_s, 2),
    "hierarchy_depth": depth_max,
    "num_top_terms": len(top_terms),
    "num_top_term_bits": sum(w for _, _, w in top_terms),
    "num_hier_instances": len(hier),
    "num_leaf_instances": sum(leaf_count.values()),
    "leaf_primitives": dict(leaf_count.most_common()),
    "top_terms": top_terms,
}
with open(os.path.join(OUT, "naja_summary.json"), "w") as f:
    json.dump(summary, f, indent=2)
with open(os.path.join(OUT, "naja_hierarchy.txt"), "w") as f:
    f.write(f"{top.get_name()} : {top.get_model_name()}\n")
    f.write("\n".join(hier) + "\n")

print(json.dumps({k: v for k, v in summary.items() if k != "top_terms"}, indent=2))

# Dump the elaborated netlist for kepler-formal (naja interchange format)
# and as structural Verilog for inspection.
netlist.dump_naja_if(os.path.join(OUT, "ibex_top.naja_if"))
top.dump_verilog(os.path.join(OUT, "ibex_top.naja.v"))
print("Dumped naja_if and Verilog to", OUT)
