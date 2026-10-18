/**
 * vote_alarm.c — FR-09 skeleton (PS-side majority vote over recent labels)
 * PL must NOT implement voting; this runs on PS after reading REG_SCORE0..9.
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#ifndef VOTE_N
#define VOTE_N 3
#endif

typedef struct {
    int labels[VOTE_N];
    int count;
    int head;
    int alarm;
} vote_state_t;

void vote_init(vote_state_t *v) {
    memset(v, 0, sizeof(*v));
    for (int i = 0; i < VOTE_N; i++) v->labels[i] = -1;
}

/** Push argmax label; alarm=1 iff last VOTE_N labels all equal and valid */
int vote_push(vote_state_t *v, int label) {
    v->labels[v->head] = label;
    v->head = (v->head + 1) % VOTE_N;
    if (v->count < VOTE_N) v->count++;
    if (v->count < VOTE_N) { v->alarm = 0; return 0; }
    int first = v->labels[0];
    int all = 1;
    for (int i = 1; i < VOTE_N; i++) {
        if (v->labels[i] != first) { all = 0; break; }
    }
    v->alarm = (all && first >= 0) ? 1 : 0;
    return v->alarm;
}

int score_argmax(const int16_t *scores, int n) {
    int best = 0;
    int16_t bv = scores[0];
    for (int i = 1; i < n; i++) {
        if (scores[i] > bv) { bv = scores[i]; best = i; }
    }
    return best;
}

#ifdef VOTE_ALARM_SELFTEST
int main(void) {
    vote_state_t v;
    vote_init(&v);
    /* inject equal labels → alarm */
    vote_push(&v, 3);
    vote_push(&v, 3);
    int a = vote_push(&v, 3);
    printf("alarm_equal=%d (expect 1)\n", a);
    vote_push(&v, 1);
    a = vote_push(&v, 3);
    printf("alarm_mixed=%d (expect 0)\n", a);
    return (a == 0) ? 0 : 1;
}
#endif
