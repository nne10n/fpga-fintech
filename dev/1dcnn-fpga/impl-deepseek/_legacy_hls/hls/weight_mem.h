/**
 * weight_mem — host/csim model of single-bank INT16 weight BRAM
 * Hot-swap reserved: bank_sel=1 → ERR_HOTSWAP_UNIMPL; feat_hotswap=0
 */
#ifndef WEIGHT_MEM_H_
#define WEIGHT_MEM_H_

#include <stdint.h>
#include <string.h>
#include "cnn_params.h"
#include "../include/regs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int16_t bank0[WEIGHT_TOTAL_WORDS];
    uint32_t wr_ptr;
    uint32_t words_target;
    int weight_ok;
    int load_en;
    int bank_sel; /* reserved */
} weight_mem_t;

static inline void weight_mem_init(weight_mem_t *m) {
    memset(m, 0, sizeof(*m));
}

static inline void weight_mem_start_load(weight_mem_t *m, uint32_t nwords) {
    m->wr_ptr = 0;
    m->words_target = nwords;
    m->weight_ok = 0;
    m->load_en = 1;
}

/** Write one INT16 via REG_WEIGHT_DATA[15:0]; auto-increment wr_ptr */
static inline int weight_mem_write_word(weight_mem_t *m, uint16_t data_lo) {
    if (!m->load_en) return -1;
    if (m->bank_sel != 0) return (int)ERR_HOTSWAP_UNIMPL;
    if (m->wr_ptr >= WEIGHT_TOTAL_WORDS) return -2;
    m->bank0[m->wr_ptr++] = (int16_t)data_lo;
    if (m->words_target && m->wr_ptr >= m->words_target) {
        m->weight_ok = 1;
        m->load_en = 0;
    }
    return 0;
}

/** Sync 1-cycle BRAM read model */
static inline int16_t weight_mem_read(weight_mem_t *m, uint32_t addr) {
    if (addr >= WEIGHT_TOTAL_WORDS) return 0;
    return m->bank0[addr];
}

static inline int weight_mem_load_blob(weight_mem_t *m, const int16_t *blob, uint32_t n) {
    if (n > WEIGHT_TOTAL_WORDS) n = WEIGHT_TOTAL_WORDS;
    memcpy(m->bank0, blob, n * sizeof(int16_t));
    m->wr_ptr = n;
    m->words_target = n;
    m->weight_ok = 1;
    m->load_en = 0;
    m->bank_sel = 0;
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif /* WEIGHT_MEM_H_ */
