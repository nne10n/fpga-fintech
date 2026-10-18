/**
 * FR-09 skeleton: consecutive N windows with same argmax label → alarm
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../include/regs.h"

#ifndef VOTE_N
#define VOTE_N 3
#endif

typedef struct {
    int labels[VOTE_N];
    int count;      /* how many filled */
    int head;
    int alarm;
} vote_state_t;

static int argmax10(const int16_t s[N_CLASS]) {
    int best = 0;
    int16_t mx = s[0];
    for (int i = 1; i < N_CLASS; ++i) {
        if (s[i] > mx) { mx = s[i]; best = i; }
    }
    return best;
}

void vote_init(vote_state_t *st) {
    memset(st, 0, sizeof(*st));
    for (int i = 0; i < VOTE_N; ++i) st->labels[i] = -1;
}

/** Push one score vector; returns alarm (1 if last N labels identical & valid) */
int vote_push(vote_state_t *st, const int16_t scores[N_CLASS]) {
    int lab = argmax10(scores);
    st->labels[st->head] = lab;
    st->head = (st->head + 1) % VOTE_N;
    if (st->count < VOTE_N) st->count++;
    st->alarm = 0;
    if (st->count < VOTE_N) return 0;
    int first = st->labels[0];
    for (int i = 1; i < VOTE_N; ++i)
        if (st->labels[i] != first) return 0;
    st->alarm = 1;
    return 1;
}

#ifdef VOTE_ALARM_MAIN
int main(void) {
    vote_state_t st;
    vote_init(&st);
    int16_t a[N_CLASS] = {0,0,0,5,0,0,0,0,0,0}; /* class 3 */
    int16_t b[N_CLASS] = {9,0,0,0,0,0,0,0,0,0}; /* class 0 */
    printf("push3=%d\n", vote_push(&st, a));
    printf("push3=%d\n", vote_push(&st, a));
    printf("push3=%d (expect 1)\n", vote_push(&st, a));
    printf("push0=%d (expect 0)\n", vote_push(&st, b));
    return 0;
}
#endif
