// Reduced from ibex_icache.sv output_data_lo mux (BUS_W=2, IC_OUTPUT_BEATS=2).
module t(input logic [31:0] data, input logic [1:0] addr, output logic [15:0] lo);
  always_comb begin
    lo = '0;
    for (int unsigned i = 0; i < 2; i++) begin
      if (addr[1:1] == i[0:0]) begin
        lo |= data[i*16+:16];
      end
    end
  end
endmodule
