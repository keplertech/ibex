#!/usr/bin/env bash
# Co-simulate RTL vs najaeda netlist for the main configs (default, PMP, ICache,
# CHERIoT, RV32B, full opentitan), 3 seeds each.
# Usage: final.sh [cycles]
set -u
HERE=$(cd "$(dirname "$0")" && pwd); KT=$HERE/..
# Requires najaeda on PYTHONPATH; PY selects the interpreter (default: python3).
export EMSDK_QUIET=1
PY=${PY:-python3}
N=${1:-100000}
for g in default bisect_pmp bisect_icache bisect_cheriot bisect_rv32b opentitan; do
  cfg=final_$g
  if [ $g = default ]; then src=$KT/ibex_top.f; srcc=$KT/ibex_top.f
  else src=$KT/ibex_top_$g.f; srcc=$KT/ibex_top_${g}_cosim.f; fi
  cp "$src" "$KT/ibex_top_$cfg.f"; cp "$srcc" "$KT/ibex_top_${cfg}_cosim.f"
  (
    if $PY "$KT/naja_load.py" "$cfg" > "$KT/results/naja_$cfg.log" 2>&1 \
       && "$HERE/build.sh" "$cfg" > "$HERE/build_$cfg.log" 2>&1; then
      for s in 1 2 3; do echo "$g: $("$HERE/build_$cfg/cosim" $N $s | tail -1)"; done
    else echo "$g: BUILD/LOAD FAILED"; fi
  ) &
done
wait
