module t(input logic [1:0] priv, output logic fail);
  function automatic logic f(logic [1:0] p);
    logic a = (p != 2'b11);   // initializer depends on argument
    return a;
  endfunction
  assign fail = f(priv);
endmodule
