/**
 * cnn_engine — synthesizable INT16 1D-CNN (Vitis HLS ready)
 * Baseline: Conv1→ReLU→Conv2→ReLU→Pool→Conv3→ReLU→GAP→FC
 * Defaults: PE_M=16, PE_K_UNROLL=8 (pragmas as comments for host g++)
 */
#include "cnn_engine.h"
#include <algorithm>
#include <cstring>

static inline int16_t sat_i16(int64_t v) {
    if (v > 32767) return (int16_t)32767;
    if (v < -32768) return (int16_t)-32768;
    return (int16_t)v;
}

static inline int16_t relu_i16(int16_t v) {
    return v < 0 ? (int16_t)0 : v;
}

/* ---- Conv1: [2048,1] -> [512,16], pad_total=12, s=4, k=16 ---- */
static void conv1_relu(
    const int16_t *win,   /* [2048] */
    const int16_t *w,     /* [16][1][16] */
    const int16_t *bias,
    const int16_t *smult,
    const int16_t *sshift,
    int16_t *out          /* [512][16] row-major */
) {
    const int pad_left = CONV1_PAD / 2;
    /* pad_right = CONV1_PAD - pad_left */
#pragma HLS INLINE off
    for (int oc = 0; oc < CONV1_COUT; oc++) {
#pragma HLS UNROLL factor=1
        for (int t = 0; t < CONV1_ROUT; t++) {
#pragma HLS PIPELINE II=1
            int32_t acc = (int32_t)bias[oc];
            const int base = t * CONV1_S;
            for (int k = 0; k < CONV1_K; k++) {
#pragma HLS UNROLL factor=PE_K_UNROLL
                int idx = base + k - pad_left;
                int16_t act = 0;
                if (idx >= 0 && idx < WIN_LEN_V1) act = win[idx];
                int16_t wt = w[oc * CONV1_K + k]; /* Cin=1 */
                acc += (int32_t)act * (int32_t)wt;
            }
            int sh = (int)(uint16_t)sshift[oc];
            int64_t scaled = ((int64_t)acc * (int64_t)smult[oc]) >> sh;
            out[t * CONV1_COUT + oc] = relu_i16(sat_i16(scaled));
        }
    }
}

/* ---- Conv2: [512,16] -> [127,32], valid, s=4, k=8 ---- */
static void conv2_relu(
    const int16_t *in,  /* [512][16] */
    const int16_t *w,   /* [32][16][8] */
    const int16_t *bias,
    const int16_t *smult,
    const int16_t *sshift,
    int16_t *out        /* [127][32] */
) {
    for (int oc = 0; oc < CONV2_COUT; oc++) {
        for (int t = 0; t < CONV2_ROUT; t++) {
#pragma HLS PIPELINE II=1
            int32_t acc = (int32_t)bias[oc];
            const int base = t * CONV2_S;
            for (int ic = 0; ic < CONV2_CIN; ic++) {
                for (int k = 0; k < CONV2_K; k++) {
#pragma HLS UNROLL factor=PE_K_UNROLL
                    int16_t act = in[(base + k) * CONV2_CIN + ic];
                    int16_t wt = w[(oc * CONV2_CIN + ic) * CONV2_K + k];
                    acc += (int32_t)act * (int32_t)wt;
                }
            }
            int sh = (int)(uint16_t)sshift[oc];
            int64_t scaled = ((int64_t)acc * (int64_t)smult[oc]) >> sh;
            out[t * CONV2_COUT + oc] = relu_i16(sat_i16(scaled));
        }
    }
}

/* ---- MaxPool k=2 s=2: [127,32] -> [63,32] ---- */
static void maxpool(
    const int16_t *in,
    int16_t *out
) {
    for (int t = 0; t < POOL_ROUT; t++) {
#pragma HLS PIPELINE II=1
        int base = t * POOL_S;
        for (int c = 0; c < CONV2_COUT; c++) {
            int16_t a = in[base * CONV2_COUT + c];
            int16_t b = in[(base + 1) * CONV2_COUT + c];
            out[t * CONV2_COUT + c] = (a > b) ? a : b;
        }
    }
}

/* ---- Conv3: [63,32] -> [61,64], valid, s=1, k=3 ---- */
static void conv3_relu(
    const int16_t *in,
    const int16_t *w,
    const int16_t *bias,
    const int16_t *smult,
    const int16_t *sshift,
    int16_t *out
) {
    for (int oc = 0; oc < CONV3_COUT; oc++) {
        for (int t = 0; t < CONV3_ROUT; t++) {
#pragma HLS PIPELINE II=1
            int32_t acc = (int32_t)bias[oc];
            const int base = t * CONV3_S;
            for (int ic = 0; ic < CONV3_CIN; ic++) {
                for (int k = 0; k < CONV3_K; k++) {
#pragma HLS UNROLL factor=3
                    int16_t act = in[(base + k) * CONV3_CIN + ic];
                    int16_t wt = w[(oc * CONV3_CIN + ic) * CONV3_K + k];
                    acc += (int32_t)act * (int32_t)wt;
                }
            }
            int sh = (int)(uint16_t)sshift[oc];
            int64_t scaled = ((int64_t)acc * (int64_t)smult[oc]) >> sh;
            out[t * CONV3_COUT + oc] = relu_i16(sat_i16(scaled));
        }
    }
}

