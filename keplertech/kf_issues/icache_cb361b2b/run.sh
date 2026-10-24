#!/usr/bin/env bash
# SEC of upstream Ibex commit cb361b2b against its parent (ICache config) with kepler-formal.
# Usage: run.sh [before-after|before-before|after-after] [extra kepler-formal args...]
#   before-after (default) is the failing case; the other two are the self-check controls.
# Env: KF (kepler-formal binary, default: kepler-formal on PATH), WORK (work dir, default: ./work).
set -u
KF=${KF:-kepler-formal}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
pair=before-after
case "${1:-}" in before-after|before-before|after-after) pair=$1; shift ;; esac
d1=${pair%-*}; d2=${pair#*-}
W=$(mkdir -p "${WORK:-$HERE/work}" && cd "${WORK:-$HERE/work}" && pwd)

# The design sources come from git; the file lists from the current keplertech/.
for side in before:cb361b2b^ after:cb361b2b; do
  name=${side%%:*}; rev=${side#*:}
  rm -rf "$W/$name"; mkdir -p "$W/$name/keplertech"
  git -C "$REPO" archive "$rev" rtl vendor | tar -x -C "$W/$name"
  cp "$REPO/keplertech/ibex_top.f" "$REPO/keplertech/ibex_top_bisect_icache.f" "$W/$name/keplertech/"
  echo "-F $W/$name/keplertech/ibex_top_bisect_icache.f" > "$W/$name.f"
done

out=$W/$pair; rm -rf "$out"; mkdir -p "$out"; cd "$out"
{ "$KF" --version; env | grep ^KEPLER_; } > env.txt 2>&1
/usr/bin/time -l "$KF" -sv \
  --sv_design1_flist "$W/$d1.f" --sv_design1_top ibex_top \
  --sv_design2_flist "$W/$d2.f" --sv_design2_top ibex_top \
  -v sec --report-skipped-pos "$@" > sec.log 2>&1
rc=$?; echo "exit=$rc" >> sec.log
grep -E "checked-output coverage|proved|counterexample at|exit=| real|maximum resident|peak memory" sec.log | grep -v "^\s*- "
exit $rc
