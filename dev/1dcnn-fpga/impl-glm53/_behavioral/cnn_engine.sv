// cnn_engine.sv — SystemVerilog 1D-CNN DUT (impl-glm53)
// Bit-exact: MAC → scale/shift → sat INT16 → ReLU (FC: no ReLU)
`timescale 1ns / 1ps
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
  // AXIS act in
  input  logic [15:0]       s_axis_tdata,
  input  logic              s_axis_tvalid,
  output logic              s_axis_tready,
  input  logic              s_axis_tlast,
  // AXIS score out
  output logic [15:0]       m_axis_tdata,
  output logic              m_axis_tvalid,
  input  logic              m_axis_tready,
  output logic              m_axis_tlast,
  // Weight write (load) + debug read
  input  logic              wgt_we,
  input  logic [13:0]       wgt_waddr,
  input  logic [15:0]       wgt_wdata,
  input  logic              wgt_re,
  input  logic [13:0]       wgt_raddr,
  output logic [15:0]       wgt_rdata
);

  act_t   act_mem [0:WIN_LEN-1];
  wgt_t   wgt_mem [0:WGT_WORDS-1];
  act_t   buf_a   [0:FEAT_MAX-1];
  act_t   buf_b   [0:FEAT_MAX-1];
  score_t scores  [0:N_CLASS-1];

  typedef enum logic [2:0] {
    ST_IDLE    = 3'd0,
    ST_RECV    = 3'd1,
    ST_COMPUTE = 3'd2,
    ST_EMIT    = 3'd3,
    ST_ERROR   = 3'd4
  } state_t;

  state_t      state;
  logic [10:0] recv_cnt;
  logic [3:0]  emit_idx;
  logic [31:0] cyc_r;
  logic        done_r;
  logic        busy_r;
  logic [7:0]  err_r;
  logic        m_valid_r;
  logic [15:0] m_data_r;
  logic        m_last_r;

  assign busy         = busy_r;
  assign done         = done_r;
  assign cyc_cnt      = cyc_r;
  assign err_code     = err_r;
  assign m_axis_tdata = m_data_r;
  assign m_axis_tvalid= m_valid_r;
  assign m_axis_tlast = m_last_r;

  always_ff @(posedge clk) begin
    if (wgt_we && (int'(wgt_waddr) < WGT_WORDS))
      wgt_mem[wgt_waddr] <= wgt_t'(wgt_wdata);
    if (wgt_re)
      wgt_rdata <= wgt_mem[wgt_raddr];
  end

  // ---- layer tasks (bit-exact math) ----
  task automatic run_conv(
      input int in_sel, // 0=act_mem, 1=buf_a, 2=buf_b
      input int rin, input int cin,
      input int rout, input int cout,
      input int k, input int stride, input int pad_l,
      input int w_off, input int b_off, input int sm_off, input int ss_off,
      input bit do_relu,
      input int out_sel // 1=buf_a, 2=buf_b
  );
    int oc, ot, ic, kk, t0, widx, idx;
    acc_t acc, scaled;
    act_t a, v;
    wgt_t ww;
    for (oc = 0; oc < cout; oc++) begin
      for (ot = 0; ot < rout; ot++) begin
        acc = acc_t'(wgt_mem[b_off + oc]);
        t0 = ot * stride;
        for (ic = 0; ic < cin; ic++) begin
          for (kk = 0; kk < k; kk++) begin
            idx = t0 + kk - pad_l;
            if (idx < 0 || idx >= rin) begin
              a = 16'sd0;
            end else if (in_sel == 0) begin
              a = act_mem[idx];
            end else if (in_sel == 1) begin
              a = buf_a[idx * cin + ic];
            end else begin
              a = buf_b[idx * cin + ic];
            end
            widx = ((oc * cin) + ic) * k + kk;
            ww = wgt_mem[w_off + widx];
            acc = acc + acc_t'(a) * acc_t'(ww);
          end
        end
        scaled = (acc * acc_t'(wgt_mem[sm_off + oc])) >>>
                 (unsigned'(wgt_mem[ss_off + oc] & 16'hFFFF));
        v = sat_i16(scaled);
        if (do_relu) v = relu_i16(v);
        if (out_sel == 1) buf_a[ot * cout + oc] = v;
        else              buf_b[ot * cout + oc] = v;
      end
    end
  endtask

  task automatic run_pool;
    int c, ot, t0;
    act_t mx, v2;
    for (c = 0; c < 32; c++) begin
      for (ot = 0; ot < 63; ot++) begin
        t0 = ot * 2;
        mx = buf_b[t0 * 32 + c];
        v2 = buf_b[(t0 + 1) * 32 + c];
        if (v2 > mx) mx = v2;
        buf_a[ot * 32 + c] = mx;
      end
    end
  endtask

  task automatic run_gap;
    int c, t;
    acc_t sum;
    wgt_t rmul;
    int unsigned rsh;
    rmul = wgt_mem[O_GAPM];
    rsh  = 32'(unsigned'(wgt_mem[O_GAPS] & 16'hFFFF));
    for (c = 0; c < 64; c++) begin
      sum = '0;
      for (t = 0; t < 61; t++) sum = sum + acc_t'(buf_b[t * 64 + c]);
      buf_a[c] = sat_i16((sum * acc_t'(rmul)) >>> rsh);
    end
  endtask

  task automatic run_fc;
    int oc, ic;
    acc_t acc, scaled;
    for (oc = 0; oc < N_CLASS; oc++) begin
      acc = acc_t'(wgt_mem[O_FCB + oc]);
      for (ic = 0; ic < 64; ic++)
        acc = acc + acc_t'(buf_a[ic]) * acc_t'(wgt_mem[O_FCW + oc * 64 + ic]);
      scaled = (acc * acc_t'(wgt_mem[O_FCSM + oc])) >>>
               (unsigned'(wgt_mem[O_FCSS + oc] & 16'hFFFF));
      scores[oc] = sat_i16(scaled);
    end
  endtask

  task automatic run_all;
    run_conv(0, 2048, 1, 512, 16, 16, 4, 6, O_C1W, O_C1B, O_C1SM, O_C1SS, 1'b1, 1);
    run_conv(1, 512, 16, 127, 32, 8, 4, 0, O_C2W, O_C2B, O_C2SM, O_C2SS, 1'b1, 2);
    run_pool();
    run_conv(1, 63, 32, 61, 64, 3, 1, 0, O_C3W, O_C3B, O_C3SM, O_C3SS, 1'b1, 2);
    run_gap();
    run_fc();
  endtask

  // ---- control FSM ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= ST_IDLE;
      recv_cnt      <= '0;
      emit_idx      <= '0;
      cyc_r         <= '0;
      done_r        <= 1'b0;
      busy_r        <= 1'b0;
      err_r         <= 8'h00;
      s_axis_tready <= 1'b0;
      m_valid_r     <= 1'b0;
      m_data_r      <= '0;
      m_last_r      <= 1'b0;
    end else begin
      done_r <= 1'b0;

      unique case (state)
        ST_IDLE: begin
          m_valid_r     <= 1'b0;
          m_last_r      <= 1'b0;
          busy_r        <= 1'b0;
          s_axis_tready <= eng_en && weight_ok;
          if (eng_en && s_axis_tvalid && s_axis_tready) begin
            if (!weight_ok) begin
              err_r <= 8'h10;
              state <= ST_ERROR;
              s_axis_tready <= 1'b0;
            end else begin
              act_mem[0] <= act_t'(s_axis_tdata);
              recv_cnt   <= 11'd1;
              busy_r     <= 1'b1;
              cyc_r      <= 32'd1;
              err_r      <= 8'h00;
              if (s_axis_tlast) begin
                s_axis_tready <= 1'b0;
                state <= ST_COMPUTE;
              end else begin
                state <= ST_RECV;
              end
            end
          end else if (eng_en && !weight_ok && s_axis_tvalid) begin
            // refuse window if weights not ready
            err_r <= 8'h10;
            state <= ST_ERROR;
            s_axis_tready <= 1'b0;
          end
        end

        ST_RECV: begin
          s_axis_tready <= 1'b1;
          cyc_r <= cyc_r + 1'b1;
          if (s_axis_tvalid && s_axis_tready) begin
            act_mem[recv_cnt] <= act_t'(s_axis_tdata);
            if (s_axis_tlast || (recv_cnt == 11'(WIN_LEN - 1))) begin
              s_axis_tready <= 1'b0;
              state <= ST_COMPUTE;
            end else begin
              recv_cnt <= recv_cnt + 1'b1;
            end
          end
        end

        ST_COMPUTE: begin
          s_axis_tready <= 1'b0;
          cyc_r <= cyc_r + 1'b1;
          run_all();
          emit_idx  <= 4'd0;
          m_data_r  <= scores[0]; // will be overwritten after run_all in same block?
          // scores written by run_all in this timestep; sample after
          state <= ST_EMIT;
        end

        ST_EMIT: begin
          cyc_r <= cyc_r + 1'b1;
          // Present scores[emit_idx]; advance on ready handshake
          if (!m_valid_r) begin
            m_data_r  <= scores[emit_idx];
            m_valid_r <= 1'b1;
            m_last_r  <= (emit_idx == 4'(N_CLASS - 1));
          end else if (m_axis_tready) begin
            if (emit_idx == 4'(N_CLASS - 1)) begin
              m_valid_r <= 1'b0;
              m_last_r  <= 1'b0;
              done_r    <= 1'b1;
              busy_r    <= 1'b0;
              state     <= ST_IDLE;
            end else begin
              emit_idx  <= emit_idx + 1'b1;
              m_data_r  <= scores[emit_idx + 1];
              m_valid_r <= 1'b1;
              m_last_r  <= (emit_idx + 1 == 4'(N_CLASS - 1));
            end
          end
        end

        ST_ERROR: begin
          busy_r        <= 1'b0;
          s_axis_tready <= 1'b0;
          m_valid_r     <= 1'b0;
          if (!eng_en) begin
            err_r <= 8'h00;
            state <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
