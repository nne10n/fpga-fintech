// tb_pegasus.v -- 用 Python golden model 生成的向量验证邻居生成器与耦合判定器
`timescale 1ns/1ps
module tb_pegasus;
    reg  [12:0] addr;
    wire [14:0] vld;
    wire [15*13-1:0] nb;
    integer errors, i, v, slot, code, tmp, cnt, au,aw,ak,az, bu,bw,bk,bz;
    reg [12:0] exp;
    wire coupled;
    integer fd;

    reg [12:0] cp_a, cp_b;
    pegasus_neighbors dut_nb (.addr(addr), .vld(vld), .nb(nb));
    pegasus_coupled    dut_cp (.a(cp_a), .b(cp_b), .coupled(coupled));

    task err;
        input integer n;
        begin
            if (errors < 20)
                $display("ERR slot=%0d addr=%h 期望=%h 实际 vld=%b nb=%h", i, addr, exp, vld[i], nb[13*i +: 13]);
            errors = errors + 1;
        end
    endtask

    initial begin
        errors = 0;
        fd = $fopen("vectors_nb.txt", "r");
        if (fd == 0) begin $display("FATAL: no vectors_nb.txt"); $finish; end
        code = $fscanf(fd, "%d", cnt);
        for (v = 0; v < cnt; v = v + 1) begin
            code = $fscanf(fd, "%d", tmp);
            addr = {tmp[12], tmp[11:8], tmp[7:4], tmp[3:0]};
            #1; // 等待组合逻辑传播
            for (i = 0; i < 15; i = i + 1) begin
                code = $fscanf(fd, "%d %d %d %d", au, aw, ak, az);
                if (au < 0) begin
                    if (vld[i] !== 1'b0) err(i);
                end else begin
                    exp = {au[0], aw[3:0], ak[3:0], az[3:0]};
                    if (vld[i] !== 1'b1 || nb[13*i +: 13] !== exp) err(i);
                end
            end
        end
        $fclose(fd);
        $display("[neighbors] %0d 向量比对完成, errors=%0d", cnt, errors);

        fd = $fopen("vectors_cp.txt", "r");
        if (fd == 0) begin $display("FATAL: no vectors_cp.txt"); $finish; end
        code = $fscanf(fd, "%d", cnt);
        for (v = 0; v < cnt; v = v + 1) begin
            code = $fscanf(fd, "%d %d %d %d %d %d %d %d %d",
                           au, aw, ak, az, bu, bw, bk, bz, tmp);
            cp_a = {au[0], aw[3:0], ak[3:0], az[3:0]};
            cp_b = {bu[0], bw[3:0], bk[3:0], bz[3:0]};
            #1;
            if (coupled !== tmp[0]) begin
                if (errors < 20)
                    $display("ERR coupled a=(%0d,%0d,%0d,%0d) b=(%0d,%0d,%0d,%0d) 期望=%0d 实际=%0d",
                             au,aw,ak,az,bu,bw,bk,bz,tmp,coupled);
                errors = errors + 1;
            end
        end
        $fclose(fd);
        $display("[coupled] %0d 向量比对完成, errors=%0d", cnt, errors);
        if (errors == 0) $display("ALL PASS");
        else $display("FAILED");
        $finish;
    end
endmodule
