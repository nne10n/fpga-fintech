#pragma once
#include <stdint.h>

#ifdef __SYNTHESIS__
#include <ap_int.h>
typedef ap_int<16> act_t;
typedef ap_int<16> wgt_t;
typedef ap_int<32> acc_t;
typedef ap_int<16> score_t;
#else
typedef int16_t act_t;
typedef int16_t wgt_t;
typedef int32_t acc_t;
typedef int16_t score_t;
#endif

#ifndef PE_M
#define PE_M 16
#endif
#ifndef PE_K_UNROLL
#define PE_K_UNROLL 8
#endif
#define WIN_LEN_MAX 4096
#define N_CLASS 10
#define DATA_W 16
#define ACC_W 32
