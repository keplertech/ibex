// Reduced from ibex_trvk.sv: addr_mid = cbound_t'(ptr_storage_q >> cap_meta.exponent)
module t(input logic [31:0] x, input logic [3:0] sh, output logic [8:0] y);
  typedef logic [8:0] cbound_t;
  assign y = cbound_t'(x >> sh);
endmodule
