// Formal-only replacement for prim_generic/rtl/prim_clock_gating.sv.
//
// The generic model uses a negative-level latch on the enable (glitch-free
// ICG). Kepler-formal SEC does not model level-sensitive state, so a latch in
// the clock cone makes every downstream output opaque. Cycle-accurately, the
// latched enable seen at the rising edge equals (en_i | test_en_i) sampled at
// that edge, so for single-clock sequential equivalence the latch can be
// replaced by a plain AND gate, which SEC turns into a state enable.
module prim_clock_gating #(
  parameter bit NoFpgaGate = 1'b0,
  parameter bit FpgaBufGlobal = 1'b1
) (
  input        clk_i,
  input        en_i,
  input        test_en_i,
  output logic clk_o
);
  assign clk_o = clk_i & (en_i | test_en_i);
endmodule
