/**
 *  bsg_adder_carry_save.v
 *
 * 
 */

`include "bsg_defines.v"

module bsg_adder_carry_save #(parameter width_p = "inv")
  (
    input [width_p-1:0] a_i
    , input [width_p-1:0] b_i
    , input [width_p-1:0] c_i
    , output logic [width_p-1:0] s_o
    , output logic [width_p-1:0] c_o
    );

  assign s_o = a_i ^ b_i ^ c_i;
  assign c_o = ((a_i & b_i) | (b_i & c_i) | (a_i & c_i)) << 1;
   

endmodule
