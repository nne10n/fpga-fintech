#include "cnn_engine.hpp"
#include <algorithm>

/* Reuse same math as tb golden — keep bit-exact with software reference.
 * For HLS, include simplified loops with #pragma HLS hints. */

static inline act_t sat_i16(acc_t x) {
    if (x > 32767) return 32767;
    if (x < -32768) return -32768;
    return (act_t)x;
}

static inline act_t relu(act_t x) { return x < 0 ? (act_t)0 : x; }

/* Offsets identical to WeightLayout in tb/golden_cnn.hpp */
enum {
    O_C1W=0, O_C1B=256, O_C1SM=272, O_C1SS=288,
    O_C2W=304, O_C2B=4400, O_C2SM=4432, O_C2SS=4464,
    O_C3W=4496, O_C3B=10640, O_C3SM=10704, O_C3SS=10768,
    O_GAPM=10832, O_GAPS=10833,
    O_FCW=10834, O_FCB=11474, O_FCSM=11484, O_FCSS=11494
};

static act_t at(const act_t *in, int rin, int cin, int t, int c, int pad_l) {
    int idx = t - pad_l;
    if (idx < 0 || idx >= rin) return 0;
    return in[idx * cin + c];
}

static void conv1d(
    const act_t *in, int rin, int cin,
    act_t *out, int rout, int cout,
    int k, int stride, int pad_l,
    const wgt_t *wgt, const wgt_t *bias, const wgt_t *sm, const wgt_t *ss,
    int do_relu)
{
#pragma HLS INLINE off
    for (int oc = 0; oc < cout; ++oc) {
#pragma HLS LOOP_TRIPCOUNT min=16 max=64
        for (int ot = 0; ot < rout; ++ot) {
#pragma HLS PIPELINE II=1
            acc_t acc = (acc_t)bias[oc];
            int t0 = ot * stride;
            for (int ic = 0; ic < cin; ++ic) {
                for (int kk = 0; kk < k; ++kk) {
#pragma HLS UNROLL factor=PE_K_UNROLL
                    act_t a = at(in, rin, cin, t0 + kk, ic, pad_l);
                    wgt_t ww = wgt[((oc * cin) + ic) * k + kk];
                    acc += (acc_t)a * (acc_t)ww;
                }
            }
            acc_t scaled = (acc * (acc_t)sm[oc]) >> (unsigned)(ss[oc] & 0xFFFF);
            act_t v = sat_i16(scaled);
            if (do_relu) v = relu(v);
            out[ot * cout + oc] = v;
        }
    }
}

void cnn_engine(
    const act_t *act_in,
    int win_len,
    const wgt_t *weights,
    score_t scores[N_CLASS],
    uint32_t *cyc_cnt)
{
#pragma HLS INTERFACE m_axi port=act_in offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=weights offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=scores offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=win_len
#pragma HLS INTERFACE s_axilite port=cyc_cnt
#pragma HLS INTERFACE s_axilite port=return

    /* V1 fixed baseline shapes; win_len must be 2048 for NFR-01 path */
    (void)win_len;
    uint32_t cycles = 0;

    static act_t y1[512 * 16];
    static act_t y2[127 * 32];
    static act_t y3[63 * 32];
    static act_t y4[61 * 64];
    static act_t gap[64];
#pragma HLS BIND_STORAGE variable=y1 type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=y2 type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=y3 type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=y4 type=ram_2p impl=bram

    conv1d(act_in, 2048, 1, y1, 512, 16, 16, 4, 6,
           &weights[O_C1W], &weights[O_C1B], &weights[O_C1SM], &weights[O_C1SS], 1);
    cycles += 512u * 16u;

    conv1d(y1, 512, 16, y2, 127, 32, 8, 4, 0,
           &weights[O_C2W], &weights[O_C2B], &weights[O_C2SM], &weights[O_C2SS], 1);
    cycles += 127u * 32u;

    for (int c = 0; c < 32; ++c) {
        for (int ot = 0; ot < 63; ++ot) {
            int t0 = ot * 2;
            act_t mx = y2[t0 * 32 + c];
            act_t v2 = y2[(t0 + 1) * 32 + c];
            if (v2 > mx) mx = v2;
            y3[ot * 32 + c] = mx;
        }
    }
    cycles += 63u * 32u;

    conv1d(y3, 63, 32, y4, 61, 64, 3, 1, 0,
           &weights[O_C3W], &weights[O_C3B], &weights[O_C3SM], &weights[O_C3SS], 1);
    cycles += 61u * 64u;

    wgt_t rmul = weights[O_GAPM];
    unsigned rsh = (unsigned)(weights[O_GAPS] & 0xFFFF);
    for (int c = 0; c < 64; ++c) {
        acc_t sum = 0;
        for (int t = 0; t < 61; ++t) sum += (acc_t)y4[t * 64 + c];
        gap[c] = sat_i16((sum * (acc_t)rmul) >> rsh);
    }
    cycles += 64u * 61u;

    for (int oc = 0; oc < N_CLASS; ++oc) {
        acc_t acc = (acc_t)weights[O_FCB + oc];
        for (int ic = 0; ic < 64; ++ic)
            acc += (acc_t)gap[ic] * (acc_t)weights[O_FCW + oc * 64 + ic];
        acc_t scaled = (acc * (acc_t)weights[O_FCSM + oc]) >> (unsigned)(weights[O_FCSS + oc] & 0xFFFF);
        scores[oc] = sat_i16(scaled);
    }
    cycles += 10u * 64u;

    *cyc_cnt = cycles;
}
