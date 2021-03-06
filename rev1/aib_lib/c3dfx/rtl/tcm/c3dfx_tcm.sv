// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2019 Intel Corporation. 
// *****************************************************************************
// *****************************************************************************
// Copyright © 2016 Altera Corporation. 
// *****************************************************************************
//  Module Name :  c3dfx_tcm
//  Date        :  Tue May 9 2016
//  Description :  Test clock macro
// *****************************************************************************

/*
i_tcm_mode[3:0]
0 - Functional Mode

ATPG Modes:
1 – func_clk 1 pulse
2 – func_clk 2 pulse
3 – func_clk 3 pulse
4 – test_ref_clk 1 pulse
5 – test_ref_clk 2 pulse
6 – test_ref_clk 3 pulse
7 – Scan clock only
8 – func_clk capture

MBIST or 
other test modes:
9 – func_clk enable
10 – test_ref_clk enable
11 – scan_clk enable
*/

module c3dfx_tcm (
  input  logic i_func_clk,
  input  logic i_test_clk,
  input  logic i_scan_clk,
  input  logic i_func_clken,

  // DFT Controls
  input  logic i_scan_mode,
  input  logic i_scan_enable,
  input  logic i_capture_enable,
  input  logic [3:0] i_tcm_mode,
  output logic o_clk
);

  logic capture_trigger;
  logic sync_capture_trigger;
  logic sync_capture_trigger_1d;
  logic sync_capture_trigger_2d;
  logic sync_capture_trigger_3d;
  logic enable_one_pulse;
  logic enable_two_pulse;
  logic enale_three_pulse;
  logic inclk;
  logic inclk_sel;
  logic clken;
  logic scan_clken;
  logic mux_out_clk;
  logic scan_enable_neg;
  logic scan_enable_inclk;

  assign inclk_sel = (i_tcm_mode == 4'd4) | (i_tcm_mode == 4'd5) | (i_tcm_mode == 4'd6) | (i_tcm_mode == 4'd10);

  c3lib_mux2_ctn uu_c3dfx_testclk_mux  (.ck0(i_func_clk),
                                        .ck1(i_test_clk),
                                        .s0(inclk_sel),
                                        .ck_out(inclk));

  // trigger generated by scanclk and low scan enable
  always @(posedge i_scan_clk or negedge i_scan_mode)
    if(~i_scan_mode)
      capture_trigger <= 1'b0;
    else
      capture_trigger <= ~i_scan_enable & i_capture_enable;

  // trigger needs to get synchronized to the fast clock domain
  c3lib_bitsync uu_c3dfx_bitsync (.clk(inclk),
                                  .rst_n(i_scan_mode),
                                  .data_in(capture_trigger),
                                  .data_out(sync_capture_trigger));

  // Then shift it for count purposes
  always @(posedge inclk or negedge i_scan_mode) begin
    if(~i_scan_mode) begin
      sync_capture_trigger_1d <= 1'b0;
      sync_capture_trigger_2d <= 1'b0;
      sync_capture_trigger_3d <= 1'b0;
    end
    else begin
      sync_capture_trigger_1d <= sync_capture_trigger;
      sync_capture_trigger_2d <= sync_capture_trigger_1d;
      sync_capture_trigger_3d <= sync_capture_trigger_2d;
    end
  end

  // The trigger is not evaluated when scan_enable is high.  Once scan_enable goes low the trigger gets set and stays set until it goes high again.

  // We enable the fast clock for 1 or 2 or 3 cycles that the trigger is high.

  assign enable_one_pulse = ((i_tcm_mode == 4'd1) | (i_tcm_mode == 4'd4)) &
                            sync_capture_trigger & ~sync_capture_trigger_1d;

  assign enable_two_pulse = ((i_tcm_mode == 4'd2) | (i_tcm_mode == 4'd5)) &
                            sync_capture_trigger & ~sync_capture_trigger_2d;

  assign enale_three_pulse = ((i_tcm_mode == 4'd3) | (i_tcm_mode == 4'd6)) &
                            sync_capture_trigger & ~sync_capture_trigger_3d;



  // TO avoid a runt clock pulse when switching scanenable from 1->0, we need to syncronize the incoming
  //async i_scan_enable, and use a negeage flop to ensure it changes when inclk is low (scan_clk is a controlled pin) 
  c3lib_bitsync uu_c3dfx_scan_enable (.clk(inclk),
                                  .rst_n(i_scan_mode),
                                  .data_in(i_scan_enable),
                                  .data_out(scan_enable_inclk));
                                  
  //launch off the negedge to ensure that the inclk is low, and now glitch happens                                 
  always @(negedge inclk or negedge i_scan_mode) begin
    if(~i_scan_mode) begin
      scan_enable_neg <= 1'b0;
    end
    else begin
      scan_enable_neg <= scan_enable_inclk;
    end
  end

  assign clken = (i_tcm_mode == 4'd0) ? i_func_clken :
                 (enable_one_pulse | enable_two_pulse | enale_three_pulse |
                  (((i_tcm_mode == 4'd7) | (i_tcm_mode == 4'd8)) & ~i_scan_enable & i_capture_enable) |
                  (i_tcm_mode == 4'd9) | (i_tcm_mode == 4'd10) | (i_tcm_mode == 4'd11));

  //assign scan_clken = i_scan_enable | (i_tcm_mode == 4'd7) | (i_tcm_mode == 4'd11);
  assign scan_clken = scan_enable_neg | (i_tcm_mode == 4'd7) | (i_tcm_mode == 4'd11);

c3lib_mux2_ctn uu_c3dfx_scanclk_mux (.ck0(inclk),
                                     .ck1(i_scan_clk),
                                     .s0(scan_clken),
                                     .ck_out(mux_out_clk));

c3lib_ckg_posedge_ctn clk_out_gater (.clk(mux_out_clk),
                                     .clk_en(clken),
                                     .tst_en(scan_enable_neg),
                                     .gated_clk(o_clk));
 
endmodule // c3lib_tcm

