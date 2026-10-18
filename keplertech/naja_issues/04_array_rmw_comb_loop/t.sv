// Reduced from ibex_alu.sv bitcnt_partial popcount tree (RV32B).
module t(input logic [3:0] bits, output logic [2:0] cnt);
  logic [2:0] p [4];
  always_comb begin
    p = '{default: '0};
    for (int unsigned i = 1; i < 4; i += 2) p[i] = {2'b0, bits[i]} + {2'b0, bits[i-1]};
    p[3] = p[1] + p[3];   // blocking read-modify-write of an array element
  end
  assign cnt = p[3];
endmodule
