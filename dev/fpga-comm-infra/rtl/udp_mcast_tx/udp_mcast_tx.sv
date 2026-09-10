`timescale 1ns/1ps
`default_nettype none

// S2 UDP multicast TX — G1 FROZEN (design/comm-infra-step1-design.md)
// Role A: o_s_axis_tready ≡ 1; MAC pause never backpressures producer.
// No ARP. On-wire DA = RFC1112(dip) always (cfg_map_en does not admit user MAC).
// payload_len ∈ [1,511]. ttl==0 / CSR 0 → 1. Group address/ports via CSR/meta only.
module udp_mcast_tx (
    input  wire             sys_clk,
    input  wire             sys_rst_n,

    input  wire [47:0]      cfg_src_mac,
    input  wire [31:0]      cfg_src_ip,
    input  wire [31:0]      cfg_dst_ip,
    input  wire [15:0]      cfg_src_port,
    input  wire [15:0]      cfg_dst_port,
    input  wire [7:0]       cfg_ttl_default,
    input  wire             cfg_map_en,
    input  wire [8:0]       cfg_mtu_pay,

    input  wire             i_meta_valid,
    input  wire [31:0]      i_meta_dst_ip,
    input  wire [31:0]      i_meta_src_ip,
    input  wire [15:0]      i_meta_dst_port,
    input  wire [15:0]      i_meta_src_port,
    input  wire [7:0]       i_meta_ttl,
    input  wire [15:0]      i_meta_payload_len,
    input  wire             i_meta_is_mcast,

    input  wire [63:0]      i_s_axis_tdata,
    input  wire [7:0]       i_s_axis_tkeep,
    input  wire             i_s_axis_tvalid,
    input  wire             i_s_axis_tlast,
    output wire             o_s_axis_tready,

    output logic [63:0]     o_m_axis_tdata,
    output logic [7:0]      o_m_axis_tkeep,
    output logic            o_m_axis_tvalid,
    output logic            o_m_axis_tlast,
    input  wire             i_m_axis_tready,

    output logic            o_fail_sticky,
    output logic [31:0]     o_drop_cnt,
    output logic [31:0]     o_nosend_cnt,
    output logic [31:0]     o_tx_ok_cnt,
    output logic            o_map_en_live,
    (* keep *) output logic [1:0] o_dbg_cs_state
);

    localparam integer P_HDR      = 42;
    localparam integer P_MAX_PAY  = 511;
    localparam [1:0]   ST_IDLE    = 2'd0;
    localparam [1:0]   ST_TAKE    = 2'd1;
    localparam [1:0]   ST_ARM     = 2'd2;
    localparam [1:0]   ST_EMIT    = 2'd3;

    assign o_s_axis_tready  = 1'b1;
    assign o_map_en_live    = cfg_map_en;

    function automatic [3:0] f_keep_len;
        input [7:0] k;
        integer i;
        begin
            f_keep_len = 4'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (k[i]) begin
                    f_keep_len = i[3:0] + 4'd1;
                end
            end
        end
    endfunction

    function automatic [15:0] f_add1c;
        input [15:0] a;
        input [15:0] b;
        reg   [16:0] s;
        begin
            s = {1'b0, a} + {1'b0, b};
            f_add1c = s[15:0] + {15'd0, s[16]};
        end
    endfunction

    function automatic [15:0] f_ipv4_csum;
        input [15:0] tot_len;
        input [7:0]  ttl;
        input [31:0] sip;
        input [31:0] dip;
        reg   [15:0] s;
        begin
            s = 16'h4500;
            s = f_add1c(s, tot_len);
            s = f_add1c(s, 16'h0000);
            s = f_add1c(s, 16'h0000);
            s = f_add1c(s, {ttl, 8'd17});
            s = f_add1c(s, 16'h0000);
            s = f_add1c(s, sip[31:16]);
            s = f_add1c(s, sip[15:0]);
            s = f_add1c(s, dip[31:16]);
            s = f_add1c(s, dip[15:0]);
            f_ipv4_csum = ~s;
        end
    endfunction

    function automatic [47:0] f_rfc1112;
        input [31:0] dip;
        begin
            f_rfc1112 = {24'h01005E, 1'b0, dip[22:0]};
        end
    endfunction

    function automatic f_is_mcast_ip;
        input [31:0] ip;
        begin
            f_is_mcast_ip = (ip[31:28] == 4'hE);
        end
    endfunction

    wire [8:0]  w_mtu_eff      = (cfg_mtu_pay == 9'd0) ? 9'd511 : cfg_mtu_pay;
    wire [7:0]  w_ttl_csr      = (cfg_ttl_default == 8'd0) ? 8'd1 : cfg_ttl_default;
    wire [7:0]  w_ttl_meta     = (i_meta_ttl == 8'd0) ? 8'd1 : i_meta_ttl;
    wire [31:0] w_sop_dst_ip   = i_meta_valid ? i_meta_dst_ip   : cfg_dst_ip;
    wire [31:0] w_sop_src_ip   = i_meta_valid ? i_meta_src_ip   : cfg_src_ip;
    wire [15:0] w_sop_dport    = i_meta_valid ? i_meta_dst_port : cfg_dst_port;
    wire [15:0] w_sop_sport    = i_meta_valid ? i_meta_src_port : cfg_src_port;
    wire [7:0]  w_sop_ttl      = i_meta_valid ? w_ttl_meta      : w_ttl_csr;
    wire        w_sop_is_mcast = i_meta_valid ? i_meta_is_mcast : f_is_mcast_ip(cfg_dst_ip);
    wire        w_meta_len_ok  = (i_meta_payload_len >= 16'd1) &&
                                 (i_meta_payload_len <= 16'd511) &&
                                 (i_meta_payload_len <= {7'd0, w_mtu_eff});
    wire        w_mcast_ok     = w_sop_is_mcast && f_is_mcast_ip(w_sop_dst_ip);
    wire        w_sop_take_ok  = w_mcast_ok && (i_meta_valid ? w_meta_len_ok : 1'b1);

    wire [3:0]  w_beat_len     = f_keep_len(i_s_axis_tkeep);
    wire        w_fire         = i_s_axis_tvalid;

    logic [1:0]  cs_state;
    logic [1:0]  ns_state;
    assign o_dbg_cs_state = cs_state;
    logic        r_in_pkt;
    logic        r_dropping;
    logic        r_busy_drop;
    logic        r_use_meta;
    logic        r_bad;

    logic [31:0] r_lock_dst_ip;
    logic [31:0] r_lock_src_ip;
    logic [15:0] r_lock_dport;
    logic [15:0] r_lock_sport;
    logic [7:0]  r_lock_ttl;
    logic [8:0]  r_lock_paylen;
    logic [47:0] r_lock_sa;
    logic [8:0]  r_wptr;
    logic [7:0]  r_pay_bytes [0:510];
    logic [7:0]  r_hdr_bytes [0:41];
    logic [15:0] r_emit_off;
    logic [15:0] r_frame_len;

    wire         w_sop         = w_fire && !r_in_pkt;
    wire [8:0]   w_next_wptr   = r_wptr + {5'd0, w_beat_len};

    wire [15:0]  w_ip_tot      = 16'd28 + {7'd0, r_lock_paylen};
    wire [15:0]  w_udp_len     = 16'd8  + {7'd0, r_lock_paylen};
    wire [15:0]  w_ip_csum     = f_ipv4_csum(w_ip_tot, r_lock_ttl, r_lock_src_ip, r_lock_dst_ip);
    wire [47:0]  w_da          = f_rfc1112(r_lock_dst_ip);

    wire         w_arm_pay_ok  = (r_lock_paylen >= 9'd1) &&
                                 (r_lock_paylen <= 9'd511) &&
                                 (r_lock_paylen <= w_mtu_eff) &&
                                 (r_wptr == r_lock_paylen);

    wire         w_emit_hs     = o_m_axis_tvalid && i_m_axis_tready;
    wire         w_emit_done   = w_emit_hs && o_m_axis_tlast;

    // process 2: next-state — writes only ns_state
    always_comb begin
        ns_state = cs_state;
        case (cs_state)
            ST_IDLE: begin
                if (w_sop && w_sop_take_ok) begin
                    ns_state = i_s_axis_tlast ? ST_ARM : ST_TAKE;
                end
            end
            ST_TAKE: begin
                if (w_fire && i_s_axis_tlast) begin
                    ns_state = (r_bad || (w_next_wptr > 9'd511)) ? ST_IDLE : ST_ARM;
                end
            end
            ST_ARM: begin
                ns_state = w_arm_pay_ok ? ST_EMIT : ST_IDLE;
            end
            ST_EMIT: begin
                if (w_emit_done) begin
                    ns_state = ST_IDLE;
                end
            end
            default: ns_state = ST_IDLE;
        endcase
    end

    // process 1: state register — writes only cs_state
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cs_state <= ST_IDLE;
        end else begin
            cs_state <= ns_state;
        end
    end

    integer i_b;
    logic [15:0] w_idx;
    logic [7:0]  w_out_keep;
    logic        w_out_last;
    logic [63:0] w_out_data;
    logic [7:0]  w_byte_sel;

    always_comb begin
        w_out_keep = 8'h00;
        w_out_last = 1'b0;
        w_out_data = 64'd0;
        w_byte_sel = 8'd0;
        w_idx      = 16'd0;
        for (i_b = 0; i_b < 8; i_b = i_b + 1) begin
            w_idx = r_emit_off + i_b[15:0];
            if ((cs_state == ST_EMIT) && (w_idx < r_frame_len)) begin
                w_out_keep = w_out_keep | (8'd1 << i_b);
                if (w_idx < 16'd42) begin
                    w_byte_sel = r_hdr_bytes[w_idx[5:0]];
                end else if ((w_idx - 16'd42) < 16'd511) begin
                    w_byte_sel = r_pay_bytes[(w_idx - 16'd42)];
                end else begin
                    w_byte_sel = 8'd0;
                end
                w_out_data = w_out_data | ({56'd0, w_byte_sel} << (i_b * 8));
            end
        end
        w_out_last = (cs_state == ST_EMIT) && ((r_emit_off + 16'd8) >= r_frame_len);
    end

    integer bi;
    integer hi;

    // process 3: datapath / outputs
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            r_in_pkt        <= 1'b0;
            r_dropping      <= 1'b0;
            r_busy_drop     <= 1'b0;
            r_use_meta      <= 1'b0;
            r_bad           <= 1'b0;
            r_wptr          <= 9'd0;
            r_emit_off      <= 16'd0;
            r_frame_len     <= 16'd0;
            r_lock_dst_ip   <= 32'd0;
            r_lock_src_ip   <= 32'd0;
            r_lock_dport    <= 16'd0;
            r_lock_sport    <= 16'd0;
            r_lock_ttl      <= 8'd1;
            r_lock_paylen   <= 9'd0;
            r_lock_sa       <= 48'd0;
            o_m_axis_tdata  <= 64'd0;
            o_m_axis_tkeep  <= 8'd0;
            o_m_axis_tvalid <= 1'b0;
            o_m_axis_tlast  <= 1'b0;
            o_fail_sticky   <= 1'b0;
            o_drop_cnt      <= 32'd0;
            o_nosend_cnt    <= 32'd0;
            o_tx_ok_cnt     <= 32'd0;
            for (hi = 0; hi < P_HDR; hi = hi + 1) begin
                r_hdr_bytes[hi] <= 8'd0;
            end
        end else begin
            if (w_fire) begin
                r_in_pkt <= !i_s_axis_tlast;
            end

            if (r_dropping && w_fire && i_s_axis_tlast) begin
                r_dropping <= 1'b0;
            end
            if (r_busy_drop && w_fire && i_s_axis_tlast) begin
                r_busy_drop <= 1'b0;
            end

            // Role A: during EMIT/ARM/TAKE-busy, new SOP is dropped, never stalled
            if ((cs_state != ST_IDLE) && w_sop) begin
                o_fail_sticky <= 1'b1;
                o_drop_cnt    <= o_drop_cnt + 32'd1;
                r_busy_drop   <= !i_s_axis_tlast;
            end

            case (cs_state)
                ST_IDLE: begin
                    o_m_axis_tvalid <= 1'b0;
                    o_m_axis_tlast  <= 1'b0;
                    r_emit_off      <= 16'd0;
                    r_frame_len     <= 16'd0;
                    if (w_sop) begin
                        if (!w_sop_take_ok) begin
                            o_fail_sticky <= 1'b1;
                            o_drop_cnt    <= o_drop_cnt + 32'd1;
                            o_nosend_cnt  <= o_nosend_cnt + 32'd1;
                            r_dropping    <= !i_s_axis_tlast;
                            r_wptr        <= 9'd0;
                        end else begin
                            r_lock_dst_ip <= w_sop_dst_ip;
                            r_lock_src_ip <= w_sop_src_ip;
                            r_lock_dport  <= w_sop_dport;
                            r_lock_sport  <= w_sop_sport;
                            r_lock_ttl    <= w_sop_ttl;
                            r_lock_sa     <= cfg_src_mac;
                            r_use_meta    <= i_meta_valid;
                            r_bad         <= 1'b0;
                            r_lock_paylen <= i_meta_valid ? i_meta_payload_len[8:0] : {5'd0, w_beat_len};
                            r_wptr        <= {5'd0, w_beat_len};
                            for (bi = 0; bi < 8; bi = bi + 1) begin
                                if (bi[3:0] < w_beat_len) begin
                                    r_pay_bytes[bi[8:0]] <= i_s_axis_tdata[bi*8 +: 8];
                                end
                            end
                        end
                    end
                end
                ST_TAKE: begin
                    if (w_fire && !r_busy_drop) begin
                        if (w_next_wptr > 9'd511) begin
                            o_fail_sticky <= 1'b1;
                            o_drop_cnt    <= o_drop_cnt + 32'd1;
                            o_nosend_cnt  <= o_nosend_cnt + 32'd1;
                            r_dropping    <= !i_s_axis_tlast;
                            r_bad         <= 1'b1;
                            r_wptr        <= 9'd0;
                        end else begin
                            for (bi = 0; bi < 8; bi = bi + 1) begin
                                if ((bi[3:0] < w_beat_len) && ((r_wptr + bi[8:0]) < 9'd511)) begin
                                    r_pay_bytes[r_wptr + bi[8:0]] <= i_s_axis_tdata[bi*8 +: 8];
                                end
                            end
                            r_wptr <= w_next_wptr;
                            if (i_s_axis_tlast && !r_use_meta) begin
                                r_lock_paylen <= w_next_wptr;
                            end
                        end
                    end
                end
                ST_ARM: begin
                    if (w_arm_pay_ok) begin
                        r_hdr_bytes[0]  <= w_da[47:40];
                        r_hdr_bytes[1]  <= w_da[39:32];
                        r_hdr_bytes[2]  <= w_da[31:24];
                        r_hdr_bytes[3]  <= w_da[23:16];
                        r_hdr_bytes[4]  <= w_da[15:8];
                        r_hdr_bytes[5]  <= w_da[7:0];
                        r_hdr_bytes[6]  <= r_lock_sa[47:40];
                        r_hdr_bytes[7]  <= r_lock_sa[39:32];
                        r_hdr_bytes[8]  <= r_lock_sa[31:24];
                        r_hdr_bytes[9]  <= r_lock_sa[23:16];
                        r_hdr_bytes[10] <= r_lock_sa[15:8];
                        r_hdr_bytes[11] <= r_lock_sa[7:0];
                        r_hdr_bytes[12] <= 8'h08;
                        r_hdr_bytes[13] <= 8'h00;
                        r_hdr_bytes[14] <= 8'h45;
                        r_hdr_bytes[15] <= 8'h00;
                        r_hdr_bytes[16] <= w_ip_tot[15:8];
                        r_hdr_bytes[17] <= w_ip_tot[7:0];
                        r_hdr_bytes[18] <= 8'h00;
                        r_hdr_bytes[19] <= 8'h00;
                        r_hdr_bytes[20] <= 8'h00;
                        r_hdr_bytes[21] <= 8'h00;
                        r_hdr_bytes[22] <= r_lock_ttl;
                        r_hdr_bytes[23] <= 8'd17;
                        r_hdr_bytes[24] <= w_ip_csum[15:8];
                        r_hdr_bytes[25] <= w_ip_csum[7:0];
                        r_hdr_bytes[26] <= r_lock_src_ip[31:24];
                        r_hdr_bytes[27] <= r_lock_src_ip[23:16];
                        r_hdr_bytes[28] <= r_lock_src_ip[15:8];
                        r_hdr_bytes[29] <= r_lock_src_ip[7:0];
                        r_hdr_bytes[30] <= r_lock_dst_ip[31:24];
                        r_hdr_bytes[31] <= r_lock_dst_ip[23:16];
                        r_hdr_bytes[32] <= r_lock_dst_ip[15:8];
                        r_hdr_bytes[33] <= r_lock_dst_ip[7:0];
                        r_hdr_bytes[34] <= r_lock_sport[15:8];
                        r_hdr_bytes[35] <= r_lock_sport[7:0];
                        r_hdr_bytes[36] <= r_lock_dport[15:8];
                        r_hdr_bytes[37] <= r_lock_dport[7:0];
                        r_hdr_bytes[38] <= w_udp_len[15:8];
                        r_hdr_bytes[39] <= w_udp_len[7:0];
                        r_hdr_bytes[40] <= 8'h00;
                        r_hdr_bytes[41] <= 8'h00;
                        r_frame_len     <= 16'd42 + {7'd0, r_lock_paylen};
                        r_emit_off      <= 16'd0;
                    end else begin
                        o_fail_sticky <= 1'b1;
                        o_drop_cnt    <= o_drop_cnt + 32'd1;
                        o_nosend_cnt  <= o_nosend_cnt + 32'd1;
                    end
                end
                ST_EMIT: begin
                    if (!o_m_axis_tvalid || i_m_axis_tready) begin
                        if (w_emit_done) begin
                            o_m_axis_tvalid <= 1'b0;
                            o_m_axis_tlast  <= 1'b0;
                            o_tx_ok_cnt     <= o_tx_ok_cnt + 32'd1;
                            r_emit_off      <= 16'd0;
                        end else begin
                            o_m_axis_tdata  <= w_out_data;
                            o_m_axis_tkeep  <= w_out_keep;
                            o_m_axis_tlast  <= w_out_last;
                            o_m_axis_tvalid <= 1'b1;
                            r_emit_off      <= r_emit_off + 16'd8;
                        end
                    end
                end
                default: begin
                end
            endcase
        end
    end

endmodule

`default_nettype wire
