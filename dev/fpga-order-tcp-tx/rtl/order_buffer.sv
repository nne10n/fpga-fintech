// -----------------------------------------------------------------------------
// order_buffer.sv — Host-side order payload buffer (发单 API storage)
// Toy binary order: opaque bytes, max MAX_PAYLOAD. Load via byte writes, then
// pulse send at the TCP client layer.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module order_buffer #(
  parameter int MAX_PAYLOAD = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  // Host load interface
  input  logic        order_we,
  input  logic [15:0] order_addr,
  input  logic [7:0]  order_wdata,
  input  logic        order_len_we,
  input  logic [15:0] order_len_wdata,
  output logic [15:0] order_len,

  // Clear buffer length
  input  logic        order_clear,

  // Read port for TX engine
  input  logic [15:0] pl_addr,
  output logic [7:0]  pl_data
);

  logic [7:0] mem [0:MAX_PAYLOAD-1];

  assign pl_data = (pl_addr < MAX_PAYLOAD) ? mem[pl_addr] : 8'h00;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      order_len <= '0;
    end else begin
      if (order_clear)
        order_len <= '0;
      else if (order_len_we)
        order_len <= (order_len_wdata > MAX_PAYLOAD) ? MAX_PAYLOAD[15:0]
                                                     : order_len_wdata;

      if (order_we && order_addr < MAX_PAYLOAD)
        mem[order_addr] <= order_wdata;
    end
  end

endmodule
