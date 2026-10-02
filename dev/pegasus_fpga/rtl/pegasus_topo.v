// pegasus_topo.v -- Pegasus P16 拓扑的纯组合邻居生成器与耦合判定器
//
// 地址编码 (packed, 13 bit):  {u[12], w[11:8], k[7:4], z[3:0]}
//   u: 0=垂直, 1=水平;  w: 0..15;  k: 0..11;  z: 0..14
// 线性索引(与 D-Wave Ocean 一致): lin = ((u*16 + w)*12 + k)*15 + z
//
// 邻居槽位固定: slot 0..11 = 内部耦合(internal), 12 = z-1, 13 = z+1 (外部), 14 = 奇偶(odd)
// 移位向量取 dwave-networkx offsets_index=0 (Advantage 实际值)

`default_nettype none

module pegasus_neighbors (
    input  wire        [12:0] addr,     // {u,w,k,z}
    output wire        [14:0] vld,      // 每个槽位有效
    output wire [15*13-1:0] nb         // 15 个邻居地址, slot i 占 [13*i+:13]
);

    wire        u = addr[12];
    wire [3:0]  w = addr[11:8];
    wire [3:0]  k = addr[7:4];
    wire [3:0]  z = addr[3:0];

    // 移位向量 LUT: S0/S1 每项 ∈ {2,6,10}
    function [3:0] s0_lut(input [3:0] i);
        case (i[3:2])
            2'd0: s0_lut = 4'd2;
            2'd1: s0_lut = 4'd10;
            2'd2: s0_lut = 4'd6;
            default: s0_lut = 4'd0;   // i=12..15 不应出现
        endcase
    endfunction
    function [3:0] s1_lut(input [3:0] i);
        case (i[3:2])
            2'd0: s1_lut = 4'd6;
            2'd1: s1_lut = 4'd2;
            2'd2: s1_lut = 4'd10;
            default: s1_lut = 4'd0;
        endcase
    endfunction
    // 主织构边界: w==0 要求 k>=2; w==15 要求 k<10
    function fabric_ok(input [3:0] wi, input [3:0] ki);
        fabric_ok = ~((wi == 4'd0  && ki < 4'd2) ||
                      (wi == 4'd15 && ki >= 4'd10));
    endfunction

    genvar j;
    generate
        for (j = 0; j < 12; j = j + 1) begin : g_int
            if (1'b0) begin end
            wire [3:0] s0j = s0_lut(j[3:0]);
            wire [3:0] s1j = s1_lut(j[3:0]);
            wire [3:0] s0k = s0_lut(k);
            wire [3:0] s1k = s1_lut(k);
            // u=0 (垂直源): 邻居 (1, w1, j, z1), w1 = z + (j < S0[k]), z1 = w - (k < S1[j])
            wire [3:0] w1v = z + (j < s0k ? 4'd1 : 4'd0);
            wire [3:0] z1v = w - (k < s1j ? 4'd1 : 4'd0);
            wire       v_v = (z1v <= 4'd14) && fabric_ok(w1v, j[3:0]);
            // u=1 (水平源): 反解邻居 (0, w0, j, z0), z0 = w - (k < S0[j]), w0 = z + (j < S1[k])
            wire [3:0] z0h = w - (k < s0j ? 4'd1 : 4'd0);
            wire [3:0] w0h = z + (j < s1k ? 4'd1 : 4'd0);
            wire       v_h = (z0h <= 4'd14) && fabric_ok(w0h, j[3:0]);
            wire [3:0] wsel = u ? w0h : w1v;
            wire [3:0] zsel = u ? z0h : z1v;
            assign vld[j] = u ? v_h : v_v;
            assign nb[13*j +: 13] = {~u, wsel, j[3:0], zsel};
        end
    endgenerate

    // 外部: z-1 / z+1 (w,k 不变, 主织构条件不变, 只需 z 在界内)
    assign vld[12]    = (z != 4'd0)  && (z <= 4'd14);
    assign nb[13*12 +: 13] = {u, w, k, z - 4'd1};
    assign vld[13]    = (z <= 4'd13);
    assign nb[13*13 +: 13] = {u, w, k, z + 4'd1};

    // 奇偶: k 翻转最低位 (2j<->2j+1)
    wire [3:0] kn = {k[3:1], ~k[0]};
    assign vld[14]    = fabric_ok(w, kn);
    assign nb[13*14 +: 13] = {u, w, kn, z};

endmodule


module pegasus_coupled (
    input  wire [12:0] a,
    input  wire [12:0] b,
    output wire        coupled
);
    wire       au = a[12],      bu = b[12];
    wire [3:0] aw = a[11:8],    bw = b[11:8];
    wire [3:0] ak = a[7:4],     bk = b[7:4];
    wire [3:0] az = a[3:0],     bz = b[3:0];

    function [3:0] s0(input [3:0] i);
        case (i[3:2]) 2'd0: s0=4'd2; 2'd1: s0=4'd10; 2'd2: s0=4'd6; default: s0=4'd0; endcase
    endfunction
    function [3:0] s1(input [3:0] i);
        case (i[3:2]) 2'd0: s1=4'd6; 2'd1: s1=4'd2; 2'd2: s1=4'd10; default: s1=4'd0; endcase
    endfunction

    // 外部: 同取向/同行/同 k, z 相差 1
    wire ext = (au == bu) && (aw == bw) && (ak == bk) &&
               ((az == bz + 4'd1) || (bz == az + 4'd1));
    // 奇偶: 同取向/同行/同 z, k 相差 1 (即仅最低位不同)
    wire odd = (au == bu) && (aw == bw) && (az == bz) &&
               (ak[3:1] == bk[3:1]) && (ak[0] != bk[0]);

    // 内部: 令 v=(0,..) 垂直, h=(1,..) 水平; 内部边必然跨越取向 (au != bu)
    wire        vfirst = (au == 1'b0);
    wire [3:0]  wv = vfirst ? aw : bw,  wh = vfirst ? bw : aw;
    wire [3:0]  kv = vfirst ? ak : bk,  kh = vfirst ? bk : ak;
    wire [3:0]  zv = vfirst ? az : bz,  zh = vfirst ? bz : az;
    wire [3:0] s0v = s0(kv), s1h = s1(kh);
    wire intl = (au != bu) &&
                (wh == zv + ((kh < s0v) ? 4'd1 : 4'd0)) &&
                (zh == wv - ((kv < s1h) ? 4'd1 : 4'd0));
    // 源端自己不可能耦合到自己 (排除外部/奇偶都不匹配的恒等输入)
    assign coupled = ext | odd | intl;

endmodule

`default_nettype wire
