#!/usr/bin/env bash
# Usage: build.sh <config>   (uses ../results/<config>/ naja dump and flist)
set -e
cfg=${1:-default}
HERE=$(cd "$(dirname "$0")" && pwd); KT=$HERE/..
R=$KT/results/$cfg
flist=$KT/ibex_top.f; [ "$cfg" != default ] && flist=$KT/ibex_top_${cfg}_cosim.f
B=$HERE/build_$cfg; rm -rf "$B"; mkdir -p "$B"
VOPTS="-O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT -Wno-MULTIDRIVEN --top-module ibex_top"
verilator --cc --build -j 4 $VOPTS --prefix Vrtl  -Mdir "$B/rtl"  -F "$flist" > "$B/rtl.log" 2>&1 &
verilator --cc --build -j 4 $VOPTS --prefix Vnaja -Mdir "$B/naja" "$R/naja_primitives.v" "$R/ibex_top.naja.v" > "$B/naja.log" 2>&1 &
wait
python3 "$HERE/gen_harness.py" "$R/naja_summary.json" "$B/harness.cpp"
VROOT=$(verilator -V | awk '/VERILATOR_ROOT/ {print $3; exit}')
c++ -std=c++20 -O2 -I"$B/rtl" -I"$B/naja" -I"$VROOT/include" -I"$VROOT/include/vltstd" \
  "$B/harness.cpp" "$B/rtl/Vrtl__ALL.a" "$B/naja/Vnaja__ALL.a" "$B/rtl/libverilated.a" -lpthread -o "$B/cosim"
echo "built $B/cosim"
