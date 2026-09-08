// -----------------------------------------------------------------------------
// mcast_eng.sv — Per-client multicast TX engine (M5, N=1 sim)
//
// Input : event AXIS-512 (single-beat). s_event_tready tied 1 — never
//         backpressure the event bus; filter/rate/busy drops are counted.
// Filter: 8192-bit enable vector[symbol_id[12:0]] AND ch_mask & (1<<ch).
// Rate  : token bucket — +cfg_refill every cfg_period cycles (cfg_period==0
//         disables limiting); send costs 1 token.
// Output: Ethernet/IPv4/UDP frame on AXIS-64 (wire byte0 = tdata[7:0]).
//         Payload = entire event_t as 64 LE bytes (event[7:0] first).
//         UDP checksum = 0; IPv4 header checksum computed in RTL.
//         No VLAN, no FCS. Store-and-forward one frame.
// P1   : cfg_ttl_default (def 1), RFC1112 DA map (cfg_map_en), SA/DA/MAC
//         gating + sticky errs; IP hdr csum follows TTL.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module mcast_eng
  import md_pkg::*;
#(
  parameter int CLIENT_ID = 0
) (
  input  logic         sys_clk,
  /* verilator lint_off SYNCASYNCNET */
  input  logic         sys_rst_n,
  /* verilator lint_on SYNCASYNCNET */
  input  logic [511:0] i_s_event_tdata,
  input  logic         i_s_event_tvalid,
  input  logic         i_s_event_tlast,
  output logic         o_s_event_tready,
  output logic [63:0]  o_m_tdata,
  output logic [7:0]   o_m_tkeep,
  output logic         o_m_tvalid,
  output logic         o_m_tlast,
  input  logic         i_m_tready,
  input  logic [47:0]  i_cfg_src_mac,
  input  logic [47:0]  i_cfg_dst_mac,
  input  logic [31:0]  i_cfg_src_ip,
  input  logic [31:0]  i_cfg_dst_ip,
  input  logic [15:0]  i_cfg_udp_sport,
  input  logic [15:0]  i_cfg_udp_dport,
  input  logic [7:0]   i_cfg_ttl_default,
  input  logic         i_cfg_map_en,
  input  logic [7:0]   i_cfg_ch_mask,
  input  logic [15:0]  i_cfg_period,
  input  logic [15:0]  i_cfg_refill,
  input  logic         i_filt_we,
  input  logic [12:0]  i_filt_addr,
  input  logic         i_filt_bit,
  output logic [31:0]  o_tx_ok,
  output logic [31:0]  o_drop_filt,
  output logic [31:0]  o_drop_rate,
  output logic         o_err_addr_sticky,
  output logic         o_err_mac_mismatch,
  (* keep = "true" *) output logic o_dbg_cs_state,
  (* keep = "true" *) output logic o_dbg_err_sticky
);

  logic w_unused_cid;
  logic w_unused_tlast;
  assign w_unused_cid   = (CLIENT_ID == 0) ? 1'b0 : 1'b1;
  assign w_unused_tlast = i_s_event_tlast;

  assign o_s_event_tready = 1'b1;

  localparam int unsigned FRAME_BYTES = 106; // 14 eth + 20 ip + 8 udp + 64 pay
  localparam int unsigned N_BEATS     = 14;  // last beat: 2 bytes
  localparam logic [15:0] IP_TOTAL    = 16'd92;
  localparam logic [15:0] UDP_LEN     = 16'd72;

  function automatic logic [31:0] sat_inc(input logic [31:0] c);
    return (c == 32'hFFFF_FFFF) ? c : (c + 32'd1);
  endfunction

  function automatic logic [15:0] sat_add16(
      input logic [15:0] a,
      input logic [15:0] b
  );
    logic [16:0] s;
    s = {1'b0, a} + {1'b0, b};
    return s[16] ? 16'hFFFF : s[15:0];
  endfunction

  function automatic logic [15:0] ipv4_hdr_csum(
      input logic [31:0] src_ip,
      input logic [31:0] dst_ip,
      input logic [7:0]  ttl
  );
    logic [31:0] sum;
    sum  = 32'h4500;
    sum += {16'd0, IP_TOTAL};
    sum += 32'h0000;
    sum += 32'h0000;
    sum += {16'd0, ttl, 8'h11};
    sum += {16'd0, src_ip[31:16]};
    sum += {16'd0, src_ip[15:0]};
    sum += {16'd0, dst_ip[31:16]};
    sum += {16'd0, dst_ip[15:0]};
    sum  = (sum & 32'hFFFF) + (sum >> 16);
    sum  = (sum & 32'hFFFF) + (sum >> 16);
    return ~sum[15:0];
  endfunction

  typedef enum logic [0:0] {
    ST_IDLE = 1'b0,
    ST_TX   = 1'b1
  } state_e;

  state_e      cs_state;
  state_e      ns_state;
  logic        r_err_sticky;
  logic        r_err_addr_sticky;
  logic        r_err_mac_mismatch;
  logic [3:0]  r_beat;
  logic [63:0] r_frame [0:N_BEATS-1];
  logic [7:0]  r_keep  [0:N_BEATS-1];
  logic        r_filt  [0:CAM_DEPTH-1];
  logic [15:0] r_tokens;
  logic [15:0] r_period_cnt;
  logic [31:0] r_tx_ok;
  logic [31:0] r_drop_filt;
  logic [31:0] r_drop_rate;

  event_t      w_ev_in;
  logic        w_filt_ok;
  logic        w_rate_unlimited;
  logic        w_rate_ok;
  logic        w_busy;
  logic        w_accept;
  logic [47:0] w_mapped_mac;
  logic [47:0] w_tx_dst_mac;
  logic        w_da_is_mcast;
  logic        w_sa_ok;
  logic        w_mac_ok;
  logic        w_addr_ok;
  logic        w_hdr_ok;
  logic [7:0]  w_ttl;

  assign w_ev_in          = event_t'(i_s_event_tdata);
  assign w_filt_ok        = (w_ev_in.symbol_id < 16'(CAM_DEPTH))
                            && r_filt[w_ev_in.symbol_id[12:0]]
                            && (w_ev_in.ch < 4'd8)
                            && ((i_cfg_ch_mask & (8'b1 << w_ev_in.ch[2:0])) != 8'd0);
  assign w_rate_unlimited = (i_cfg_period == 16'd0);
  assign w_rate_ok        = w_rate_unlimited || (r_tokens != 16'd0);
  assign w_busy           = (cs_state != ST_IDLE);

  // RFC1112 map + SA/DA legality (P1). SPEC: udp-mcast-tx-design.md §4.3
  assign w_mapped_mac = {24'h01005E, 1'b0, i_cfg_dst_ip[22:0]};
  assign w_tx_dst_mac = i_cfg_map_en ? w_mapped_mac : i_cfg_dst_mac;
  assign w_da_is_mcast = (i_cfg_dst_ip[31:28] == 4'hE);
  assign w_sa_ok       = (i_cfg_src_ip[31:28] != 4'hE);
  assign w_mac_ok      = i_cfg_map_en ? 1'b1
                       : (i_cfg_dst_mac == w_mapped_mac);
  assign w_addr_ok     = w_da_is_mcast && w_sa_ok;
  assign w_hdr_ok      = w_addr_ok && w_mac_ok;
  assign w_ttl         = (i_cfg_ttl_default == 8'd0) ? 8'd1 : i_cfg_ttl_default;

  assign w_accept         = i_s_event_tvalid && w_filt_ok && w_rate_ok
                            && !w_busy && w_hdr_ok;

  assign o_tx_ok            = r_tx_ok;
  assign o_drop_filt        = r_drop_filt;
  assign o_drop_rate        = r_drop_rate;
  assign o_err_addr_sticky  = r_err_addr_sticky;
  assign o_err_mac_mismatch = r_err_mac_mismatch;
  assign o_m_tvalid         = (cs_state == ST_TX);
  assign o_m_tdata          = r_frame[r_beat];
  assign o_m_tkeep          = r_keep[r_beat];
  assign o_m_tlast          = (r_beat == 4'(N_BEATS - 1));
  assign o_dbg_cs_state     = cs_state;
  assign o_dbg_err_sticky   = r_err_sticky;

  // Register current FSM state.
  // SPEC: module-design-v1.md §3.8
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  // Select next FSM state from accept / last-beat handshake.
  // SPEC: module-design-v1.md §3.8
  always_comb begin
    ns_state = cs_state;
    case (cs_state)
      ST_IDLE: begin
        if (i_s_event_tvalid && w_filt_ok && w_rate_ok && w_hdr_ok)
          ns_state = ST_TX;
      end
      ST_TX: begin
        if (i_m_tready && (r_beat == 4'(N_BEATS - 1)))
          ns_state = ST_IDLE;
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  // Symbol enable bitmap (8192-bit filter).
  // SPEC: module-design-v1.md §3.8
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic int fi;
    if (!sys_rst_n) begin
      for (fi = 0; fi < CAM_DEPTH; fi++)
        r_filt[fi] <= 1'b0;
    end else if (i_filt_we) begin
      r_filt[i_filt_addr] <= i_filt_bit;
    end
  end

  // Token bucket: refill then optional consume on accept.
  // SPEC: module-design-v1.md §3.8
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_tokens     <= 16'd0;
      r_period_cnt <= 16'd0;
    end else begin
      automatic logic [15:0] t_next;
      automatic logic [15:0] p_next;
      t_next = r_tokens;
      p_next = r_period_cnt;
      if (w_rate_unlimited) begin
        p_next = 16'd0;
        t_next = 16'hFFFF;
      end else if (r_period_cnt >= (i_cfg_period - 16'd1)) begin
        p_next = 16'd0;
        t_next = sat_add16(t_next, i_cfg_refill);
      end else
        p_next = r_period_cnt + 16'd1;
      if (w_accept && !w_rate_unlimited && (t_next != 16'd0))
        t_next = t_next - 16'd1;
      r_tokens     <= t_next;
      r_period_cnt <= p_next;
    end
  end

  // Build 106-byte Eth/IPv4/UDP frame, walk 14 TX beats, saturating counters.
  // SPEC: module-design-v1.md §3.8; udp-mcast-tx-p1-impl.md §2
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic int i, bi, base, nb, j;
    automatic logic [7:0]  fb [0:FRAME_BYTES-1];
    automatic logic [15:0] csum;
    automatic logic [63:0] dtmp;
    automatic logic [7:0]  ktmp;
    if (!sys_rst_n) begin
      r_beat      <= 4'd0;
      r_tx_ok     <= 32'd0;
      r_drop_filt <= 32'd0;
      r_drop_rate <= 32'd0;
      for (bi = 0; bi < N_BEATS; bi++) begin
        r_frame[bi] <= 64'd0;
        r_keep[bi]  <= 8'd0;
      end
    end else begin
      if (i_s_event_tvalid && !w_filt_ok)
        r_drop_filt <= sat_inc(r_drop_filt);
      if (i_s_event_tvalid && w_filt_ok && (!w_rate_ok || w_busy))
        r_drop_rate <= sat_inc(r_drop_rate);
      if (w_accept) begin
        csum = ipv4_hdr_csum(i_cfg_src_ip, i_cfg_dst_ip, w_ttl);
        fb[0]  = w_tx_dst_mac[47:40];
        fb[1]  = w_tx_dst_mac[39:32];
        fb[2]  = w_tx_dst_mac[31:24];
        fb[3]  = w_tx_dst_mac[23:16];
        fb[4]  = w_tx_dst_mac[15:8];
        fb[5]  = w_tx_dst_mac[7:0];
        fb[6]  = i_cfg_src_mac[47:40];
        fb[7]  = i_cfg_src_mac[39:32];
        fb[8]  = i_cfg_src_mac[31:24];
        fb[9]  = i_cfg_src_mac[23:16];
        fb[10] = i_cfg_src_mac[15:8];
        fb[11] = i_cfg_src_mac[7:0];
        fb[12] = 8'h08;
        fb[13] = 8'h00;
        fb[14] = 8'h45;
        fb[15] = 8'h00;
        fb[16] = IP_TOTAL[15:8];
        fb[17] = IP_TOTAL[7:0];
        fb[18] = 8'h00;
        fb[19] = 8'h00;
        fb[20] = 8'h00;
        fb[21] = 8'h00;
        fb[22] = w_ttl;
        fb[23] = 8'h11;
        fb[24] = csum[15:8];
        fb[25] = csum[7:0];
        fb[26] = i_cfg_src_ip[31:24];
        fb[27] = i_cfg_src_ip[23:16];
        fb[28] = i_cfg_src_ip[15:8];
        fb[29] = i_cfg_src_ip[7:0];
        fb[30] = i_cfg_dst_ip[31:24];
        fb[31] = i_cfg_dst_ip[23:16];
        fb[32] = i_cfg_dst_ip[15:8];
        fb[33] = i_cfg_dst_ip[7:0];
        fb[34] = i_cfg_udp_sport[15:8];
        fb[35] = i_cfg_udp_sport[7:0];
        fb[36] = i_cfg_udp_dport[15:8];
        fb[37] = i_cfg_udp_dport[7:0];
        fb[38] = UDP_LEN[15:8];
        fb[39] = UDP_LEN[7:0];
        fb[40] = 8'h00;
        fb[41] = 8'h00;
        for (i = 0; i < 64; i++)
          fb[42 + i] = i_s_event_tdata[8 * i +: 8];
        for (bi = 0; bi < N_BEATS; bi++) begin
          base = bi * 8;
          nb   = ((base + 8) <= FRAME_BYTES) ? 8 : (FRAME_BYTES - base);
          dtmp = 64'd0;
          ktmp = 8'd0;
          for (j = 0; j < 8; j++) begin
            if (j < nb) begin
              dtmp[8 * j +: 8] = fb[base + j];
              ktmp[j]          = 1'b1;
            end
          end
          r_frame[bi] <= dtmp;
          r_keep[bi]  <= ktmp;
        end
        r_beat  <= 4'd0;
        r_tx_ok <= sat_inc(r_tx_ok);
      end else if (cs_state == ST_TX) begin
        if (i_m_tready) begin
          if (r_beat == 4'(N_BEATS - 1))
            r_beat <= 4'd0;
          else
            r_beat <= r_beat + 4'd1;
        end
      end
    end
  end

  // Sticky illegal-state flag + P1 addr/mac stickies.
  // SPEC: module-design-v1.md §3.8; udp-mcast-tx-p1-impl.md §2.1
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_err_sticky        <= 1'b0;
      r_err_addr_sticky   <= 1'b0;
      r_err_mac_mismatch  <= 1'b0;
    end else begin
      if ((cs_state != ST_IDLE) && (cs_state != ST_TX))
        r_err_sticky <= 1'b1;
      // Latch sticky on filt-pass event that fails header legality
      if (i_s_event_tvalid && w_filt_ok && !w_addr_ok)
        r_err_addr_sticky <= 1'b1;
      if (i_s_event_tvalid && w_filt_ok && !w_mac_ok)
        r_err_mac_mismatch <= 1'b1;
    end
  end

endmodule

`default_nettype wire
