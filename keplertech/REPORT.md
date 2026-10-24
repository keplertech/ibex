# Ibex × keplertech tools — evaluation report (2026-10-16)

> Initial report (2026-10-16), kept for history. See [README.md](README.md) for the current status.

Tools: najaeda 0.7.29 (`3da8811d`) and kepler-formal (`c7bf059`). Ibex commit `7a4697f5` (CHERIoT variant).

## TL;DR

| Check | Default `ibex_top` (RV32I) | `opentitan` config (CHERIoT, icache, SecureIbex, PMP, RV32B) |
|---|---|---|
| najaeda load / elaborate | OK: 0.4 s, 0 errors, 0 unsupported | OK: 2.0 s, 0 errors, 0 unsupported (**silently wrong**, see below) |
| Co-sim of najaeda netlist vs Verilator RTL | **0 mismatches**, 3 × 200k random cycles | **mismatches**: 4 najaeda bugs found |
| kepler-formal SEC, ibex vs itself | 350/428 outputs proved (82%) | 36/428 (blocked by the najaeda bugs) |

## 1. najaeda: loading and elaboration

* File lists: `ibex_top.f` (default), `ibex_top_opentitan.f` (adds slang `-G` overrides
  matching `ibex_configs.yaml:opentitan`). `naja_load.py <config>` loads one config and writes
  `results/<config>/` (summary JSON, hierarchy, naja_if, Verilog dump, diagnostics).
* The hierarchy matches the parameters, e.g. opentitan has 2× `ibex_core` (lockstep shadow),
  `ibex_cheriot_ex`, `ibex_trvk`, `ibex_pmp`, `ibex_icache` with 4× `prim_ram_1p_scr`.
* **Independent check** (`cosim/`): the RTL and najaeda's Verilog dump are compiled as two
  Verilator models and driven with identical random stimulus; every output is compared on
  both clock edges. A one-gate mutation in the netlist is caught within 375 cycles, so the
  harness does detect bugs.
* `cosim/bisect.sh` turns on one opentitan feature at a time on top of the default config:

| Feature | Result | Root cause |
|---|---|---|
| WritebackStage, BranchTargetALU, RV32M single-cycle, SecureIbex, DbgTrigger, HPM counters | 0 mismatches | — |
| PMP | mismatch at cycle 10 | najaeda bug 1 (confirmed with a workaround: 0 mismatches) |
| ICache (+ECC, scramble) | mismatch at cycle 10 | najaeda bug 2 |
| CHERIoT | mismatch at cycle 568 | najaeda bug 3 |
| RV32B full | Verilator `DIDNOTCONVERGE` | najaeda bug 4 (comb loop) |

### najaeda bugs (minimal repros in `naja_issues/`)

Each folder has `t.sv` (repro), `tb.cpp` (exhaustive/expected-value test), `t_naja.v` (najaeda output).
**None of them produce a warning.**

1. **`01_func_local_init`**: a non-constant declaration initializer of a local in an
   `automatic` function (`logic a = (p != 2'b11);`) is computed but never connected: the
   local is left undriven. Hits `ibex_pmp.sv:138` (`access_fail`), so every PMP check is wrong.
2. **`02_loop_or_accumulate`**: in `always_comb`, `for (int unsigned i…) if (addr[1:1] == i[0:0]) lo |= data[i*16+:16];`
   gives wrong values for all inputs. Hits `ibex_icache.sv:1170` (`output_data_lo`), so
   fetched instructions are corrupted.
3. **`03_cast_of_shift`**: `cbound_t'(x >> sh)` truncates `x` *before* shifting. Per
   IEEE 1800 §6.24.1 the shift is evaluated at full width and truncated afterwards. Hits
   `ibex_trvk.sv:310` (`addr_mid`), giving a wrong revocation-bitmap address.
4. **`04_array_rmw_comb_loop`**: a blocking in-place update of an array element in `always_comb`
   (`p[i] = p[i-2] + p[i]`) becomes a combinational self-loop. Hits the `ibex_alu.sv:422` popcount
   tree (RV32B).

