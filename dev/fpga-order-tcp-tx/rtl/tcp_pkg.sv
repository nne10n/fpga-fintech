// -----------------------------------------------------------------------------
// tcp_pkg.sv — Shared types/constants for the minimal TCP order-send core
// -----------------------------------------------------------------------------
package tcp_pkg;

  typedef enum logic [3:0] {
    ST_CLOSED      = 4'd0,
    ST_SYN_SENT    = 4'd1,
    ST_ESTABLISHED = 4'd2,
    ST_FIN_WAIT_1  = 4'd3,
    ST_TIME_WAIT   = 4'd4,
    ST_ERROR       = 4'd15
  } tcp_state_e;

  typedef enum logic [2:0] {
    TX_IDLE     = 3'd0,
    TX_BUILD    = 3'd1,
    TX_EMIT     = 3'd2,
    TX_WAIT_RDY = 3'd3
  } tx_phase_e;

  typedef enum logic [2:0] {
    PKT_NONE    = 3'd0,
    PKT_SYN     = 3'd1,
    PKT_ACK     = 3'd2,
    PKT_DATA    = 3'd3,
    PKT_FIN     = 3'd4
  } pkt_kind_e;

  // TCP flag bits (wire order in flags byte)
  localparam logic [7:0] TCP_FIN = 8'h01;
  localparam logic [7:0] TCP_SYN = 8'h02;
  localparam logic [7:0] TCP_RST = 8'h04;
  localparam logic [7:0] TCP_PSH = 8'h08;
  localparam logic [7:0] TCP_ACK = 8'h10;
  localparam logic [7:0] TCP_URG = 8'h20;

  localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
  localparam logic [7:0]  IP_PROTO_TCP   = 8'd6;

  // Ones' complement add of two 16-bit values (with end-around carry)
  function automatic logic [15:0] ocadd16(input logic [15:0] a, input logic [15:0] b);
    logic [16:0] s;
    s = {1'b0, a} + {1'b0, b};
    ocadd16 = s[15:0] + {15'd0, s[16]};
  endfunction

  // Fold a 32-bit sum into 16-bit ones' complement
  function automatic logic [15:0] fold32(input logic [31:0] s);
    logic [16:0] t;
    t = {1'b0, s[31:16]} + {1'b0, s[15:0]};
    fold32 = t[15:0] + {15'd0, t[16]};
  endfunction

  // Final internet checksum from accumulator (invert)
  function automatic logic [15:0] finalize_csum(input logic [31:0] acc);
    finalize_csum = ~fold32(acc);
  endfunction

  // Add one big-endian 16-bit word into a 32-bit ones' complement accumulator
  function automatic logic [31:0] acc_add16(input logic [31:0] acc, input logic [15:0] w);
    logic [32:0] s;
    s = {1'b0, acc} + {17'd0, w};
    // Keep carrying into high so fold32 can finish later; also fold lightly
    acc_add16 = s[31:0] + {31'd0, s[32]};
  endfunction

  // Add a byte into accumulator given odd/even position (network order)
  // even_byte=1 means this is the high byte of a 16-bit word (byte offset even)
  function automatic logic [31:0] acc_add8(
      input logic [31:0] acc,
      input logic [7:0]  b,
      input logic        even_byte
  );
    if (even_byte)
      acc_add8 = acc_add16(acc, {b, 8'h00});
    else
      acc_add8 = acc_add16(acc, {8'h00, b});
  endfunction

endpackage
