# kepler-formal: before/after SEC of an Ibex ICache commit is mostly inconclusive

Status: open (2026-10-24). Logged for the kepler-formal team; not part of the Ibex results.

## Case

SEC of `ibex_top` with the ICache enabled, comparing two consecutive upstream Ibex commits:

| | Commit | Change |
|---|---|---|
| design 1 (before) | `65368a4c` (= `cb361b2b^`) | |
| design 2 (after) | `cb361b2b` "[rtl] Read only one way on a multi-way icache hit" | `rtl/ibex_icache.sv`, +11/−3 lines: the hit-data mux selects only the lowest matching way (`hit_way_ic1`) instead of ORing all matching ways |

Config: `keplertech/ibex_top_bisect_icache.f` = default `ibex_top.f` plus `-G ICache=1 -G ICacheECC=1 -G ICacheScramble=1`.
The latch-based `prim_clock_gating` is used as is.

The change is only visible when the same line is in two ways at once. It is not known whether that state is reachable from reset, so the expected answer is either a proof or a counterexample.

## Tools

* kepler-formal 0.5.0, commit `a669e569452f5cff9865aad4a4fcb42e16124dd6`
* naja 0.7.31, commit `538d3f72` (bundled in that kepler-formal build)
* macOS, 8 cores, 16 GB RAM

## Command

```sh
KF=<kepler-formal>/build/src/bin/kepler-formal keplertech/kf_issues/icache_cb361b2b/run.sh
```

`run.sh` extracts `rtl/` and `vendor/` of both commits with `git archive` into `work/` and runs:

```sh
kepler-formal -sv \
  --sv_design1_flist work/before.f --sv_design1_top ibex_top \
  --sv_design2_flist work/after.f  --sv_design2_top ibex_top \
  -v sec --report-skipped-pos
```

Extra arguments to `run.sh` go to kepler-formal. Defaults in effect: PDR engine, `dual_rail_steady`, max_k 32, KISSAT, `learn=true allow_x_equality=true binary_relation_round=true`, latch abstraction and data-enabled latch model on.

## Result

```
SEC checked-output coverage: 38.55% (165/428 covered/existing outputs).
SEC partially proved equivalence at k = 3: 165/428 outputs proved; remaining outputs are inconclusive.
SEC partial-proof details: Exact dual-rail PDR proved 165 of 428 observed outputs; remaining outputs are inconclusive
exit=1
4719 s real, 4082 s user, 375 s sys; max RSS 4.96 GB; peak memory footprint 18.1 GB
```

* No counterexample.
* No skipped outputs: `skipped_no_driver`, `skipped_multi_driver` and `skipped_logical_loop` are all empty.
* Every one of the 263 unproved outputs reports "dual-rail PDR steady-state proof was inconclusive":

| Output | Bits inconclusive |
|---|---|
| `crash_dump_o` | 159 of 160 |
| `data_wdata_o` | 32 |
| `data_addr_o` | 30 |
| `instr_addr_o` | 30 (bits 31:2; bits 1:0 are constant) |
| `data_be_o` | 4 |
| `instr_req_o`, `data_req_o`, `data_we_o`, `core_sleep_o`, `double_fault_seen_o`, `alert_minor_o`, `alert_major_internal_o`, `scramble_req_o` | 1 each |

The peak memory footprint (18.1 GB) is above the machine's RAM, so part of the run time is probably swapping.

## For comparison

The same tools prove 428/428 when each Ibex config is compared with itself:

| Run | Result | Time |
|---|---|---|
| default `ibex_top.f` against itself | 428/428 | 121 s |
| opentitan (ICache+ECC+scrambling, …) against itself | 428/428 | 573 s |

Not run yet: `ibex_top_bisect_icache.f` against itself. That run would tell whether the difficulty comes from the change or from the ICache config.

## More detail

These debug-only environment variables are from `docs/sec-flags-spec.md` and the kepler-formal sources. Set them before running `run.sh`:

| Variable | Output |
|---|---|
| `KEPLER_SEC_DIAG=1` | extraction, alignment, boundary, proof-problem and engine-progress diagnostics |
| `KEPLER_SEC_PDR_STATS=1` | PDR statistics, including the budget each single-output dual-rail proof used |
| `KEPLER_SEC_SUMMARY_STATS=1` | one-line problem summaries, internal relation candidates, rail equalities proved |
| `KEPLER_SEC_PDR_TRACE=1` | PDR problem and frame traces (large) |
| `KEPLER_SEC_CLOCK_GATE_DIAG=1` | clock-gate modeling diagnostics |
| `KEPLER_SEC_PDR_DUAL_RAIL_SINGLETON_{CONFLICT,DECISION,TICK}_BUDGET=<n>` | override the per-output dual-rail PDR budget |

A debug log level is only available in config mode (`--config <yaml>` with `log_level: debug`). Config mode cannot be combined with other command-line options.

To hand over the obligation without the Ibex sources, add `--dump-btor2 equivalence.btor2 --dump-only`. This writes both designs as one BTOR2 transition system and stops before solving.

Logs of the run above: `keplertech/results/kf/kf050_icache_cb361b2b/` (`sec.log`, `miter_log_0.txt`, `boundary_terms.txt`). This directory is gitignored, so the logs are local only.
