#!/usr/bin/env bash
# Before/after SEC of upstream Ibex commit cb361b2b (ICache config) with kepler-formal.
# Usage: run.sh [workdir]   (KF selects the kepler-formal binary)
# Extra diagnostics: export KEPLER_SEC_DIAG=1 KEPLER_SEC_PDR_STATS=1 ... before running (see REPRO.md).
set -u
KF=${KF:-kepler-formal}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
W=$(mkdir -p "${1:-$HERE/work}" && cd "${1:-$HERE/work}" && pwd)

# The design sources come from git; the file lists from the current keplertech/.
for side in before:cb361b2b^ after:cb361b2b; do
  name=${side%%:*}; rev=${side#*:}
  rm -rf "$W/$name"; mkdir -p "$W/$name/keplertech"
  git -C "$REPO" archive "$rev" rtl vendor | tar -x -C "$W/$name"
  cp "$REPO/keplertech/ibex_top.f" "$REPO/keplertech/ibex_top_bisect_icache.f" "$W/$name/keplertech/"
  echo "-F $W/$name/keplertech/ibex_top_bisect_icache.f" > "$W/$name.f"
done

cd "$W"
{ "$KF" --version; env | grep ^KEPLER_; } > env.txt 2>&1
/usr/bin/time -l "$KF" -sv \
  --sv_design1_flist "$W/before.f" --sv_design1_top ibex_top \
  --sv_design2_flist "$W/after.f" --sv_design2_top ibex_top \
  -v sec --report-skipped-pos "$@" > sec.log 2>&1
rc=$?; echo "exit=$rc" >> sec.log
grep -E "checked-output coverage|proved|exit=| real|maximum resident|peak memory" sec.log | grep -v "^\s*- "
exit $rc
