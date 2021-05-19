//====================================================================
// bsg_idiv_iterative.v
// 11/14/2016, shawnless.xie@gmail.com
//====================================================================
//
// An N-bit integer iterative divider, capable of signed & unsigned division
// Code refactored based on Sam Larser's work
// -------------------------------------------
// Cycles       Operation
// -------------------------------------------
// 1            latch inputs
// 2            negate divisor (if necessary)
// 3            negate dividend (if necessary)
// 4            shift in msb of the dividend
// 5-37         iterate
// 38           repair remainder (if necessary)
// 39           negate remainder (if necessary)
// 40           negate quotient (if necessary)
// -------------------------------------------
//
// Schematic: https://docs.google.com/presentation/d/1F7Lam7fMCp-v9K1PsjTvypWHJFFXfqoX6pJrmgf-_JE/
//
// TODO
// 1. added register to hold the previous operands, if the current operands
//    are the same with prevous one, we can output the results instantly. This
//    is useful for a RISC ISA, in which only quotient or remainder is need in
//    one instruction.
// 2. using data detection logic to reduce the iteration cycles.
`include "bsg_defines.v"

module bsg_idiv_iterative #(parameter width_p=32, parameter bitstack_p=0, parameter bits_per_iter_p = 2)
    (input                  clk_i
    ,input                  reset_i

    ,input                  v_i      //there is a request
    ,output                 ready_and_o  //idiv is idle 

    ,input [width_p-1: 0]   dividend_i
    ,input [width_p-1: 0]   divisor_i
    ,input                  signed_div_i

    ,output                 v_o      //result is valid
    ,output [width_p-1: 0]  quotient_o
    ,output [width_p-1: 0]  remainder_o
    ,input                  yumi_i
    );


   wire [width_p:0] opA_r;
   assign remainder_o = opA_r[width_p-1:0];

   wire [width_p:0] opC_r;
   assign quotient_o = opC_r[width_p-1:0];

   wire         signed_div_r;
   wire divisor_msb  = signed_div_i & divisor_i[width_p-1];
   wire dividend_msb = signed_div_i & dividend_i[width_p-1];

   wire latch_signed_div_lo;
   bsg_dff_en#(.width_p(1)) req_reg
       (.data_i (signed_div_i)
       ,.data_o (signed_div_r)
       ,.en_i   (latch_signed_div_lo)
       ,.clk_i(clk_i)
        );

   //if the divisor is zero
   wire         zero_divisor_li   =  ~(| opA_r);

   wire         opA_sel_lo;
   wire [width_p:0]  opA_mux;
   wire [width_p:0]  add_out, csa2_out0, csa2_out1;
   wire 	     pg1_out, pg2_out;
   
   bsg_mux  #(.width_p(width_p+1), .els_p(2)) muxA
       (.data_i({ {divisor_msb, divisor_i}, add_out } )
       ,.data_o(opA_mux)
       ,.sel_i(opA_sel_lo)
     );
   
   wire [width_p:0]  opB_mux, opC_mux;
   wire [bits_per_iter_p + 1:0] opB_sel_lo, opC_sel_lo;
   
   if (bits_per_iter_p == 2) begin
      
      bsg_mux_one_hot #(.width_p(width_p+1), .els_p(4)) muxB
        (.data_i( {opC_r, add_out, {add_out[width_p-1:0], opC_r[width_p]}, {csa2_out0[width_p-1:0], opC_r[width_p-1]}} )
	,.data_o(  opB_mux )
	,.sel_one_hot_i(opB_sel_lo)
	);

      bsg_mux_one_hot #(.width_p(width_p+1), .els_p(4)) muxC
        (.data_i( {{dividend_msb, dividend_i},add_out, {opC_r[width_p-1:0],  ~add_out[width_p]}, {opC_r[width_p-2:0], ~pg1_out, ~pg2_out}})
        ,.data_o(  opC_mux )
        ,.sel_one_hot_i(opC_sel_lo)
        );
      
   end else begin

      bsg_mux_one_hot #(.width_p(width_p+1), .els_p(3)) muxB
        (.data_i( {opC_r, add_out, {add_out[width_p-1:0], opC_r[width_p]}} )
        ,.data_o( opB_mux )
        ,.sel_one_hot_i(opB_sel_lo)
        );

      bsg_mux_one_hot #(.width_p(width_p+1), .els_p(3)) muxC
        (.data_i( {{dividend_msb, dividend_i}, add_out, {opC_r[width_p-1:0], ~add_out[width_p]}} )
        ,.data_o( opC_mux )
	,.sel_one_hot_i(opC_sel_lo)
	);
       
  end
   
   wire opA_ld_lo;
   bsg_dff_en#(.width_p(width_p+1)) opA_reg
       (.data_i (opA_mux)
       ,.data_o (opA_r  )
       ,.en_i   (opA_ld_lo )
       ,.clk_i(clk_i)
       );
 
   wire         opB_ld_lo;
   wire [width_p:0]  opB_r;
   bsg_dff_en#(.width_p(width_p+1)) opB_reg
       (.data_i (opB_mux)
       ,.data_o (opB_r  )
       ,.en_i   (opB_ld_lo )
       ,.clk_i(clk_i)
       );

   wire opC_ld_lo;
   bsg_dff_en#(.width_p(width_p+1)) opC_reg
       (.data_i (opC_mux)
       ,.data_o (opC_r  )
       ,.en_i   (opC_ld_lo )
       ,.clk_i(clk_i)
       );

   wire csa_ld_lo; 
   wire [width_p:0] csa_r;
   if (bits_per_iter_p == 2) begin     
     bsg_dff_en#(.width_p(width_p+1)) csa_reg
         (.data_i (csa2_out1)
         ,.data_o (csa_r  )
         ,.en_i   (csa_ld_lo )
         ,.clk_i  (clk_i)
	 );
   end	 

  wire        opA_inv_lo;
  wire        opB_inv_lo;
  wire        opA_clr_lo;
  wire        opB_clr_lo;

  wire [width_p:0] add_in0;
  wire [width_p:0] add_in1;
  wire [width_p:0] csa1_in0, csa1_in1, csa1_in2, csa1_out0, csa1_out1;
  wire [width_p:0] csa2_in0, csa2_in1, csa2_in2;
  wire 	   csa_clr_lo;
   
   

  // this logic is sandwiched between bitstacks -- MBT
  if (bitstack_p) begin: bs

    wire [width_p:0] opA_xnor;
    bsg_xnor#(.width_p(width_p+1)) xnor_opA 
        (.a_i({(width_p+1){opA_inv_lo}})
        ,.b_i(opA_r)
        ,.o  (opA_xnor)
        ); 

    wire [width_p:0] opB_xnor;
    bsg_xnor#(.width_p(width_p+1)) xnor_opB 
        (.a_i({(width_p+1){opB_inv_lo}})
        ,.b_i(opB_r)
        ,.o  (opB_xnor)
        ); 

    bsg_nor2 #(.width_p(width_p+1)) nor_opA 
       ( .a_i( opA_xnor )
        ,.b_i({(width_p+1){~opA_clr_lo}})
        ,.o  (add_in0)
        );

    bsg_nor2 #(.width_p(width_p+1)) nor_opB 
       ( .a_i( opB_xnor )
        ,.b_i( {(width_p+1){~opB_clr_lo}})
        ,.o  (add_in1)
        );
     
    // fix this later
    if (bits_per_iter_p == 2) begin 
      bsg_xnor#(.width_p(width_p+1)) xnor_add1 
          (.a_i({(width_p+1){~add1_out[width_p]}})
          ,.b_i(opA_r)
          ,.o  (add2_in0)
          );
      assign add2_in1 = {add1_out[width_p-1:0], opC_r[width_p]};
    end
 
  end
  else begin: nbs
    
    if (bits_per_iter_p == 2) begin
      assign csa1_in0 = (opA_r ^ {width_p+1{opA_inv_lo}}) & {width_p+1{opA_clr_lo}};
      assign csa1_in1 = (opB_r ^ {width_p+1{opB_inv_lo}}) & {width_p+1{opB_clr_lo}};
      assign csa1_in2 = ({({width_p{csa_clr_lo}}  & csa_r[width_p-1:0]), opA_inv_lo});
      assign csa2_in0 = {csa1_out0[width_p-1:0], opC_r[width_p]};
      assign csa2_in1 = {csa1_out1[width_p-1:0], ~pg1_out};
      assign csa2_in2 = opA_r ^ {width_p+1{~pg1_out}};
    end 

    else begin
      assign add_in0 = (opA_r ^ {width_p+1{opA_inv_lo}}) & {width_p+1{opA_clr_lo}};
      assign add_in1 = (opB_r ^ {width_p+1{opB_inv_lo}}) & {width_p+1{opB_clr_lo}};	   
    end

  end   
  
  wire adder_cin_lo;
  bsg_adder_cin #(.width_p(width_p+1)) adder1
   (.a_i  (add_in0)
   ,.b_i  (add_in1)
   ,.cin_i(adder_cin_lo)
   ,.o    (add_out)
   );

  wire [1:0] fadd_mux0_sel_lo, fadd_mux1_sel_lo;
  wire g1_lo, g2_lo;

  /*genvar i, j;

  localparam int l_edge [width_p-2:0];
  localparam int r_edge [width_p-2:0];
  localparam int o_edge [width_p-2:0];
  
  for (i=0; i < width_log; i=i+1) begin
    for (j=0; j < 2**(width_p - 1 - i); j=j+1) begin
      assign r_edge[(2**(width_log - 1- i)) * (2**(i + 1) - 2) + j] = (2**(width_log - i)) * (2**(i + 1) - 2) + j*2;
      assign l_edge[(2**(width_log - 1- i)) * (2**(i + 1) - 2) + j] = (2**(width_log - i)) * (2**(i + 1) - 2) + j*2 + 1;
      assign o_edge[(2**(width_log - 1- i)) * (2**(i + 1) - 2) + j] = (2**(width_log - i - 1)) * (2**(i + 1) - 1) + j;
    end
  end*/
   
   
  if (bits_per_iter_p == 2) begin

   bsg_pg_tree #(.l_edge_p   ({61, 59, 57, 55, 53, 51, 49, 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 27, 25, 23, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1})
                 ,.r_edge_p  ({60, 58, 56, 54, 52, 50, 48, 46, 44, 42, 40, 38, 36, 34, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2, 0})
                 ,.o_edge_p  ({62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32})) prefix_tree1
      (.a_i(csa1_out0[width_p-1:0])
      ,.b_i(csa1_out1[width_p-1:0])
      ,.g_o(g1_lo)
      );
    /*bsg_pg_tree #(.l_edge_p   (l_edge)
		 ,.r_edge_p   (r_edge)
		 ,.o_edge_p   (o_edge)
		 ,.node_type_p({0,0,0})) prefix_tree1
            (.a_i(csa1_out0[width_p-1:0])
	    ,.b_i(csa1_out1[width_p-1:0])
	    ,.g_o(g1_lo)
	    );*/
     

    assign pg1_out = g1_lo ^ (csa1_out0[width_p] ^ csa1_out1[width_p]);    
     
    bsg_pg_tree #(.l_edge_p  ({61, 59, 57, 55, 53, 51, 49, 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 27, 25, 23, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1})
                 ,.r_edge_p  ({60, 58, 56, 54, 52, 50, 48, 46, 44, 42, 40, 38, 36, 34, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2, 0})
                 ,.o_edge_p  ({62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32})) prefix_tree2
      (.a_i(csa2_out0[width_p-1:0])
      ,.b_i(csa2_out1[width_p-1:0])
      ,.g_o(g2_lo)
      );

    /* bsg_pg_tree #(.l_edge_p   (l_edge)
		                    ,.r_edge_p   (r_edge)
		                    ,.o_edge_p   (o_edge)
		                    ,.node_type_p({0,0,0})) prefix_tree2
                   (.a_i(csa1_out0[width_p-1:0])
		                ,.b_i(csa1_out1[width_p-1:0])
		                ,.g_o(g1_lo)
		    );*/
     

    assign pg2_out = g2_lo ^ (csa2_out0[width_p] ^ csa2_out1[width_p]);

    // assign pg1_out = 1'b1;
    // assign pg2_out = 1'b1;
     
    bsg_adder_carry_save #(.width_p(width_p+1)) csa1
     (.a_i  (csa1_in0)
     ,.b_i  (csa1_in1)
     ,.c_i  (csa1_in2)
     ,.s_o  (csa1_out0)
     ,.c_o  (csa1_out1)
     );

    bsg_adder_carry_save #(.width_p(width_p+1)) csa2
      (.a_i  (csa2_in0)
      ,.b_i  (csa2_in1)
      ,.c_i  (csa2_in2)
      ,.s_o  (csa2_out0)
      ,.c_o  (csa2_out1)
      );

     
     bsg_mux_one_hot #(.width_p(width_p+1), .els_p(2)) fadd_mux0
        (.data_i( {csa1_out0, csa1_in0} )
	,.data_o( add_in0 )
	,.sel_one_hot_i(fadd_mux0_sel_lo)
	);
     
     bsg_mux_one_hot #(.width_p(width_p+1), .els_p(2)) fadd_mux1
        (.data_i( {csa1_out1, csa1_in1} )
        ,.data_o( add_in1 )
        ,.sel_one_hot_i(fadd_mux1_sel_lo)
	);
     
  end
   
  bsg_idiv_iterative_controller #(.width_p(width_p), .bits_per_iter_p(bits_per_iter_p)) control 
     ( .reset_i                  (reset_i)
      ,.clk_i                    (clk_i)

      ,.v_i                      (v_i)
      ,.ready_and_o              (ready_and_o)

      ,.zero_divisor_i           (zero_divisor_li)
      ,.signed_div_r_i           (signed_div_r)
      ,.adder_result_is_neg_i    (add_out[width_p])
      ,.csa_result_is_neg_i      (pg2_out)
      ,.opA_is_neg_i             (opA_r[width_p])
      ,.opC_is_neg_i             (opC_r[width_p])

      ,.opA_sel_o                (opA_sel_lo)
      ,.opA_ld_o                 (opA_ld_lo)
      ,.opA_inv_o                (opA_inv_lo)
      ,.opA_clr_l_o              (opA_clr_lo)

      ,.opB_sel_o                (opB_sel_lo)
      ,.opB_ld_o                 (opB_ld_lo)
      ,.opB_inv_o                (opB_inv_lo)
      ,.opB_clr_l_o              (opB_clr_lo)

      ,.opC_sel_o                (opC_sel_lo)
      ,.opC_ld_o                 (opC_ld_lo)

      ,.csa_ld_o                 (csa_ld_lo)
      ,.csa_clr_o                (csa_clr_lo)
       
      ,.fadd_mux0_sel_o          (fadd_mux0_sel_lo)
      ,.fadd_mux1_sel_o          (fadd_mux1_sel_lo)

      ,.latch_signed_div_o       (latch_signed_div_lo)
      ,.adder1_cin_o             (adder_cin_lo)

      ,.v_o(v_o)
      ,.yumi_i(yumi_i)
     );
endmodule // divide
