// cnn_pkg.sv — types & helpers for 1D-CNN engine (impl-glm53)
// Quant order (microarch §0.3): MAC → scale/shift → sat INT16 → ReLU
`timescale 1ns / 1ps
package cnn_pkg;
  localparam int WIN_LEN     = 2048;
  localparam int N_CLASS     = 10;
  localparam int WGT_WORDS   = 11504;
  localparam int FEAT_MAX    = 8192; // 512*16

  // Weight layout offsets (INT16 words) — weight_map.json / WeightLayout
  localparam int O_C1W  = 0;
  localparam int O_C1B  = 256;
  localparam int O_C1SM = 272;
  localparam int O_C1SS = 288;
  localparam int O_C2W  = 304;
  localparam int O_C2B  = 4400;
  localparam int O_C2SM = 4432;
  localparam int O_C2SS = 4464;
  localparam int O_C3W  = 4496;
  localparam int O_C3B  = 10640;
  localparam int O_C3SM = 10704;
  localparam int O_C3SS = 10768;
  localparam int O_GAPM = 10832;
  localparam int O_GAPS = 10833;
  localparam int O_FCW  = 10834;
  localparam int O_FCB  = 11474;
  localparam int O_FCSM = 11484;
  localparam int O_FCSS = 11494;

  typedef logic signed [15:0] act_t;
  typedef logic signed [15:0] wgt_t;
  typedef logic signed [31:0] acc_t;
  typedef logic signed [15:0] score_t;

  function automatic act_t sat_i16(input acc_t x);
    if (x > 32'sd32767) return 16'sd32767;
    else if (x < -32'sd32768) return -16'sd32768;
    else return act_t'(x[15:0]);
  endfunction

  function automatic act_t relu_i16(input act_t x);
    return (x < 0) ? 16'sd0 : x;
  endfunction

  // Sample with left pad (zero outside)
  function automatic act_t sample_at(
      input act_t in_mem [0:FEAT_MAX-1],
      input int rin, input int cin,
      input int t, input int c, input int pad_l);
    int idx;
    idx = t - pad_l;
    if (idx < 0 || idx >= rin) return 16'sd0;
    return in_mem[idx * cin + c];
  endfunction
endpackage
