#ifndef CNN_ENGINE_H_
#define CNN_ENGINE_H_

#include <stdint.h>
#include "cnn_params.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Run baseline net on one window.
 * weights: INT16 little-endian linear blob (WEIGHT_TOTAL_WORDS)
 * window:  WIN_LEN_V1 samples
 * scores:  N_CLASS INT16 outputs
 * Quant: MAC -> scale/shift -> sat i16 -> ReLU (FC: no ReLU)
 */
void cnn_engine_infer(
    const int16_t *weights,
    const int16_t *window,
    int16_t *scores
);

#ifdef __cplusplus
}
#endif

#endif