Also:
* **Non-deterministic elaboration**: loading the same sources 3 times gives 3 different dumps
  (same instance count; ordering and temp-net names differ, e.g. Zcmp temporaries in
  `ibex_compressed_decoder`). It hurts reproducibility, and kepler-formal's traceback shows
  "cone terms only in design0/design1" when comparing a design with itself.
* Benign: `ibex_cheriot_ex.sv:519` `seal_type` is assigned in one branch of an `always_comb`
  with no default. It's a don't-care, but Verilator holds the old value while najaeda gives 0.

## 2. kepler-formal: ibex vs itself (SEC, `run_sec.sh`)

RTL input requires `-v sec`. Results under `results/kf/<run>/`:

| Run | Flist | Options | Result | Time / RSS |
|---|---|---|---|---|
| `default_sec.log` | `ibex_top.f` | defaults (PDR, dual-rail) | 167/428; rest opaque (latch) | 2.5 s |
| `default_sec/` | `ibex_top_sec.f` | defaults | **350/428 proved**, 78 inconclusive | 262 s / 0.4 GB |
| `default_sec_reset/` | `ibex_top_sec.f` | `--sec-reset-cycles 2 --sec-reset-port rst_ni=0` | 350/428 | 552 s / 1.4 GB |
| `default_sec_kind/` | `ibex_top_sec.f` | `--sec-engine k_induction` | 332/428 | 231 s / 1.1 GB |
| `default_sec_binary_reset/` | `ibex_top_sec.f` | binary + reset | **counterexample** (spurious) | 83 s / 1.0 GB |
| `opentitan_sec/` | `ibex_top_opentitan_sec.f` | defaults | 36/428 (no-driver / logical-loop skips = najaeda bugs 1 and 4) | 192 s / 1.8 GB |

Findings for the kepler-formal team:
* **Latch clock gates**: `prim_clock_gating` (generic) is a latch-based ICG, and SEC treats latches
  as opaque, so 261/428 outputs were skipped. `--set-as-boundary` can't name the latch
  (an unnamed najaeda instance, `core_clock_gate_i/4` or `instance_4`, does not resolve).
  The workaround is `formal/prim_clock_gating.sv` (`clk & (en | test_en)`), used in `ibex_top*_sec.f`.
  Supporting ICG latches natively (or recognizing the pattern) would remove the need for it.
* **78 inconclusive outputs** (`instr_addr_o[*]`, `data_wdata_o[*]`) under dual-rail PDR. The fetch
  path has resetless registers (`ibex_prefetch_buffer.sv:162/186`, `ibex_fetch_fifo.sv:192`,
  `ibex_if_stage.sv:656…`), which is the likely cause.
* **Binary mode reports a counterexample on a design compared with itself** (`instr_addr_o[2]` at
  k=3) while claiming 100% coverage. Cause, probably: the resetless state above gets independent
  initial values in each copy. The docs say such outputs should be skipped in binary mode.
* Positive: kepler-formal correctly refused to "prove" logic hit by najaeda bugs 1 and 4, and
  reported them as no-driver / logical-loop skips with the exact instances (`pmp_i`, `alu_i`).

## 3. Key caveat for the ibex pitch

Self-equivalence (A vs A) **cannot** catch elaboration bugs, because both sides share the same
wrong netlist. The co-simulation harness is what found bugs 1–4. Before showing results to the
ibex owners, fix bugs 1–4 (and the non-determinism), then rerun:

```sh
python3 naja_load.py opentitan && cosim/build.sh opentitan && cosim/build_opentitan/cosim 200000 1
cosim/bisect.sh                 # per-feature co-sim
./run_sec.sh opentitan_sec ibex_top_opentitan_sec.f
```

(`PYTHONPATH=<kepler-formal>/build/src/bin:<kepler-formal>/thirdparty/naja/src/najaeda`, `EMSDK_QUIET=1`.)
Debug helpers: `cosim/trace.sh <config> <cycles>` plus `cosim/vcd_diff.py` find the first
internal signal where RTL and najaeda diverge.
