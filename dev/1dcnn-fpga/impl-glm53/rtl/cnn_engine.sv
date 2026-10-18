`timescale 1ns / 1ps
`default_nettype none
// cnn_engine.sv — synthesizable 1D-CNN DUT (impl-glm53)
// Explicit FSM (cs_state/ns_state) + PE_M x PE_K_UNROLL MAC datapath.
// Quant order: MAC → scale/shift → sat INT16 → ReLU
// Behavioral whole-net task model archived at _behavioral/cnn_engine.sv
module cnn_engine
  import cnn_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              eng_en,
  input  logic              weight_ok,
  output logic              busy,
  output logic              done,
  output logic [31:0]       cyc_cnt,
  output logic [7:0]        err_code,
  input  logic [15:0]       s_axis_tdata,
  input  logic              s_axis_tvalid,
  output logic              s_axis_tready,
  input  logic              s_axis_tlast,
  output logic [15:0]       m_axis_tdata,
  output logic              m_axis_tvalid,
  input  logic              m_axis_tready,
  output logic              m_axis_tlast,
  input  logic              wgt_we,
  input  logic [13:0]       wgt_waddr,
  input  logic [15:0]       wgt_wdata,
  input  logic              wgt_re,
  input  logic [13:0]       wgt_raddr,
  output logic [15:0]       wgt_rdata
);

  // sv_coding_rules: internal sys_clk / sys_rst_n (async active-low)
  logic sys_clk;
  logic sys_rst_n;
  assign sys_clk   = clk;
  assign sys_rst_n = rst_n;

  localparam int PE_M        = 16;
  localparam int PE_K_UNROLL = 8;

  // ---- memories (inferred RAM style) ----
  act_t   act_mem [0:WIN_LEN-1];
  wgt_t   wgt_mem [0:WGT_WORDS-1];
  act_t   buf_a   [0:FEAT_MAX-1];
  act_t   buf_b   [0:FEAT_MAX-1];
  score_t scores  [0:N_CLASS-1];

  // ---- FSM (three-process) ----
  typedef enum logic [3:0] {
    ST_IDLE     = 4'd0,
    ST_RECV     = 4'd1,
    ST_LCFG     = 4'd2,
    ST_BIAS     = 4'd3,
    ST_MAC      = 4'd4,
    ST_QUANT    = 4'd5,
    ST_POOL     = 4'd6,
    ST_GAP_ACC  = 4'd7,
    ST_GAP_Q    = 4'd8,
    ST_FC_BIAS  = 4'd9,
    ST_FC_MAC   = 4'd10,
    ST_FC_QUANT = 4'd11,
    ST_EMIT     = 4'd12,
    ST_ERROR    = 4'd13
  } state_e;

  state_e cs_state;
  state_e ns_state;

  // layer / schedule registers
  logic [2:0]  r_phase;       // 0:C1 1:C2 2:POOL 3:C3 4:GAP 5:FC
  logic [1:0]  r_in_sel;      // 0 act_mem, 1 buf_a, 2 buf_b
  logic [1:0]  r_out_sel;     // 1 buf_a, 2 buf_b
  logic        r_do_relu;
  logic [11:0] r_rin, r_rout;
  logic [7:0]  r_cin, r_cout;
  logic [5:0]  r_k, r_stride;
  logic [5:0]  r_pad_l;
  logic [13:0] r_w_off, r_b_off, r_sm_off, r_ss_off;

  logic [11:0] r_ot;
  logic [7:0]  r_ocg;         // output-channel group index
  logic [7:0]  r_ic;
  logic [5:0]  r_kkg;         // kernel group index
  logic [7:0]  r_ocg_last;
  logic [5:0]  r_kkg_last;

  acc_t        r_acc   [0:PE_M-1];
  acc_t        r_gap   [0:PE_M-1];
  logic [7:0]  r_gap_cg;
  logic [11:0] r_gap_t;
  logic [7:0]  r_fc_ic;
  logic [3:0]  r_fc_ocg;      // ceil(10/16)=1 → only group 0

  logic [10:0] r_recv_cnt;
  logic [3:0]  r_emit_idx;
  logic [31:0] r_cyc;
  logic        r_done;
  logic        r_busy;
  logic [7:0]  r_err;
  logic        r_s_ready;
  logic        r_m_valid;
  logic [15:0] r_m_data;
  logic        r_m_last;

  assign busy          = r_busy;
  assign done          = r_done;
  assign cyc_cnt       = r_cyc;
  assign err_code      = r_err;
  assign s_axis_tready = r_s_ready;
  assign m_axis_tdata  = r_m_data;
  assign m_axis_tvalid = r_m_valid;
  assign m_axis_tlast  = r_m_last;

  // weight port
  always_ff @(posedge sys_clk) begin
    if (wgt_we && (int'(wgt_waddr) < WGT_WORDS))
      wgt_mem[wgt_waddr] <= wgt_t'(wgt_wdata);
    if (wgt_re)
      wgt_rdata <= 16'(unsigned'(wgt_mem[wgt_raddr]));
  end

  // ---- PE combinational MAC tree (PE_M x PE_K_UNROLL) ----
  acc_t pe_sum [0:PE_M-1];
  logic [11:0] w_t0;

  assign w_t0 = r_ot * 12'(r_stride);

  always_comb begin
    for (int m = 0; m < PE_M; m++) begin
      pe_sum[m] = '0;
      for (int ku = 0; ku < PE_K_UNROLL; ku++) begin
        // Fully assigned every iter to avoid latch inference
        int oc;
        int kk;
        int idx;
        act_t a;
        wgt_t ww;
        acc_t prod;
        oc  = int'(r_ocg) * PE_M + m;
        kk  = int'(r_kkg) * PE_K_UNROLL + ku;
        idx = 0;
        a   = 16'sd0;
        ww  = 16'sd0;
        prod = '0;
        if ((oc < int'(r_cout)) && (kk < int'(r_k))) begin
          idx = int'(w_t0) + kk - int'(r_pad_l);
          if (idx < 0 || idx >= int'(r_rin))
            a = 16'sd0;
          else if (r_in_sel == 2'd0)
            a = act_mem[idx];
          else if (r_in_sel == 2'd1)
            a = buf_a[idx * int'(r_cin) + int'(r_ic)];
          else
            a = buf_b[idx * int'(r_cin) + int'(r_ic)];
          ww   = wgt_mem[int'(r_w_off) + ((oc * int'(r_cin)) + int'(r_ic)) * int'(r_k) + kk];
          prod = acc_t'(a) * acc_t'(ww);
          pe_sum[m] = pe_sum[m] + prod;
        end
      end
    end
  end

  // helpers for next-phase / tile done
  logic w_mac_tile_done;
  logic w_conv_all_done;
  logic w_pool_done;
  logic w_gap_acc_done;
  logic w_fc_mac_done;

  assign w_mac_tile_done = (r_kkg == r_kkg_last) && (r_ic == r_cin - 8'd1);
  assign w_conv_all_done = (r_ot == r_rout - 12'd1) && (r_ocg == r_ocg_last);
  assign w_pool_done     = (r_ot == r_rout - 12'd1) && (r_ocg == r_ocg_last);
  assign w_gap_acc_done  = (r_gap_t == r_rin - 12'd1);
  assign w_fc_mac_done   = (r_fc_ic == 8'd63); // cin=64, 1 IC / cycle (PE_K not needed)

  // ========== Process 1: state register ==========
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  // ========== Process 2: next-state only ==========
  always_comb begin
    ns_state = cs_state;
    unique case (cs_state)
      ST_IDLE: begin
        if (eng_en && s_axis_tvalid && r_s_ready) begin
          if (!weight_ok)
            ns_state = ST_ERROR;
          else if (s_axis_tlast)
            ns_state = ST_LCFG;
          else
            ns_state = ST_RECV;
        end else if (eng_en && !weight_ok && s_axis_tvalid) begin
          ns_state = ST_ERROR;
        end
      end
      ST_RECV: begin
        if (s_axis_tvalid && r_s_ready &&
            (s_axis_tlast || (r_recv_cnt == 11'(WIN_LEN - 1))))
          ns_state = ST_LCFG;
      end
      ST_LCFG: begin
        unique case (r_phase)
          3'd0, 3'd1, 3'd3: ns_state = ST_BIAS;   // conv
          3'd2:             ns_state = ST_POOL;
          3'd4:             ns_state = ST_GAP_ACC;
          3'd5:             ns_state = ST_FC_BIAS;
          default:          ns_state = ST_ERROR;
        endcase
      end
      ST_BIAS:    ns_state = ST_MAC;
      ST_MAC:     ns_state = w_mac_tile_done ? ST_QUANT : ST_MAC;
      ST_QUANT: begin
        if (w_conv_all_done) begin
          // next phase: C1→C2, C2→POOL, C3→GAP
          ns_state = ST_LCFG;
        end else begin
          ns_state = ST_BIAS;
        end
      end
      ST_POOL: begin
        if (w_pool_done)
          ns_state = ST_LCFG; // → C3
        else
          ns_state = ST_POOL;
      end
      ST_GAP_ACC: ns_state = w_gap_acc_done ? ST_GAP_Q : ST_GAP_ACC;
      ST_GAP_Q: begin
        if (r_gap_cg == r_ocg_last)
          ns_state = ST_LCFG; // → FC
        else
          ns_state = ST_GAP_ACC;
      end
      ST_FC_BIAS:  ns_state = ST_FC_MAC;
      ST_FC_MAC:   ns_state = w_fc_mac_done ? ST_FC_QUANT : ST_FC_MAC;
      ST_FC_QUANT: ns_state = ST_EMIT;
      ST_EMIT: begin
        if (r_m_valid && m_axis_tready && (r_emit_idx == 4'(N_CLASS - 1)))
          ns_state = ST_IDLE;
      end
      ST_ERROR: begin
        if (!eng_en)
          ns_state = ST_IDLE;
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  // ========== Process 3: datapath / counters / handshakes ==========
  integer mi;

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_phase      <= '0;
      r_in_sel     <= '0;
      r_out_sel    <= '0;
      r_do_relu    <= 1'b0;
      r_rin        <= '0;
      r_rout       <= '0;
      r_cin        <= '0;
      r_cout       <= '0;
      r_k          <= '0;
      r_stride     <= '0;
      r_pad_l      <= '0;
      r_w_off      <= '0;
      r_b_off      <= '0;
      r_sm_off     <= '0;
      r_ss_off     <= '0;
      r_ot         <= '0;
      r_ocg        <= '0;
      r_ic         <= '0;
      r_kkg        <= '0;
      r_ocg_last   <= '0;
      r_kkg_last   <= '0;
      r_gap_cg     <= '0;
      r_gap_t      <= '0;
      r_fc_ic      <= '0;
      r_fc_ocg     <= '0;
      r_recv_cnt   <= '0;
      r_emit_idx   <= '0;
      r_cyc        <= '0;
      r_done       <= 1'b0;
      r_busy       <= 1'b0;
      r_err        <= 8'h00;
      r_s_ready    <= 1'b0;
      r_m_valid    <= 1'b0;
      r_m_data     <= '0;
      r_m_last     <= 1'b0;
      for (mi = 0; mi < PE_M; mi++) begin
        r_acc[mi] <= '0;
        r_gap[mi] <= '0;
      end
    end else begin
      r_done <= 1'b0;

      // cycle counter while busy
      if (r_busy)
        r_cyc <= r_cyc + 1'b1;

      unique case (cs_state)
        ST_IDLE: begin
          r_m_valid  <= 1'b0;
          r_m_last   <= 1'b0;
          r_busy     <= 1'b0;
          r_s_ready  <= eng_en && weight_ok;
          r_phase    <= 3'd0;
          if (eng_en && s_axis_tvalid && r_s_ready) begin
            if (!weight_ok) begin
              r_err     <= 8'h10;
              r_s_ready <= 1'b0;
            end else begin
              act_mem[0]  <= act_t'(s_axis_tdata);
              r_recv_cnt  <= 11'd1;
              r_busy      <= 1'b1;
              r_cyc       <= 32'd1;
              r_err       <= 8'h00;
              if (s_axis_tlast)
                r_s_ready <= 1'b0;
            end
          end else if (eng_en && !weight_ok && s_axis_tvalid) begin
            r_err     <= 8'h10;
            r_s_ready <= 1'b0;
          end
        end

        ST_RECV: begin
          r_s_ready <= 1'b1;
          if (s_axis_tvalid && r_s_ready) begin
            act_mem[r_recv_cnt] <= act_t'(s_axis_tdata);
            if (s_axis_tlast || (r_recv_cnt == 11'(WIN_LEN - 1))) begin
              r_s_ready <= 1'b0;
              r_phase   <= 3'd0; // start at Conv1
            end else begin
              r_recv_cnt <= r_recv_cnt + 1'b1;
            end
          end
        end

        ST_LCFG: begin
          r_ot   <= '0;
          r_ocg  <= '0;
          r_ic   <= '0;
          r_kkg  <= '0;
          unique case (r_phase)
            3'd0: begin // Conv1
              r_in_sel   <= 2'd0;
              r_out_sel  <= 2'd1;
              r_do_relu  <= 1'b1;
              r_rin      <= 12'd2048;
              r_cin      <= 8'd1;
              r_rout     <= 12'd512;
              r_cout     <= 8'd16;
              r_k        <= 6'd16;
              r_stride   <= 6'd4;
              r_pad_l    <= 6'd6;
              r_w_off    <= 14'(O_C1W);
              r_b_off    <= 14'(O_C1B);
              r_sm_off   <= 14'(O_C1SM);
              r_ss_off   <= 14'(O_C1SS);
              r_ocg_last <= 8'd0;                 // ceil(16/16)-1
              r_kkg_last <= 6'd1;                 // ceil(16/8)-1
            end
            3'd1: begin // Conv2
              r_in_sel   <= 2'd1;
              r_out_sel  <= 2'd2;
              r_do_relu  <= 1'b1;
              r_rin      <= 12'd512;
              r_cin      <= 8'd16;
              r_rout     <= 12'd127;
              r_cout     <= 8'd32;
              r_k        <= 6'd8;
              r_stride   <= 6'd4;
              r_pad_l    <= 6'd0;
              r_w_off    <= 14'(O_C2W);
              r_b_off    <= 14'(O_C2B);
              r_sm_off   <= 14'(O_C2SM);
              r_ss_off   <= 14'(O_C2SS);
              r_ocg_last <= 8'd1;                 // ceil(32/16)-1
              r_kkg_last <= 6'd0;                 // ceil(8/8)-1
            end
            3'd2: begin // MaxPool
              r_in_sel   <= 2'd2; // from buf_b
              r_out_sel  <= 2'd1; // to buf_a
              r_rin      <= 12'd127;
              r_cin      <= 8'd32;
              r_rout     <= 12'd63;
              r_cout     <= 8'd32;
              r_k        <= 6'd2;
              r_stride   <= 6'd2;
              r_pad_l    <= 6'd0;
              r_ocg_last <= 8'd1; // ceil(32/16)-1
            end
            3'd3: begin // Conv3
              r_in_sel   <= 2'd1;
              r_out_sel  <= 2'd2;
              r_do_relu  <= 1'b1;
              r_rin      <= 12'd63;
              r_cin      <= 8'd32;
              r_rout     <= 12'd61;
              r_cout     <= 8'd64;
              r_k        <= 6'd3;
              r_stride   <= 6'd1;
              r_pad_l    <= 6'd0;
              r_w_off    <= 14'(O_C3W);
              r_b_off    <= 14'(O_C3B);
              r_sm_off   <= 14'(O_C3SM);
              r_ss_off   <= 14'(O_C3SS);
              r_ocg_last <= 8'd3; // ceil(64/16)-1
              r_kkg_last <= 6'd0; // ceil(3/8)-1
            end
            3'd4: begin // GAP
              r_in_sel   <= 2'd2;
              r_out_sel  <= 2'd1;
              r_rin      <= 12'd61;
              r_cin      <= 8'd64;
              r_rout     <= 12'd1;
              r_cout     <= 8'd64;
              r_ocg_last <= 8'd3; // ceil(64/16)-1
              r_gap_cg   <= '0;
              r_gap_t    <= '0;
              for (mi = 0; mi < PE_M; mi++)
                r_gap[mi] <= '0;
            end
            3'd5: begin // FC
              r_do_relu  <= 1'b0;
              r_cin      <= 8'd64;
              r_cout     <= 8'd10;
              r_fc_ic    <= '0;
              r_fc_ocg   <= '0;
            end
            default: ;
          endcase
        end

        ST_BIAS: begin
          r_ic  <= '0;
          r_kkg <= '0;
          for (mi = 0; mi < PE_M; mi++) begin
            if ((int'(r_ocg) * PE_M + mi) < int'(r_cout))
              r_acc[mi] <= acc_t'(wgt_mem[int'(r_b_off) + int'(r_ocg) * PE_M + mi]);
            else
              r_acc[mi] <= '0;
          end
        end

        ST_MAC: begin
          for (mi = 0; mi < PE_M; mi++)
            r_acc[mi] <= r_acc[mi] + pe_sum[mi];
          // advance (ic, kkg)
          if (r_kkg == r_kkg_last) begin
            r_kkg <= '0;
            if (r_ic != r_cin - 8'd1)
              r_ic <= r_ic + 1'b1;
          end else begin
            r_kkg <= r_kkg + 1'b1;
          end
        end

        ST_QUANT: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if ((int'(r_ocg) * PE_M + mi) < int'(r_cout)) begin
              if (r_out_sel == 2'd1)
                buf_a[int'(r_ot) * int'(r_cout) + int'(r_ocg) * PE_M + mi] <=
                  r_do_relu
                    ? relu_i16(sat_i16(
                        (r_acc[mi] * acc_t'(wgt_mem[int'(r_sm_off) + int'(r_ocg) * PE_M + mi])) >>>
                        (unsigned'(wgt_mem[int'(r_ss_off) + int'(r_ocg) * PE_M + mi] & 16'hFFFF))))
                    : sat_i16(
                        (r_acc[mi] * acc_t'(wgt_mem[int'(r_sm_off) + int'(r_ocg) * PE_M + mi])) >>>
                        (unsigned'(wgt_mem[int'(r_ss_off) + int'(r_ocg) * PE_M + mi] & 16'hFFFF)));
              else
                buf_b[int'(r_ot) * int'(r_cout) + int'(r_ocg) * PE_M + mi] <=
                  r_do_relu
                    ? relu_i16(sat_i16(
                        (r_acc[mi] * acc_t'(wgt_mem[int'(r_sm_off) + int'(r_ocg) * PE_M + mi])) >>>
                        (unsigned'(wgt_mem[int'(r_ss_off) + int'(r_ocg) * PE_M + mi] & 16'hFFFF))))
                    : sat_i16(
                        (r_acc[mi] * acc_t'(wgt_mem[int'(r_sm_off) + int'(r_ocg) * PE_M + mi])) >>>
                        (unsigned'(wgt_mem[int'(r_ss_off) + int'(r_ocg) * PE_M + mi] & 16'hFFFF)));
            end
          end
          // advance tile / phase
          if (w_conv_all_done) begin
            // C1→1, C2→2(pool), C3→4(gap)
            if (r_phase == 3'd0)
              r_phase <= 3'd1;
            else if (r_phase == 3'd1)
              r_phase <= 3'd2;
            else if (r_phase == 3'd3)
              r_phase <= 3'd4;
          end else if (r_ocg == r_ocg_last) begin
            r_ocg <= '0;
            r_ot  <= r_ot + 1'b1;
          end else begin
            r_ocg <= r_ocg + 1'b1;
          end
        end

        ST_POOL: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if ((int'(r_ocg) * PE_M + mi) < int'(r_cin)) begin
              buf_a[int'(r_ot) * int'(r_cin) + int'(r_ocg) * PE_M + mi] <=
                (buf_b[(int'(r_ot) * int'(r_stride) + 1) * int'(r_cin) + int'(r_ocg) * PE_M + mi]
                 > buf_b[(int'(r_ot) * int'(r_stride)) * int'(r_cin) + int'(r_ocg) * PE_M + mi])
                  ? buf_b[(int'(r_ot) * int'(r_stride) + 1) * int'(r_cin) + int'(r_ocg) * PE_M + mi]
                  : buf_b[(int'(r_ot) * int'(r_stride)) * int'(r_cin) + int'(r_ocg) * PE_M + mi];
            end
          end
          if (w_pool_done) begin
            r_phase <= 3'd3; // Conv3
          end else if (r_ocg == r_ocg_last) begin
            r_ocg <= '0;
            r_ot  <= r_ot + 1'b1;
          end else begin
            r_ocg <= r_ocg + 1'b1;
          end
        end

        ST_GAP_ACC: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if ((int'(r_gap_cg) * PE_M + mi) < 64)
              r_gap[mi] <= r_gap[mi] + acc_t'(buf_b[int'(r_gap_t) * 64 + int'(r_gap_cg) * PE_M + mi]);
          end
          if (w_gap_acc_done)
            ; // go QUANT next
          else
            r_gap_t <= r_gap_t + 1'b1;
        end

        ST_GAP_Q: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if ((int'(r_gap_cg) * PE_M + mi) < 64)
              buf_a[int'(r_gap_cg) * PE_M + mi] <= sat_i16(
                (r_gap[mi] * acc_t'(wgt_mem[O_GAPM])) >>>
                (unsigned'(wgt_mem[O_GAPS] & 16'hFFFF)));
          end
          if (r_gap_cg == r_ocg_last) begin
            r_phase <= 3'd5; // FC
          end else begin
            r_gap_cg <= r_gap_cg + 1'b1;
            r_gap_t  <= '0;
            for (mi = 0; mi < PE_M; mi++)
              r_gap[mi] <= '0;
          end
        end

        ST_FC_BIAS: begin
          r_fc_ic <= '0;
          for (mi = 0; mi < PE_M; mi++) begin
            if (mi < N_CLASS)
              r_acc[mi] <= acc_t'(wgt_mem[O_FCB + mi]);
            else
              r_acc[mi] <= '0;
          end
        end

        ST_FC_MAC: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if (mi < N_CLASS)
              r_acc[mi] <= r_acc[mi]
                + acc_t'(buf_a[r_fc_ic])
                  * acc_t'(wgt_mem[O_FCW + mi * 64 + int'(r_fc_ic)]);
          end
          if (!w_fc_mac_done)
            r_fc_ic <= r_fc_ic + 1'b1;
        end

        ST_FC_QUANT: begin
          for (mi = 0; mi < PE_M; mi++) begin
            if (mi < N_CLASS)
              scores[mi] <= sat_i16(
                (r_acc[mi] * acc_t'(wgt_mem[O_FCSM + mi])) >>>
                (unsigned'(wgt_mem[O_FCSS + mi] & 16'hFFFF)));
          end
          r_emit_idx <= 4'd0;
          r_m_valid  <= 1'b0;
          r_m_last   <= 1'b0;
        end

        ST_EMIT: begin
          if (!r_m_valid) begin
            r_m_data  <= scores[r_emit_idx];
            r_m_valid <= 1'b1;
            r_m_last  <= (r_emit_idx == 4'(N_CLASS - 1));
          end else if (m_axis_tready) begin
            if (r_emit_idx == 4'(N_CLASS - 1)) begin
              r_m_valid <= 1'b0;
              r_m_last  <= 1'b0;
              r_done    <= 1'b1;
              r_busy    <= 1'b0;
            end else begin
              r_emit_idx <= r_emit_idx + 1'b1;
              r_m_data   <= scores[r_emit_idx + 1];
              r_m_valid  <= 1'b1;
              r_m_last   <= (r_emit_idx + 1 == 4'(N_CLASS - 1));
            end
          end
        end

        ST_ERROR: begin
          r_busy    <= 1'b0;
          r_s_ready <= 1'b0;
          r_m_valid <= 1'b0;
          if (!eng_en)
            r_err <= 8'h00;
        end

        default: ;
      endcase
    end
  end

endmodule
`default_nettype wire
