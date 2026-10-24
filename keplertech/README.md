# Ibex with the naja tools

Three open-source tools from the [naja](https://github.com/najaeda/naja) ecosystem, run on the unmodified Ibex sources (CHERIoT variant, upstream `a896ef22`):

* **[najaeda](https://github.com/najaeda/naja)**: a Python netlist API with a SystemVerilog frontend (slang). It turns the Ibex RTL into a netlist you can query, edit and dump.
* **[naja-scope](https://github.com/keplertech/naja-scope)**: lets you, or an AI assistant, ask questions of the elaborated design: what drives this signal, what is in this cone, which RTL line does this cell come from.
* **[kepler-formal](https://github.com/keplertech/kepler-formal)**: an equivalence checker. Sequential equivalence checking (SEC) proves that two versions of a design have the same outputs.

## Results

| | Default `ibex_top` | `opentitan` config (CHERIoT, ICache + ECC + scrambling, SecureIbex, PMP×16, RV32B) |
|---|---|---|
| najaeda elaboration | 0.5 s, 0 errors, 0 unsupported constructs | 2.4 s, 211k cells, 0 errors, 0 unsupported constructs |
| najaeda netlist against the RTL in Verilator (3 seeds × 100k cycles) | 0 mismatches | 0 mismatches |
| kepler-formal SEC | **428/428 outputs proved** in 2 min | **428/428 outputs proved** in 10 min |

No RTL changes, no blackboxes, no skipped outputs. The latch-based clock gate (`prim_clock_gating`) is handled as is. Measured on an 8-core laptop with 16 GB.

## A regression flow for Ibex

1. **Elaborate** each config with najaeda (`naja_load.py <config>`).
2. **Check the elaboration** by co-simulation (`cosim/`): the RTL and the najaeda netlist run as two Verilator models with the same random stimulus, and every output is compared on every clock edge.
3. **Prove** with kepler-formal (`run_sec.sh`). Here each config is compared against itself, which shows the tools handle all of Ibex. The same command compares two versions, for example before and after an RTL change. This is not yet conclusive on Ibex (see the note below).
4. **Explain** any difference with naja-scope: map the netlist cell kepler-formal reports back to an RTL file and line, and trace its cone.

### Example: from a formal trace to the RTL line

kepler-formal has an optional binary mode (`--sec-encoding binary`). In that mode it reports a difference on `instr_addr_o[2]` at cycle 3, on Ibex compared with itself. Its trace goes through netlist cells such as `prefetch_buffer_i.#219`. naja-scope maps them to the RTL:

```python
from naja_scope import api
api.load_systemverilog(flist="ibex_top.f", top="ibex_top")
api.get_source("ibex_top.u_ibex_core.if_stage_i."
               "ibex_top_u_ibex_core_if_stage_i_gen_prefetch_buffer_prefetch_buffer_i.#219")
```

```
../rtl/ibex_prefetch_buffer.sv:163-165
    always_ff @(posedge clk_i) begin
      if (stored_addr_en) begin
        stored_addr_q <= stored_addr_d;
```

`stored_addr_q` has no reset, so in binary mode the two copies can start with different values. That is a limitation of kepler-formal's binary mode ([kepler-formal#285](https://github.com/keplertech/kepler-formal/issues/285)), not an Ibex bug. The default mode used for the results above models such registers as unknown (X) and is not affected.

Through its MCP server, naja-scope answers the same questions in an AI assistant (Claude Code, ChatGPT, …): *"what drives `instr_addr_o`?"* returns the drivers with their RTL lines (`ibex_prefetch_buffer.sv:194-196`, `:265`).

## Notes

* **What "proved" means:** SEC (default dual-rail mode) proves that the two designs never differ on an output whose value is defined (0 or 1) in both. Registers without a reset start as X.
* **Comparing two versions is not conclusive yet:** SEC of upstream commit `cb361b2b` (ICache "read only one way on a multi-way hit") against its parent, in the ICache config, proved 165/428 outputs after 79 min. The other 263 are inconclusive: no proof and no counterexample. This is an open kepler-formal limitation; the reproducer is in [`kf_issues/icache_cb361b2b/`](kf_issues/icache_cb361b2b/REPRO.md).
* **Co-sim coverage:** in the full opentitan config the random stimulus produces few data-bus transactions, so the data path is covered mainly by the single-feature configs (PMP, ICache, CHERIoT, RV32B), which also give 0 mismatches.

## Reproducing

Tools: kepler-formal 0.5.0 (`a669e56`, which builds naja 0.7.31 and the najaeda Python module), naja-scope 0.1.9, Verilator ≥ 5, a C++20 compiler, Python 3.

```sh
cd keplertech
KFB=<kepler-formal>/build/src/bin
export PYTHONPATH=$KFB:<kepler-formal>/thirdparty/naja/src/najaeda  PY=python3  KF=$KFB/kepler-formal

$PY naja_load.py opentitan                    # elaborate; writes results/opentitan/
cosim/final.sh 100000                         # co-sim: default, PMP, ICache, CHERIoT, RV32B, opentitan
./run_sec.sh default ibex_top.f               # SEC, default config
./run_sec.sh opentitan ibex_top_opentitan.f   # SEC, opentitan config
```

Run `run_sec.sh` invocations one at a time.

| Path | Content |
|---|---|
| `ibex_top.f`, `ibex_top_opentitan.f` | file lists, with parameter overrides from `ibex_configs.yaml:opentitan` |
| `ibex_top_bisect_*.f`, `*_cosim.f` | single-feature configs, and the same configs for Verilator |
| `naja_load.py` | elaborates one config, writes summary, hierarchy, diagnostics and Verilog to `results/<config>/` |
| `cosim/` | co-simulation harness: build, `final.sh`, `bisect.sh` (one feature at a time), trace and VCD diff |
| `run_sec.sh` | kepler-formal SEC wrapper, results in `results/kf/<run>/` |
| `*_sec.f`, `formal/` | older variants with a combinational clock-gate model, no longer needed |
