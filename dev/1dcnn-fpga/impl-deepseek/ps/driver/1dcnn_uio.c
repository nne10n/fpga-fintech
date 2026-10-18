/**
 * Minimal UIO/mmap driver skeleton for system_1dcnn_pl register file.
 * Build on target: gcc -O2 -o 1dcnn_demo 1dcnn_uio.c ../vote_alarm.c
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include "1dcnn_regs.h"

#ifndef UIO_SIZE
#define UIO_SIZE 0x1000
#endif

typedef struct {
    volatile uint32_t *base;
    int fd;
    size_t map_len;
} d1cnn_dev_t;

static inline uint32_t r32(d1cnn_dev_t *d, uint32_t off) {
    return d->base[off / 4];
}
static inline void w32(d1cnn_dev_t *d, uint32_t off, uint32_t v) {
    d->base[off / 4] = v;
}

int d1cnn_open(d1cnn_dev_t *d, const char *uio_path, size_t map_len) {
    memset(d, 0, sizeof(*d));
    d->fd = open(uio_path, O_RDWR | O_SYNC);
    if (d->fd < 0) return -1;
    d->map_len = map_len ? map_len : UIO_SIZE;
    d->base = (volatile uint32_t *)mmap(NULL, d->map_len, PROT_READ | PROT_WRITE,
                                        MAP_SHARED, d->fd, 0);
    if (d->base == MAP_FAILED) { close(d->fd); return -2; }
    return 0;
}

void d1cnn_close(d1cnn_dev_t *d) {
    if (d->base && d->base != MAP_FAILED) munmap((void *)d->base, d->map_len);
    if (d->fd >= 0) close(d->fd);
}

int d1cnn_check_id(d1cnn_dev_t *d) {
    uint32_t id = r32(d, REG_ID);
    return (id == REG_ID_MAGIC) ? 0 : -1;
}

void d1cnn_read_scores(d1cnn_dev_t *d, int16_t scores[N_CLASS]) {
    for (int i = 0; i < N_CLASS; i++)
        scores[i] = (int16_t)(r32(d, REG_SCORE(i)) & 0xFFFF);
}

void d1cnn_soft_rst(d1cnn_dev_t *d) {
    uint32_t c = r32(d, REG_CTRL);
    w32(d, REG_CTRL, c | CTRL_SOFT_RST);
    /* hold ≥16 clk — software delay */
    usleep(1);
    w32(d, REG_CTRL, c & ~CTRL_SOFT_RST);
}

#ifdef D1CNN_DRIVER_DEMO_MAIN
int main(void) {
    d1cnn_dev_t dev;
    if (d1cnn_open(&dev, "/dev/uio0", UIO_SIZE) != 0) {
        perror("uio open");
        return 1;
    }
    printf("REG_ID=0x%08x expect=0x%08x %s\n",
           r32(&dev, REG_ID), REG_ID_MAGIC,
           d1cnn_check_id(&dev) == 0 ? "OK" : "MISMATCH");
    d1cnn_close(&dev);
    return 0;
}
#endif
