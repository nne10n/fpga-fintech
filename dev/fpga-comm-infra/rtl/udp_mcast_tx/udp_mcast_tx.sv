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

    localparam integer P_HDR     = 42;   // Eth(14) + IP(20) + UDP(8)
    localparam integer P_MAX_PAY = 511;

    // Header byte offsets (big-endian; lane 0 = first on-wire byte).
    localparam integer H_DA0     = 0;
    localparam integer H_SA0     = 6;
    localparam integer H_ETYPE0  = 12;  // 0x0800
    localparam integer H_IPVER   = 14;  // 0x45
    localparam integer H_IPTOT0  = 16;  // IP total length
    localparam integer H_IPID0   = 18;  // 0x0000
    localparam integer H_IPFLG0  = 20;  // flags/frag = 0
    localparam integer H_IPTTL   = 22;
    localparam integer H_IPPROTO = 23;  // 17 = UDP
    localparam integer H_IPCS0   = 24;  // IPv4 header checksum
    localparam integer H_SIP0    = 26;
    localparam integer H_DIP0    = 30;
    localparam integer H_SPORT0  = 34;
    localparam integer H_DPORT0  = 36;
    localparam integer H_UDPLEN0 = 38;
    localparam integer H_UDPCSUM = 40;  // UDP checksum = 0

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

    // Combinational header byte generator (idx ∈ [0,41]). Inputs are the
    // locked SOP fields, stable across EMIT, so this reproduces the exact
    // bytes the old r_hdr_bytes array staged during ARM.
    function automatic [7:0] f_hdr_byte;
        input [5:0]  idx;
        input [47:0] da;
        input [47:0] sa;
        input [15:0] ip_tot;
        input [7:0]  ttl;
        input [15:0] ip_csum;
        input [31:0] sip;
        input [31:0] dip;
        input [15:0] sport;
        input [15:0] dport;
        input [15:0] udp_len;
        begin
            case (idx)
                H_DA0+0:     f_hdr_byte = da[47:40];
                H_DA0+1:     f_hdr_byte = da[39:32];
                H_DA0+2:     f_hdr_byte = da[31:24];
                H_DA0+3:     f_hdr_byte = da[23:16];
                H_DA0+4:     f_hdr_byte = da[15:8];
                H_DA0+5:     f_hdr_byte = da[7:0];
                H_SA0+0:     f_hdr_byte = sa[47:40];
                H_SA0+1:     f_hdr_byte = sa[39:32];
                H_SA0+2:     f_hdr_byte = sa[31:24];
                H_SA0+3:     f_hdr_byte = sa[23:16];
                H_SA0+4:     f_hdr_byte = sa[15:8];
                H_SA0+5:     f_hdr_byte = sa[7:0];
                H_ETYPE0:    f_hdr_byte = 8'h08;
                H_ETYPE0+1:  f_hdr_byte = 8'h00;
                H_IPVER:     f_hdr_byte = 8'h45;
                H_IPVER+1:   f_hdr_byte = 8'h00;
                H_IPTOT0:    f_hdr_byte = ip_tot[15:8];
                H_IPTOT0+1:  f_hdr_byte = ip_tot[7:0];
                H_IPID0:     f_hdr_byte = 8'h00;
                H_IPID0+1:   f_hdr_byte = 8'h00;
                H_IPFLG0:    f_hdr_byte = 8'h00;
                H_IPFLG0+1:  f_hdr_byte = 8'h00;
                H_IPTTL:     f_hdr_byte = ttl;
                H_IPPROTO:   f_hdr_byte = 8'd17;
                H_IPCS0:     f_hdr_byte = ip_csum[15:8];
                H_IPCS0+1:   f_hdr_byte = ip_csum[7:0];
                H_SIP0+0:    f_hdr_byte = sip[31:24];
                H_SIP0+1:    f_hdr_byte = sip[23:16];
                H_SIP0+2:    f_hdr_byte = sip[15:8];
                H_SIP0+3:    f_hdr_byte = sip[7:0];
                H_DIP0+0:    f_hdr_byte = dip[31:24];
                H_DIP0+1:    f_hdr_byte = dip[23:16];
                H_DIP0+2:    f_hdr_byte = dip[15:8];
                H_DIP0+3:    f_hdr_byte = dip[7:0];
                H_SPORT0:    f_hdr_byte = sport[15:8];
                H_SPORT0+1:  f_hdr_byte = sport[7:0];
                H_DPORT0:    f_hdr_byte = dport[15:8];
                H_DPORT0+1:  f_hdr_byte = dport[7:0];
                H_UDPLEN0:   f_hdr_byte = udp_len[15:8];
                H_UDPLEN0+1: f_hdr_byte = udp_len[7:0];
                H_UDPCSUM:   f_hdr_byte = 8'h00;
                H_UDPCSUM+1: f_hdr_byte = 8'h00;
                default:     f_hdr_byte = 8'h00;
            endcase
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
    integer bi;
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
                    w_byte_sel = f_hdr_byte(w_idx[5:0],
                                            w_da, r_lock_sa, w_ip_tot,
                                            r_lock_ttl, w_ip_csum,
                                            r_lock_src_ip, r_lock_dst_ip,
                                            r_lock_sport, r_lock_dport, w_udp_len);
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
                        // Header bytes are derived combinationally during
                        // EMIT (f_hdr_byte) from the locked SOP fields, so ARM
                        // only needs to arm the frame length / emit pointer.
                        r_frame_len <= 16'd42 + {7'd0, r_lock_paylen};
                        r_emit_off  <= 16'd0;
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
