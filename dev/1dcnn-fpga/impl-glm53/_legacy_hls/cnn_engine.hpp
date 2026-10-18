#pragma once
#include "cnn_types.hpp"
#include "weight_blob_size.h"

/**
 * cnn_engine — Vitis HLS top for baseline 1D-CNN.
 * AXIS in: WIN_LEN act_t beats + TLAST on last
 * AXIS out: 10 score_t beats + TLAST on last
 * Quant: MAC → scale/shift → sat INT16 → ReLU (conv)
 */
void cnn_engine(
    const act_t *act_in,      /* length WIN_LEN (csim array interface) */
    int win_len,
    const wgt_t *weights,     /* WEIGHT_BLOB_WORDS */
    score_t scores[N_CLASS],
    uint32_t *cyc_cnt
);
