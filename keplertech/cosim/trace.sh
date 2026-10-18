#!/usr/bin/env bash
# Usage: trace.sh <config> <cycles> [seed]
# Builds RTL and najaeda models with VCD tracing, runs them in lockstep and
# writes build_<config>_trace/{rtl,naja}.vcd for vcd_diff.py.
set -e
cfg=$1; cycles=$2; seed=${3:-1}
HERE=$(cd "$(dirname "$0")" && pwd); KT=$HERE/..
R=$KT/results/$cfg
flist=$KT/ibex_top.f; [ "$cfg" != default ] && flist=$KT/ibex_top_${cfg}_cosim.f
B=$HERE/build_${cfg}_trace; rm -rf "$B"; mkdir -p "$B"
VOPTS="-O1 --trace --trace-structs --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT -Wno-MULTIDRIVEN --top-module ibex_top"
verilator --cc --build -j 4 $VOPTS --prefix Vrtl  -Mdir "$B/rtl"  -F "$flist" > "$B/rtl.log" 2>&1 &
verilator --cc --build -j 4 $VOPTS --prefix Vnaja -Mdir "$B/naja" "$R/naja_primitives.v" "$R/ibex_top.naja.v" > "$B/naja.log" 2>&1 &
wait
python3 "$HERE/gen_harness.py" "$R/naja_summary.json" "$B/harness.cpp"
VROOT=$(verilator -V | awk '/VERILATOR_ROOT/ {print $3; exit}')
c++ -std=c++20 -O1 -DTRACE -I"$B/rtl" -I"$B/naja" -I"$VROOT/include" -I"$VROOT/include/vltstd" \
  "$B/harness.cpp" "$VROOT/include/verilated_vcd_c.cpp" "$B/rtl/Vrtl__ALL.a" "$B/naja/Vnaja__ALL.a" "$B/rtl/libverilated.a" -lpthread -o "$B/cosim"
cd "$B" && ./cosim "$cycles" "$seed" | tail -3
