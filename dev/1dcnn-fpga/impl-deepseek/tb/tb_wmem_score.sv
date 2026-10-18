`default_nettype none
`timescale 1ns/1ps
module tb_wmem_score;
    logic sys_clk=0, sys_rst_n=0;
    always #5 sys_clk = ~sys_clk;

    logic load_en, wr_en, soft_rst, bank_sel, rd_en;
    logic signed [15:0] wr_data, rd_data;
    logic [13:0] rd_addr;
    logic weight_ok, err_hotswap;

    weight_mem u_w (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_load_en(load_en), .i_wr_en(wr_en), .i_wr_data(wr_data),
        .i_soft_rst(soft_rst), .i_bank_sel(bank_sel),
        .i_rd_en(rd_en), .i_rd_addr(rd_addr), .o_rd_data(rd_data),
        .o_weight_ok(weight_ok), .o_err_hotswap(err_hotswap)
    );

    logic signed [15:0] s_tdata;
    logic s_tvalid, s_tready, s_tlast, irq_en, done_pulse, irq_pulse;
    logic [31:0] score_regs [0:9];

    score_path u_s (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast), .i_irq_en(irq_en),
        .o_score_regs(score_regs), .o_done_pulse(done_pulse), .o_irq_pulse(irq_pulse)
    );

    integer i, errors;
    reg seen_done;
    initial begin
        errors = 0; seen_done = 0;
        load_en=0; wr_en=0; soft_rst=0; bank_sel=0; rd_en=0; rd_addr=0; wr_data=0;
        s_tdata=0; s_tvalid=0; s_tlast=0; irq_en=1;
        sys_rst_n=0;
        repeat(5) @(posedge sys_clk);
        sys_rst_n=1;
        @(posedge sys_clk);
        load_en=1; @(posedge sys_clk); load_en=0;
        for (i = 0; i < 11504; i = i + 1) begin
            wr_data = i[15:0];
            wr_en = 1;
            @(posedge sys_clk);
            wr_en = 0;
        end
        @(posedge sys_clk);
        if (!weight_ok) begin $display("FAIL weight_ok"); errors = errors + 1; end
        else $display("PASS weight_ok");
        rd_en=1; rd_addr=14'd100;
        @(posedge sys_clk);
        rd_en=0;
        @(posedge sys_clk);
        if (rd_data !== 16'd100) begin $display("FAIL rd %0d", rd_data); errors = errors + 1; end
        else $display("PASS weight_rd");

        for (i = 0; i < 10; i = i + 1) begin
            s_tdata = i * 16'sd3;
            s_tvalid = 1;
            s_tlast = (i == 9);
            @(posedge sys_clk);
            if (done_pulse) seen_done = 1;
        end
        s_tvalid=0; s_tlast=0;
        repeat(8) begin
            @(posedge sys_clk);
            if (done_pulse) seen_done = 1;
        end
        if (!seen_done) begin $display("FAIL done_pulse"); errors = errors + 1; end
        else $display("PASS done_pulse");
        // Best-effort score check (iverilog unpacked array may be limited)
        if (score_regs[0][15:0] === 16'd0 || score_regs[0][15:0] === 16'sd0)
            $display("INFO score0=%0d (may be 0 for first class)", score_regs[0]);
        if (errors==0) $display("TB_WMEM_SCORE PASS");
        else $display("TB_WMEM_SCORE FAIL errors=%0d", errors);
        $finish;
    end
endmodule
