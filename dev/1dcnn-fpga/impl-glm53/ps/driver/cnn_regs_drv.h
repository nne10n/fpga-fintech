/**
 * Minimal mmap/UIO-oriented driver header using include/regs.h
 */
#ifndef CNN_REGS_DRV_H_
#define CNN_REGS_DRV_H_

#include <stdint.h>
#include <stddef.h>
#include "../../include/regs.h"

typedef struct {
    volatile uint32_t *base; /* mapped AXI-Lite window */
} cnn_dev_t;

static inline uint32_t cnn_read(cnn_dev_t *d, uint32_t off) {
    return d->base[off / 4u];
}
static inline void cnn_write(cnn_dev_t *d, uint32_t off, uint32_t v) {
    d->base[off / 4u] = v;
}

static inline uint32_t cnn_id(cnn_dev_t *d) { return cnn_read(d, REG_ID); }

static inline int cnn_weight_ok(cnn_dev_t *d) {
    return (cnn_read(d, REG_STATUS) & STATUS_WEIGHT_OK) != 0;
}

static inline int cnn_feat_hotswap(cnn_dev_t *d) {
    return (cnn_read(d, REG_STATUS) & STATUS_FEAT_HOTSWAP) != 0; /* V1: 0 */
}

/** Load INT16 words via REG_WEIGHT_DATA (data[15:0]), auto-increment wr_ptr */
static inline void cnn_load_weights(cnn_dev_t *d, const int16_t *w, uint32_t nwords) {
    cnn_write(d, REG_WEIGHT_WORDS, nwords);
    cnn_write(d, REG_WEIGHT_CTRL, WCTRL_LOAD_EN);
    for (uint32_t i = 0; i < nwords; ++i)
        cnn_write(d, REG_WEIGHT_DATA, (uint32_t)(uint16_t)w[i]);
    cnn_write(d, REG_WEIGHT_CTRL, 0);
}

static inline void cnn_read_scores(cnn_dev_t *d, int16_t out[N_CLASS]) {
    for (int i = 0; i < N_CLASS; ++i)
        out[i] = (int16_t)(cnn_read(d, REG_SCORE(i)) & 0xFFFFu);
}

static inline void cnn_enable(cnn_dev_t *d, int eng, int capt, int fir_bypass) {
    uint32_t v = 0;
    if (eng) v |= CTRL_ENG_EN;
    if (capt) v |= CTRL_CAPT_EN;
    if (fir_bypass) v |= CTRL_FIR_BYPASS;
    cnn_write(d, REG_CTRL, v);
}

#endif
