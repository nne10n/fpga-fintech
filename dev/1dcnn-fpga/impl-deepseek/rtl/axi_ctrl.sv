`default_nettype none
//==============================================================================
// axi_ctrl — AXI4-Lite slave + full register file (Phase1 arch §5.3)
//==============================================================================
`timescale 1ns/1ps
module axi_ctrl #(
    parameter C_S_AXI_ADDR_WIDTH = 8,
    parameter C_S_AXI_DATA_WIDTH = 32
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    // AXI4-Lite
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg [1:0]   s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg [31:0]  s_axi_rdata,
    output reg [1:0]   s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    // Status inputs from pipeline
    input  wire        busy,
    input  wire        done_pulse,
    input  wire        err_pulse,
    input  wire        fifo_ovfl,
    input  wire        weight_ok,
    input  wire [7:0]  err_code_in,
    input  wire [31:0] cyc_cnt_in,
    input  wire [31:0] score_snap [0:9],
    // Controls out
    output wire        eng_en,
    output wire        capt_en,
    output wire        soft_rst,
    output wire        fir_bypass,
    output wire        irq_en,
    output wire [31:0] win_len,
    output wire [31:0] win_hop,
    output wire [1:0]  fs_sel,
    output wire [1:0]  ch_sel,
    output wire        weight_load_en,
    output wire        bank_sel,
    output wire [31:0] weight_words,
    output wire [15:0] weight_data,
    output wire        weight_data_we,
    output wire        irq
);
    localparam REG_ID_MAGIC = 32'h1DC0_0101; // doc 0x1DCN0101 (N→0)

    reg [31:0] r_ctrl;
    reg [31:0] r_ier;
    reg [31:0] r_win_len;
    reg [31:0] r_win_hop;
    reg [31:0] r_fs_sel;
    reg [31:0] r_ch_sel;
    reg [31:0] r_weight_base;
    reg [31:0] r_weight_words;
    reg [31:0] r_weight_ctrl;
    reg [31:0] r_score_base;
    reg [31:0] r_rsvd [0:14];
    reg        done_sticky, err_sticky;
    reg [31:0] win_cnt;
    reg [7:0]  err_code;
    reg [31:0] cyc_cnt;
    reg        wdata_we_pulse;
    reg [15:0] wdata_lo;

    wire feat_hotswap = 1'b0; // V1
    wire [31:0] status_w = {26'd0, feat_hotswap, weight_ok, fifo_ovfl,
                            err_sticky, done_sticky, busy};

    assign eng_en    = r_ctrl[0];
    assign capt_en   = r_ctrl[1];
    assign soft_rst  = r_ctrl[2];
    assign fir_bypass= r_ctrl[3];
    assign irq_en    = r_ctrl[4];
    assign win_len   = r_win_len;
    assign win_hop   = r_win_hop;
    assign fs_sel    = r_fs_sel[1:0];
    assign ch_sel    = r_ch_sel[1:0];
    assign weight_load_en = r_weight_ctrl[0];
    assign bank_sel  = r_weight_ctrl[1];
    assign weight_words = r_weight_words;
    assign weight_data = wdata_lo;
    assign weight_data_we = wdata_we_pulse;
    assign irq = irq_en & done_sticky;

    // AXI write
    reg aw_hs, w_hs;
    reg [7:0] awaddr_r;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            s_axi_awready<=0; s_axi_wready<=0; s_axi_bvalid<=0; s_axi_bresp<=0;
            aw_hs<=0; w_hs<=0; awaddr_r<=0;
            r_ctrl<=0; r_ier<=0; r_win_len<=2048; r_win_hop<=2048;
            r_fs_sel<=1; r_ch_sel<=0; r_weight_base<=0; r_weight_words<=0;
            r_weight_ctrl<=0; r_score_base<=0;
            done_sticky<=0; err_sticky<=0; win_cnt<=0; err_code<=0; cyc_cnt<=0;
            wdata_we_pulse<=0; wdata_lo<=0;
        end else begin
            wdata_we_pulse <= 1'b0;
            if (done_pulse) begin done_sticky<=1'b1; win_cnt<=win_cnt+1; cyc_cnt<=cyc_cnt_in; end
            if (err_pulse)  begin err_sticky<=1'b1; err_code<=err_code_in; end

            s_axi_awready <= (!aw_hs) && s_axi_awvalid;
            if (s_axi_awready && s_axi_awvalid) begin aw_hs<=1; awaddr_r<=s_axi_awaddr[7:0]; end
            s_axi_wready <= (!w_hs) && s_axi_wvalid;
            if (s_axi_wready && s_axi_wvalid) w_hs<=1;

            if (aw_hs && w_hs && !s_axi_bvalid) begin
                case (awaddr_r)
                    8'h04: r_ctrl <= s_axi_wdata;
                    8'h0C: begin // IER / W1C sticky clear
                        if (s_axi_wdata[1]) done_sticky<=0;
                        if (s_axi_wdata[2]) err_sticky<=0;
                        r_ier <= s_axi_wdata;
                    end
                    8'h10: r_win_len <= s_axi_wdata;
                    8'h14: r_win_hop <= s_axi_wdata;
                    8'h18: r_fs_sel <= s_axi_wdata;
                    8'h1C: r_ch_sel <= s_axi_wdata;
                    8'h20: r_weight_base <= s_axi_wdata;
                    8'h24: r_weight_words <= s_axi_wdata;
                    8'h28: r_weight_ctrl <= s_axi_wdata;
                    8'h2C: begin
                        wdata_lo <= s_axi_wdata[15:0];
                        wdata_we_pulse <= 1'b1;
                    end
                    8'h40: r_score_base <= s_axi_wdata;
                    default: begin
                        if (awaddr_r >= 8'h44 && awaddr_r <= 8'h7C && awaddr_r[1:0]==2'b00)
                            r_rsvd[(awaddr_r-8'h44)>>2] <= s_axi_wdata;
                    end
                endcase
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                aw_hs<=0; w_hs<=0;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
        end
    end

    // AXI read
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            s_axi_arready<=0; s_axi_rvalid<=0; s_axi_rdata<=0; s_axi_rresp<=0;
        end else begin
            s_axi_arready <= (!s_axi_rvalid) && s_axi_arvalid;
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                case (s_axi_araddr[7:0])
                    8'h00: s_axi_rdata <= REG_ID_MAGIC;
                    8'h04: s_axi_rdata <= r_ctrl;
                    8'h08: s_axi_rdata <= status_w;
                    8'h0C: s_axi_rdata <= r_ier;
                    8'h10: s_axi_rdata <= r_win_len;
                    8'h14: s_axi_rdata <= r_win_hop;
                    8'h18: s_axi_rdata <= r_fs_sel;
                    8'h1C: s_axi_rdata <= r_ch_sel;
                    8'h20: s_axi_rdata <= r_weight_base;
                    8'h24: s_axi_rdata <= r_weight_words;
                    8'h28: s_axi_rdata <= {29'd0, 1'b0 /*bank_active*/, r_weight_ctrl[1:0]};
                    8'h30: s_axi_rdata <= cyc_cnt;
                    8'h34: s_axi_rdata <= win_cnt;
                    8'h38: s_axi_rdata <= {24'd0, err_code};
                    8'h3C: s_axi_rdata <= {31'd0, done_sticky};
                    8'h40: s_axi_rdata <= r_score_base;
                    8'h80: s_axi_rdata <= score_snap[0];
                    8'h84: s_axi_rdata <= score_snap[1];
                    8'h88: s_axi_rdata <= score_snap[2];
                    8'h8C: s_axi_rdata <= score_snap[3];
                    8'h90: s_axi_rdata <= score_snap[4];
                    8'h94: s_axi_rdata <= score_snap[5];
                    8'h98: s_axi_rdata <= score_snap[6];
                    8'h9C: s_axi_rdata <= score_snap[7];
                    8'hA0: s_axi_rdata <= score_snap[8];
                    8'hA4: s_axi_rdata <= score_snap[9];
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
        end
    end
endmodule