/* ---- GAP: [61,64] -> [64] ---- */
static void gap_layer(
    const int16_t *in,
    int16_t recip_mult,
    uint16_t recip_shift,
    int16_t *out
) {
    for (int c = 0; c < GAP_C; c++) {
#pragma HLS PIPELINE II=1
        int32_t acc = 0;
        for (int t = 0; t < CONV3_ROUT; t++) {
            acc += (int32_t)in[t * GAP_C + c];
        }
        int64_t scaled = ((int64_t)acc * (int64_t)recip_mult) >> (int)recip_shift;
        out[c] = sat_i16(scaled);
    }
}

/* ---- FC: [64] -> [10], no ReLU ---- */
static void fc_layer(
    const int16_t *in,
    const int16_t *w,
    const int16_t *bias,
    const int16_t *smult,
    const int16_t *sshift,
    int16_t *scores
) {
    for (int oc = 0; oc < FC_COUT; oc++) {
#pragma HLS PIPELINE II=1
        int32_t acc = (int32_t)bias[oc];
        for (int ic = 0; ic < FC_CIN; ic++) {
#pragma HLS UNROLL factor=8
            acc += (int32_t)in[ic] * (int32_t)w[oc * FC_CIN + ic];
        }
        int sh = (int)(uint16_t)sshift[oc];
        int64_t scaled = ((int64_t)acc * (int64_t)smult[oc]) >> sh;
        scores[oc] = sat_i16(scaled);
    }
}

void cnn_engine_infer(
    const int16_t *weights,
    const int16_t *window,
    int16_t *scores
) {
#pragma HLS INTERFACE m_axi port=weights offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=window  offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=scores  offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=return

    /* Feature ping-pong buffers (host csim: stack; synth: BRAM) */
    static int16_t buf_a[CONV1_ROUT * CONV1_COUT]; /* 512*16 */
    static int16_t buf_b[CONV2_ROUT * CONV2_COUT]; /* 127*32 */
    static int16_t buf_c[POOL_ROUT * CONV2_COUT];  /* 63*32 */
    static int16_t buf_d[CONV3_ROUT * CONV3_COUT]; /* 61*64 */
    static int16_t gap_v[GAP_C];
#ifndef __SYNTHESIS__
    /* static OK for single-thread csim */
#endif
#pragma HLS BIND_STORAGE variable=buf_a type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=buf_b type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=buf_c type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=buf_d type=ram_2p impl=bram

    const int16_t *w1 = weights + OFF_CONV1_W;
    const int16_t *b1 = weights + OFF_CONV1_BIAS;
    const int16_t *m1 = weights + OFF_CONV1_SMULT;
    const int16_t *s1 = weights + OFF_CONV1_SSHIFT;

    const int16_t *w2 = weights + OFF_CONV2_W;
    const int16_t *b2 = weights + OFF_CONV2_BIAS;
    const int16_t *m2 = weights + OFF_CONV2_SMULT;
    const int16_t *s2 = weights + OFF_CONV2_SSHIFT;

    const int16_t *w3 = weights + OFF_CONV3_W;
    const int16_t *b3 = weights + OFF_CONV3_BIAS;
    const int16_t *m3 = weights + OFF_CONV3_SMULT;
    const int16_t *s3 = weights + OFF_CONV3_SSHIFT;

    int16_t gap_rmult = weights[OFF_GAP_RMULT];
    uint16_t gap_rshift = (uint16_t)weights[OFF_GAP_RSHIFT];

    const int16_t *wf = weights + OFF_FC_W;
    const int16_t *bf = weights + OFF_FC_BIAS;
    const int16_t *mf = weights + OFF_FC_SMULT;
    const int16_t *sf = weights + OFF_FC_SSHIFT;

    conv1_relu(window, w1, b1, m1, s1, buf_a);
    conv2_relu(buf_a, w2, b2, m2, s2, buf_b);
    maxpool(buf_b, buf_c);
    conv3_relu(buf_c, w3, b3, m3, s3, buf_d);
    gap_layer(buf_d, gap_rmult, gap_rshift, gap_v);
    fc_layer(gap_v, wf, bf, mf, sf, scores);
}
