# Ibex with najaeda and kepler-formal

Status: 2026-10-17. This directory evaluates two open-source tools from [keplertech.io](https://keplertech.io) on Ibex (CHERIoT variant, commit `7a4697f5`):

* **najaeda**: Python netlist API with a slang-based SystemVerilog frontend. It elaborates RTL into a gate-level netlist.
* **kepler-formal**: equivalence checker. Here it runs sequential equivalence checking (SEC) of `ibex_top` against itself.

## Summary

| | Default `ibex_top` (RV32I) | `opentitan` config (CHERIoT, ICache+ECC+scramble, SecureIbex, PMP×16, RV32B, …) |
|---|---|---|
| najaeda elaboration | OK. 0 errors, 0 unsupported constructs. Loads in 0.5 s. | OK. 0 errors, 0 unsupported constructs. Loads in 2.5 s. |
| Co-simulation of the najaeda netlist against the RTL (3 seeds × 100k cycles) | **0 mismatches** | **0 mismatches** |
| Elaboration is deterministic (identical netlists over 5 runs) | yes | yes |
| kepler-formal SEC, Ibex against itself | **349/428 outputs proved**, the rest inconclusive | **242/428 proved** with ICache scrambling off. With scrambling on, SEC stops on a kepler-formal limitation (K5 below). |

These results need naja `main` at commit `c7f04beb` or later. kepler-formal must be built against that naja; the current kepler-formal release bundles an older one.

## Method

1. **Elaborate** with najaeda (`naja_load.py <config>`), using the file lists `ibex_top*.f`. Parameter overrides are passed as slang `-G` options.
2. **Check the elaboration independently** (`cosim/`):
   * Build the original RTL and najaeda's Verilog dump as two separate Verilator models.
   * Drive both with the same random stimulus and compare every output on both clock edges.
   * A single injected gate mutation is caught within a few hundred cycles, so the harness does catch real differences.
   * `cosim/bisect.sh` turns on one opentitan feature at a time to find which feature causes a mismatch.
   * `cosim/trace.sh` and `cosim/vcd_diff.py` find the first internal signal where the two models diverge.
3. **Check formally** (`run_sec.sh`): kepler-formal SEC of `ibex_top` against itself.

Self-equivalence cannot find elaboration bugs, because both sides share the same netlist. Step 2 is what found the najaeda bugs listed below. Step 3 measures how much of the design the formal engine can handle.

## najaeda bugs found by this evaluation (all fixed on naja `main`)

Bugs 1–4 produced a wrong netlist with no warning or error. Bug 5 made the netlist differ from run to run. Minimal repros of bugs 1–4 are in `naja_issues/`. Each folder has `t.sv`, an expected-value testbench `tb.cpp` for Verilator, and the wrong netlist najaeda produced before the fix.

| # | Bug | Where it hit Ibex |
|---|---|---|
| 1 | An `automatic` function local with a non-constant initializer (`logic a = (p != 2'b11);`) was left undriven. | `ibex_pmp.sv:138`: every PMP check was wrong. |
| 2 | A bit- or part-select of a `for` loop variable (`i[0]`) was evaluated once and reused in every unrolled iteration. | `ibex_icache.sv:1170-1188`: fetched instructions were corrupted. |
| 3 | In a continuous `assign`, operands were truncated to the LHS width *before* `>>`, `>>>`, `/` and `%`, contrary to IEEE 1800 §11.6. Example: `assign y9 = cbound_t'(x32 >> sh);`. | `ibex_trvk.sv:310`: wrong CHERIoT revocation-bitmap address. |
| 4 | `arr[k] = f(arr[k])` on an unpacked array element in `always_comb` read its own result, creating a combinational loop. | `ibex_alu.sv:422` popcount tree (RV32B). |
| 5 | Non-deterministic elaboration: the same input gave different instance order and net names from run to run. | `ibex_decoder`, `ibex_compressed_decoder`. |

## Co-simulation results

Every repro now gives the correct values. The najaeda netlist matches the RTL in every configuration:

| Config | Mismatches (seeds 1–3, 100k cycles each) |
|---|---|
| default | 0 / 0 / 0 |
| + PMP (16 regions) | 0 / 0 / 0 |
| + ICache (ECC, scramble) | 0 / 0 / 0 |
| + CHERIoT | 0 / 0 / 0 |
| + RV32B full | 0 / 0 / 0 |
| full opentitan | 0 / 0 / 0 |

Coverage caveat: the random stimulus exercises instruction fetch heavily in every config. In the full opentitan config it produces very few data-bus transactions (about 50 per 100k cycles), so the data path there is mostly covered by the single-feature configs.

## kepler-formal SEC results

All runs use the defaults: PDR engine, dual-rail steady-state encoding. `ibex_top_*sec.f` replaces the latch-based `prim_clock_gating` with a combinational model in `formal/prim_clock_gating.sv` (see K1).

| Run | Outputs proved | Time / memory |
|---|---|---|
| default (`ibex_top_sec.f`) | **349/428**; the rest inconclusive (K4) | about 245 s CPU, 0.4 GB |
| opentitan, ICache scrambling off (`ibex_top_opentitan_noscr_sec.f`) | **242/428**; the rest inconclusive (K4), nothing skipped | 760 s, 1.9 GB |
| opentitan (`ibex_top_opentitan_sec.f`) | stops with an error (K5) | — |

### Open items for kepler-formal

* **K1, latch clock gates:** the generic `prim_clock_gating` is a latch-based clock gate, and SEC treats latches as opaque, so 261 of 428 outputs were skipped. Workaround: `formal/prim_clock_gating.sv`. Native support for clock-gate latches would remove the need for it.
* **K2, `--set-as-boundary`:** it cannot name the latch inside the clock gate, because najaeda leaves that instance unnamed.
* **K3, binary encoding with reset** ([kepler-formal#285](https://github.com/keplertech/kepler-formal/issues/285)): `--sec-reset-cycles 2 --sec-reset-port rst_ni=0` reports a counterexample (`instr_addr_o[2]`, k=3) on the design compared with itself, while claiming full coverage. The likely cause is registers without a reset getting independent initial values in the two copies.
* **K4, inconclusive outputs:** these are the instruction and data bus outputs (address, request, write data, integrity, byte enables, and their lockstep `*_shadow_o` copies), plus `trvk_revbm_*` and the alert outputs. The fetch and data paths contain registers without a reset (e.g. `ibex_prefetch_buffer.sv`, `ibex_fetch_fifo.sv`), which is the likely reason.
* **K5, read-only memories** ([kepler-formal#286](https://github.com/keplertech/kepler-formal/issues/286)): naja maps constant lookup tables (the PRINCE and `prim_subst_perm` S-boxes used by ICache scrambling) to read-only `naja_mem` cells (no write ports, with init data). There are 108 such cells in the opentitan config. kepler-formal SEC then stops with `Missing SEC variable for memory read-output state`.

## Reproducing

Requirements:
* najaeda: naja built from source at commit `c7f04beb` or later, or a release that includes it
* kepler-formal
* Verilator ≥ 5
* a C++20 compiler

```sh
cd keplertech
export PYTHONPATH=<najaeda python package dir>  PY=python3  KF=<path>/kepler-formal

$PY naja_load.py opentitan       # elaborate; writes results/opentitan/
cosim/final.sh 100000            # co-sim of all configs above, 3 seeds
cosim/bisect.sh pmp icache       # single-feature co-sim
./run_sec.sh my_run ibex_top_sec.f                      # SEC, default config
./run_sec.sh my_ot ibex_top_opentitan_noscr_sec.f       # SEC, opentitan without scrambling
```

Each repro in `naja_issues/<bug>/` can be checked on its own:

```python
from najaeda import netlist
netlist.load_system_verilog(["t.sv"])
netlist.get_top().dump_verilog("out/t.v")
```

```sh
verilator --cc --exe --build --top-module t out/t.v [out/naja_primitives.v] tb.cpp && ./obj_dir/Vt
```

## Files

| Path | Content |
|---|---|
| `ibex_top.f`, `ibex_top_opentitan.f` | slang file lists (default config, plus `-G` overrides from `ibex_configs.yaml:opentitan`) |
| `*_cosim.f` | the same configs with numeric `-G` values, for Verilator |
| `*_sec.f`, `formal/` | SEC file lists using the latch-free clock-gate model |
| `ibex_top_bisect_*.f` | single-feature configs (default plus one opentitan parameter group), written by `cosim/bisect.sh` |
| `naja_load.py` | elaborates one config and writes a summary, hierarchy, diagnostics and Verilog dump to `results/<config>/` |
| `cosim/` | co-simulation harness generator, build, bisect, trace and VCD-diff scripts |
| `run_sec.sh` | kepler-formal SEC wrapper; results go to `results/kf/<run>/` |
| `naja_issues/` | minimal repros of najaeda bugs 1–4 |
