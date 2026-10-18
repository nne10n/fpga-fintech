/**
 * preprocess_fir — DC block + 32-tap FIR (bypass path for V1 csim)
 * fir_bypass=1: 1-cycle registered passthrough
 */
#include <stdint.h>
#include "cnn_params.h"

#define FIR_TAPS 32

/* Fixed low-pass-ish coefficients (sum≈32768/16 for mild gain) — V1 placeholder */
static const int16_t FIR_COEF[FIR_TAPS] = {
    64, 128, 256, 384, 512, 640, 768, 896,
    1024, 1152, 1280, 1408, 1536, 1664, 1792, 1920,
    1920, 1792, 1664, 1536, 1408, 1280, 1152, 1024,
    896, 768, 640, 512, 384, 256, 128, 64
};

extern "C" void preprocess_fir_sample(
    int16_t in_sample,
    int bypass,
    int16_t *out_sample,
    int16_t delay_line[FIR_TAPS],
    int *wr_idx
) {
#pragma HLS INLINE off
    if (bypass) {
        *out_sample = in_sample;
        return;
    }
    delay_line[*wr_idx] = in_sample;
    int32_t acc = 0;
    for (int i = 0; i < FIR_TAPS; i++) {
#pragma HLS UNROLL factor=4
        int idx = (*wr_idx - i + FIR_TAPS) % FIR_TAPS;
        acc += (int32_t)delay_line[idx] * (int32_t)FIR_COEF[i];
    }
    *wr_idx = (*wr_idx + 1) % FIR_TAPS;
    /* Q15-ish scale down */
    int64_t y = acc >> 15;
    if (y > 32767) y = 32767;
    if (y < -32768) y = -32768;
    *out_sample = (int16_t)y;
}
