`timescale 1ns/1ps
`default_nettype none

// S1 TCP payload strip — G1 FROZEN (design/comm-infra-step1-design.md)
// Independent core. L2–L4 network frame in, TCP payload out, 64-bit AXIS.
// Role A: o_s_axis_tready ≡ 1. Illegal frames drop + count.
// Not a udp_strip / tcp_pay_stub.
//
// Refactor notes (behavior-preserving):
//   * L2/L3/L4 byte offsets and well-known ethertypes/protocol values moved to
//     named localparams (L2_BASE, L2_VLAN, HDR_MIN, ET_VLAN, ET_IPV4,
//     IP_PROTO_TCP, P_MAX) instead of inline magic numbers. Parse logic is
//     unchanged; only the constants are named.
module tcp_pay_strip (
    input  wire             sys_clk,
    input  wire             sys_rst_n,

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
    output logic [31:0]     o_ok_cnt,
    (* keep *) output logic [1:0] o_dbg_cs_state
);

    localparam integer P_MAX     = 2048;

    // L2/L3/L4 byte offsets used by the parse block.
    localparam [12:0] L2_BASE      = 13'd14;  // DA(6)+SA(6)+etype(2)
    localparam [12:0] L2_VLAN      = 13'd18;  // +VLAN tag (4)
    localparam [12:0] HDR_MIN      = 13'd54;  // 14 + 20 (IP) + 20 (TCP) minimum parseable
    localparam [12:0] IP_HDR_MIN   = 13'd20;  // IHL>=5 → 20 bytes
    localparam [12:0] TCP_HDR_MIN  = 13'd20;  // doff>=5 → 20 bytes
    localparam [15:0] ET_VLAN      = 16'h8100;
    localparam [15:0] ET_IPV4      = 16'h0800;
    localparam [3:0]  IP_VER4      = 4'd4;
    localparam [7:0]  IP_PROTO_TCP = 8'd6;

    localparam [1:0]   ST_IDLE   = 2'd0;
    localparam [1:0]   ST_TAKE   = 2'd1;
    localparam [1:0]   ST_PARSE  = 2'd2;
    localparam [1:0]   ST_EMIT   = 2'd3;

    assign o_s_axis_tready = 1'b1;

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

    wire [3:0] w_beat_len = f_keep_len(i_s_axis_tkeep);
    wire       w_fire     = i_s_axis_tvalid;

    logic [1:0]  cs_state;
    logic [1:0]  ns_state;
    assign o_dbg_cs_state = cs_state;
    logic        r_in_pkt;
    logic        r_busy_drop;
    logic        r_bad;

    logic [7:0]  r_frm [0:P_MAX-1];
    logic [12:0] r_wptr;
    logic [12:0] r_pay_off;
    logic [12:0] r_pay_end;
    logic [12:0] r_emit_off;

    wire         w_sop       = w_fire && !r_in_pkt;
    wire [12:0]  w_next_wptr = r_wptr + {9'd0, w_beat_len};
    wire         w_emit_hs   = o_m_axis_tvalid && i_m_axis_tready;
    wire         w_emit_done = w_emit_hs && o_m_axis_tlast;
    wire [12:0]  w_pay_len   = (r_pay_end > r_pay_off) ? (r_pay_end - r_pay_off) : 13'd0;

    // Combinational parse of stored frame (valid in ST_PARSE)
    logic        w_parse_ok;
    logic        w_parse_empty;
    logic [12:0] w_parse_off;
    logic [12:0] w_parse_end;

    logic [15:0] w_et0;
    logic [15:0] w_et;
    logic [12:0] w_l2;
    logic [12:0] w_ip;
    logic [3:0]  w_ihl;
    logic [12:0] w_iplen;
    logic [15:0] w_iptot;
    logic [15:0] w_frag;
    logic [12:0] w_tcp;
    logic [3:0]  w_doff;
    logic [12:0] w_tcplen;
    logic [12:0] w_hdr_end;
    logic [12:0] w_ip_end;

    logic [7:0]  w_b_ip0;
    logic [7:0]  w_b_ip2;
    logic [7:0]  w_b_ip3;
    logic [7:0]  w_b_ip6;
    logic [7:0]  w_b_ip7;
    logic [7:0]  w_b_ip9;
    logic [7:0]  w_b_tcp12;

    always_comb begin
        w_parse_ok    = 1'b0;
        w_parse_empty = 1'b0;
        w_parse_off   = 13'd0;
        w_parse_end   = 13'd0;
        w_et0         = 16'd0;
        w_et          = 16'd0;
        w_l2          = L2_BASE;
        w_ip          = L2_BASE;
        w_ihl         = 4'd0;
        w_iplen       = 13'd0;
        w_iptot       = 16'd0;
        w_frag        = 16'd0;
        w_tcp         = 13'd0;
        w_doff        = 4'd0;
        w_tcplen      = 13'd0;
        w_hdr_end     = 13'd0;
        w_ip_end      = 13'd0;
        w_b_ip0       = 8'd0;
        w_b_ip2       = 8'd0;
        w_b_ip3       = 8'd0;
        w_b_ip6       = 8'd0;
        w_b_ip7       = 8'd0;
        w_b_ip9       = 8'd0;
        w_b_tcp12     = 8'd0;

        if ((cs_state == ST_PARSE) && (r_wptr >= HDR_MIN)) begin
            w_et0 = {r_frm[12], r_frm[13]};
            if (w_et0 == ET_VLAN) begin
                w_l2 = L2_VLAN;
                w_et = {r_frm[16], r_frm[17]};
            end else begin
                w_l2 = L2_BASE;
                w_et = w_et0;
            end
            w_ip = w_l2;
            if ((w_et == ET_IPV4) && (r_wptr >= (w_ip + IP_HDR_MIN))) begin
                w_b_ip0 = r_frm[w_ip];
                if (w_b_ip0[7:4] == IP_VER4) begin
                    w_ihl   = w_b_ip0[3:0];
                    w_iplen = {9'd0, w_ihl, 2'b00};
                    w_b_ip2 = r_frm[w_ip + 13'd2];
                    w_b_ip3 = r_frm[w_ip + 13'd3];
                    w_b_ip6 = r_frm[w_ip + 13'd6];
                    w_b_ip7 = r_frm[w_ip + 13'd7];
                    w_b_ip9 = r_frm[w_ip + 13'd9];
                    w_iptot = {w_b_ip2, w_b_ip3};
                    w_frag  = {w_b_ip6, w_b_ip7};
                    w_tcp   = w_ip + w_iplen;
                    if ((w_ihl >= 4'd5) &&
                        (w_b_ip9 == IP_PROTO_TCP) &&
                        (w_frag[12:0] == 13'd0) &&
                        (w_frag[13] == 1'b0) &&
                        (w_iptot >= {3'd0, w_iplen} + TCP_HDR_MIN) &&
                        (r_wptr >= (w_tcp + TCP_HDR_MIN))) begin
                        w_b_tcp12 = r_frm[w_tcp + 13'd12];
                        w_doff    = w_b_tcp12[7:4];
                        w_tcplen  = {9'd0, w_doff, 2'b00};
                        w_hdr_end = w_tcp + w_tcplen;
                        w_ip_end  = w_ip + w_iptot[12:0];
                        if ((w_doff >= 4'd5) &&
                            (w_iptot >= ({3'd0, w_iplen} + {3'd0, w_tcplen})) &&
                            (w_ip_end <= r_wptr) &&
                            (w_hdr_end <= w_ip_end)) begin
                            w_parse_off = w_hdr_end;
                            w_parse_end = w_ip_end;
                            if (w_hdr_end == w_ip_end) begin
                                w_parse_empty = 1'b1;
                                w_parse_ok    = 1'b1;
                            end else begin
                                w_parse_ok = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end

    // process 2: next-state — writes only ns_state
    always_comb begin
        ns_state = cs_state;
        case (cs_state)
            ST_IDLE: begin
                if (w_sop) begin
                    ns_state = i_s_axis_tlast ? ST_PARSE : ST_TAKE;
                end
            end
            ST_TAKE: begin
                if (w_fire && i_s_axis_tlast) begin
                    ns_state = (r_bad || (w_next_wptr > P_MAX)) ? ST_IDLE : ST_PARSE;
                end
            end
            ST_PARSE: begin
                if (w_parse_ok && !w_parse_empty) begin
                    ns_state = ST_EMIT;
                end else begin
                    ns_state = ST_IDLE;
                end
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
    logic [12:0] w_idx;
    logic [7:0]  w_out_keep;
    logic        w_out_last;
    logic [63:0] w_out_data;
    logic [12:0] w_src;

    always_comb begin
        w_out_keep = 8'h00;
        w_out_last = 1'b0;
        w_out_data = 64'd0;
        w_idx      = 13'd0;
        w_src      = 13'd0;
        for (i_b = 0; i_b < 8; i_b = i_b + 1) begin
            w_idx = r_emit_off + i_b[12:0];
            if ((cs_state == ST_EMIT) && (w_idx < w_pay_len)) begin
                w_out_keep = w_out_keep | (8'd1 << i_b);
                w_src = r_pay_off + w_idx;
                if (w_src < P_MAX) begin
                    w_out_data = w_out_data | ({56'd0, r_frm[w_src]} << (i_b * 8));
                end
            end
        end
        w_out_last = (cs_state == ST_EMIT) && ((r_emit_off + 13'd8) >= w_pay_len);
    end

    integer bi;

    // process 3: datapath / outputs
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            r_in_pkt        <= 1'b0;
            r_busy_drop     <= 1'b0;
            r_bad           <= 1'b0;
            r_wptr          <= 13'd0;
            r_pay_off       <= 13'd0;
            r_pay_end       <= 13'd0;
            r_emit_off      <= 13'd0;
            o_m_axis_tdata  <= 64'd0;
            o_m_axis_tkeep  <= 8'd0;
            o_m_axis_tvalid <= 1'b0;
            o_m_axis_tlast  <= 1'b0;
            o_fail_sticky   <= 1'b0;
            o_drop_cnt      <= 32'd0;
            o_ok_cnt        <= 32'd0;
        end else begin
            if (w_fire) begin
                r_in_pkt <= !i_s_axis_tlast;
            end
            if (r_busy_drop && w_fire && i_s_axis_tlast) begin
                r_busy_drop <= 1'b0;
            end
            if ((cs_state != ST_IDLE) && w_sop) begin
                o_fail_sticky <= 1'b1;
                o_drop_cnt    <= o_drop_cnt + 32'd1;
                r_busy_drop   <= !i_s_axis_tlast;
            end

            case (cs_state)
                ST_IDLE: begin
                    o_m_axis_tvalid <= 1'b0;
                    o_m_axis_tlast  <= 1'b0;
                    r_emit_off      <= 13'd0;
                    if (w_sop) begin
                        r_bad  <= 1'b0;
                        r_wptr <= {9'd0, w_beat_len};
                        for (bi = 0; bi < 8; bi = bi + 1) begin
                            if (bi[3:0] < w_beat_len) begin
                                r_frm[bi[12:0]] <= i_s_axis_tdata[bi*8 +: 8];
                            end
                        end
                    end
                end
                ST_TAKE: begin
                    if (w_fire && !r_busy_drop) begin
                        if (w_next_wptr > P_MAX) begin
                            o_fail_sticky <= 1'b1;
                            o_drop_cnt    <= o_drop_cnt + 32'd1;
                            r_bad         <= 1'b1;
                            r_wptr        <= 13'd0;
                        end else begin
                            for (bi = 0; bi < 8; bi = bi + 1) begin
                                if ((bi[3:0] < w_beat_len) && ((r_wptr + bi[12:0]) < P_MAX)) begin
                                    r_frm[r_wptr + bi[12:0]] <= i_s_axis_tdata[bi*8 +: 8];
                                end
                            end
                            r_wptr <= w_next_wptr;
                        end
                    end
                end
                ST_PARSE: begin
                    if (w_parse_ok && !w_parse_empty) begin
                        r_pay_off  <= w_parse_off;
                        r_pay_end  <= w_parse_end;
                        r_emit_off <= 13'd0;
                    end else if (!w_parse_ok) begin
                        o_fail_sticky <= 1'b1;
                        o_drop_cnt    <= o_drop_cnt + 32'd1;
                    end
                end
                ST_EMIT: begin
                    if (!o_m_axis_tvalid || i_m_axis_tready) begin
                        if (w_emit_done) begin
                            o_m_axis_tvalid <= 1'b0;
                            o_m_axis_tlast  <= 1'b0;
                            o_ok_cnt        <= o_ok_cnt + 32'd1;
                            r_emit_off      <= 13'd0;
                        end else begin
                            o_m_axis_tdata  <= w_out_data;
                            o_m_axis_tkeep  <= w_out_keep;
                            o_m_axis_tlast  <= w_out_last;
                            o_m_axis_tvalid <= 1'b1;
                            r_emit_off      <= r_emit_off + 13'd8;
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
