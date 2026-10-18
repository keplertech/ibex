#!/usr/bin/env bash
# Usage: run_sec.sh <run-name> <flist> [extra kepler-formal args...]
# Self-equivalence (SEC) of ibex_top against itself with kepler-formal.
set -u
KF=${KF:-kepler-formal}   # path to the kepler-formal binary
HERE=$(cd "$(dirname "$0")" && pwd)
name=$1; flist=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2
out=$HERE/results/kf/$name; rm -rf "$out"; mkdir -p "$out"; cd "$out"
# The file lists are relative to their own directory (-F); kepler-formal reads its
# flist relative to the working directory, so go through a shim.
echo "-F $flist" > flist.f; flist=$out/flist.f
echo "$KF -sv --sv_design1_flist $flist --sv_design1_top ibex_top --sv_design2_flist $flist --sv_design2_top ibex_top -v sec --report-skipped-pos $*" > cmd.txt
/usr/bin/time -l "$KF" -sv \
  --sv_design1_flist "$flist" --sv_design1_top ibex_top \
  --sv_design2_flist "$flist" --sv_design2_top ibex_top \
  -v sec --report-skipped-pos "$@" > sec.log 2>&1
rc=$?; echo "exit=$rc" >> sec.log
grep -E "checked-output coverage|proved|SEC verification|exit=| real|maximum resident" sec.log | grep -v "^\s*- "
exit $rc
