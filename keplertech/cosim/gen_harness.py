"""Generate a Verilator C++ harness that co-simulates two builds of ibex_top
(Vrtl = original RTL, Vnaja = najaeda-elaborated netlist) with identical
random stimulus and compares every output after every clock edge.

Usage: gen_harness.py <naja_summary.json> <out.cpp>
"""
import json
import sys

summary = json.load(open(sys.argv[1]))
ports = summary["top_terms"]

# Inputs held at fixed, meaningful values (everything else is randomized).
FIXED = {
    "clk_i": None,       # driven by the clock loop
    "rst_ni": None,      # driven by the reset sequence
    "test_en_i": "0",
    "scan_rst_ni": "1",
    "fetch_enable_i": "0x5",     # IbexMuBiOn
    "cheriot_enable_i": "0x5",   # IbexMuBiOn
    "boot_addr_i": "0x00100000",
    "hart_id_i": "0",
}
# Inputs that should toggle rarely, to let the core make progress.
RARE = {"irq_nm_i", "debug_req_i", "irq_external_i", "irq_timer_i",
        "irq_software_i", "irq_fast_i", "instr_err_i", "data_err_i",
        "trvk_revbm_err_i"}


def words(w):
    return (w + 31) // 32


lines = []
emit = lines.append
emit('#include <cstdio>\n#include <cstdlib>\n#include <cstdint>\n#include <random>')
emit('#include "Vrtl.h"\n#include "Vnaja.h"\n#include "verilated.h"')
emit('#ifdef TRACE\n#include "verilated_vcd_c.h"\n#endif\n')
emit('double sc_time_stamp() { return 0; }')
emit('static std::mt19937_64 rng;')
emit('static uint64_t rnd(int w) { uint64_t v = rng(); return w >= 64 ? v : (v & ((1ULL << w) - 1)); }')
emit('static bool rare() { return (rng() % 200) == 0; }\n')

emit('static void drive(Vrtl* a, Vnaja* b) {')
for name, d, w in ports:
    if "INPUT" not in d or name in ("clk_i", "rst_ni"):
        continue
    if name in FIXED:
        val = FIXED[name]
        if w > 64:
            for i in range(words(w)):
                emit(f'  a->{name}[{i}] = b->{name}[{i}] = {val};')
        else:
            emit(f'  a->{name} = b->{name} = {val};')
        continue
    if w > 64:
        for i in range(words(w)):
            emit(f'  {{ uint32_t v = rnd(32); a->{name}[{i}] = v; b->{name}[{i}] = v; }}')
    elif name in RARE:
        emit(f'  {{ uint64_t v = rare() ? rnd({w}) : 0; a->{name} = v; b->{name} = v; }}')
    else:
        emit(f'  {{ uint64_t v = rnd({w}); a->{name} = v; b->{name} = v; }}')
emit('}\n')

emit('static int compare(Vrtl* a, Vnaja* b, uint64_t cyc, const char* edge) {')
emit('  int bad = 0;')
for name, d, w in ports:
    if "OUTPUT" not in d:
        continue
    if w > 64:
        for i in range(words(w)):
            emit(f'  if (a->{name}[{i}] != b->{name}[{i}]) {{ bad++; '
                 f'printf("MISMATCH cyc=%llu %s {name}[word {i}] rtl=%08x naja=%08x\\n", '
                 f'(unsigned long long)cyc, edge, a->{name}[{i}], b->{name}[{i}]); }}')
    else:
        emit(f'  if (a->{name} != b->{name}) {{ bad++; '
             f'printf("MISMATCH cyc=%llu %s {name} rtl=%llx naja=%llx\\n", '
             f'(unsigned long long)cyc, edge, (unsigned long long)a->{name}, '
             f'(unsigned long long)b->{name}); }}')
emit('  return bad;\n}\n')

emit('''int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  uint64_t cycles = argc > 1 ? strtoull(argv[1], nullptr, 0) : 100000;
  uint64_t seed = argc > 2 ? strtoull(argv[2], nullptr, 0) : 1;
  rng.seed(seed);
  // Separate contexts so the two models (and their traces) stay independent.
  VerilatedContext* ca = new VerilatedContext; VerilatedContext* cb = new VerilatedContext;
#ifdef TRACE
  ca->traceEverOn(true); cb->traceEverOn(true);
#endif
  Vrtl* a = new Vrtl{ca}; Vnaja* b = new Vnaja{cb};
#ifdef TRACE
  VerilatedVcdC* ta = new VerilatedVcdC; VerilatedVcdC* tb = new VerilatedVcdC;
  a->trace(ta, 99); b->trace(tb, 99); ta->open("rtl.vcd"); tb->open("naja.vcd");
  uint64_t t = 0;
#define DUMP() do { ta->dump(t); tb->dump(t); t += 5; } while (0)
#else
#define DUMP() do {} while (0)
#endif
  uint64_t mismatches = 0, toggles = 0, instr_reqs = 0, data_reqs = 0;
  uint32_t last_iaddr = 0;
  a->clk_i = b->clk_i = 0; a->rst_ni = b->rst_ni = 0;
  drive(a, b); a->eval(); b->eval();
  for (uint64_t c = 0; c < cycles; c++) {
    a->rst_ni = b->rst_ni = (c >= 5);
    // Change inputs while the clock is low, then raise it.
    drive(a, b);
    a->clk_i = b->clk_i = 0; a->eval(); b->eval(); DUMP();
    mismatches += compare(a, b, c, "negedge");
    a->clk_i = b->clk_i = 1; a->eval(); b->eval(); DUMP();
    mismatches += compare(a, b, c, "posedge");
    if (a->instr_req_o) instr_reqs++;
    if (a->data_req_o) data_reqs++;
    if (a->instr_addr_o != last_iaddr) { toggles++; last_iaddr = a->instr_addr_o; }
    if (mismatches > 50) { printf("Too many mismatches, stopping at cycle %llu\\n", (unsigned long long)c); break; }
  }
  printf("seed=%llu cycles=%llu mismatches=%llu instr_req_cycles=%llu data_req_cycles=%llu instr_addr_changes=%llu\\n",
         (unsigned long long)seed, (unsigned long long)cycles, (unsigned long long)mismatches,
         (unsigned long long)instr_reqs, (unsigned long long)data_reqs, (unsigned long long)toggles);
#ifdef TRACE
  ta->close(); tb->close();
#endif
  a->final(); b->final(); delete a; delete b;
  return mismatches ? 1 : 0;
}''')

open(sys.argv[2], "w").write("\n".join(lines) + "\n")
