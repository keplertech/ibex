#!/usr/bin/env bash
# Bisect RTL-vs-najaeda co-sim mismatches by enabling one opentitan parameter
# group at a time on top of the default ibex_top configuration.
# Usage: bisect.sh [name ...]   (default: all groups)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); KT=$HERE/..
# Requires najaeda on PYTHONPATH; PY selects the interpreter (default: python3).
export EMSDK_QUIET=1
PY=${PY:-python3}

# name|slang -G overrides (najaeda)|verilator -G overrides (numeric enums)
CFGS=(
  "cheriot|BaseIsa=ibex_pkg::BaseIsaRV32IorCHERIoT|BaseIsa=1"
  "wb|WritebackStage=1|WritebackStage=1"
  "bta|BranchTargetALU=1|BranchTargetALU=1"
  "rv32b|RV32B=ibex_pkg::RV32BFull|RV32B=2"
  "rv32m|RV32M=ibex_pkg::RV32MSingleCycle|RV32M=3"
  "icache|ICache=1 ICacheECC=1 ICacheScramble=1|ICache=1 ICacheECC=1 ICacheScramble=1"
  "secure|SecureIbex=1|SecureIbex=1"
  "pmp|PMPEnable=1 PMPNumRegions=16|PMPEnable=1 PMPNumRegions=16"
  "dbg|DbgTriggerEn=1|DbgTriggerEn=1"
  "hpm|MHPMCounterNum=10 MHPMCounterWidth=32|MHPMCounterNum=10 MHPMCounterWidth=32"
)

want=" $* "
for g in "${CFGS[@]}"; do
  IFS='|' read -r name sl vl <<< "$g"
  [ $# -gt 0 ] && [[ "$want" != *" $name "* ]] && continue
  cfg=bisect_$name
  { echo "-F ibex_top.f"; for p in $sl; do echo "-G $p"; done; } > "$KT/ibex_top_$cfg.f"
  { echo "-F ibex_top.f"; for p in $vl; do echo "-G$p"; done; } > "$KT/ibex_top_${cfg}_cosim.f"
  (
    $PY "$KT/naja_load.py" "$cfg" > "$KT/results/naja_$cfg.log" 2>&1 \
      && "$HERE/build.sh" "$cfg" > "$HERE/build_$cfg.log" 2>&1 \
      && res=$("$HERE/build_$cfg/cosim" 100000 1 | tail -1) \
      || res="BUILD/LOAD FAILED"
    echo "$name: $res"
    [ -n "${KEEP_BUILDS:-}" ] || rm -rf "$HERE/build_$cfg"/{rtl,naja}
  ) &
done
wait
