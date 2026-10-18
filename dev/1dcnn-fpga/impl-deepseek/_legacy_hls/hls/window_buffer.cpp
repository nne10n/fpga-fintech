/**
 * window_buffer helpers — ping-pong cut of WIN_LEN with HOP=LEN (V1)
 */
#include <stdint.h>
#include <string.h>
#include "cnn_params.h"
#include "../include/regs.h"

typedef struct {
    int16_t bank[2][WIN_LEN_MAX];
    int wr_bank;
    int wr_pos;
    int win_len;
    int win_hop;
    int ready_bank; /* -1 none */
    uint32_t win_seq;
    int err;
} window_buf_t;

extern "C" void window_buf_init(window_buf_t *wb, int len, int hop) {
    memset(wb, 0, sizeof(*wb));
    wb->win_len = len;
    wb->win_hop = hop;
    wb->ready_bank = -1;
    if (!(len == 1024 || len == 2048 || len == 4096) || hop < 1 || hop > len) {
        wb->err = (int)ERR_WIN_PARAM;
    }
}

extern "C" int window_buf_push(window_buf_t *wb, int16_t s) {
    if (wb->err == (int)ERR_WIN_PARAM) return wb->err;
    if (wb->ready_bank >= 0 && wb->wr_pos == 0 &&
        wb->wr_bank != wb->ready_bank) {
        /* both banks occupied conceptually — simple model: ovfl if ready not drained */
    }
    wb->bank[wb->wr_bank][wb->wr_pos++] = s;
    if (wb->wr_pos >= wb->win_len) {
        if (wb->ready_bank >= 0) {
            wb->err = (int)ERR_WIN_OVFL;
            return wb->err;
        }
        wb->ready_bank = wb->wr_bank;
        wb->wr_bank ^= 1;
        wb->wr_pos = 0;
        wb->win_seq++;
    }
    return 0;
}

extern "C" int window_buf_pop(window_buf_t *wb, int16_t *dst) {
    if (wb->ready_bank < 0) return -1;
    memcpy(dst, wb->bank[wb->ready_bank], (size_t)wb->win_len * sizeof(int16_t));
    wb->ready_bank = -1;
    return 0;
}
