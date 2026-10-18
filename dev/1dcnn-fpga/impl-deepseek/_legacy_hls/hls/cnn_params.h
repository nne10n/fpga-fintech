#ifndef CNN_PARAMS_H_
#define CNN_PARAMS_H_

/* HLS-friendly parameters (microarch §0.5 / §4.2) */
#define WIN_LEN_MAX     4096
#define WIN_LEN_V1      2048
#define CH_MAX          2
#define N_CLASS         10
#define PE_M            16
#define PE_K_UNROLL     8
#define DATA_W          16
#define ACC_W           32

#define CONV1_COUT      16
#define CONV1_CIN       1
#define CONV1_K         16
#define CONV1_S         4
#define CONV1_PAD       12
#define CONV1_ROUT      512

#define CONV2_COUT      32
#define CONV2_CIN       16
#define CONV2_K         8
#define CONV2_S         4
#define CONV2_PAD       0
#define CONV2_ROUT      127

#define POOL_K          2
#define POOL_S          2
#define POOL_ROUT       63

#define CONV3_COUT      64
#define CONV3_CIN       32
#define CONV3_K         3
#define CONV3_S         1
#define CONV3_PAD       0
#define CONV3_ROUT      61

#define GAP_C           64
#define FC_COUT         10
#define FC_CIN          64

/* Weight region offsets (words) — must match vectors/weight_map.json */
#define OFF_CONV1_W             0
#define OFF_CONV1_BIAS          256
#define OFF_CONV1_SMULT         272
#define OFF_CONV1_SSHIFT        288
#define OFF_CONV2_W             304
#define OFF_CONV2_BIAS          4400
#define OFF_CONV2_SMULT         4432
#define OFF_CONV2_SSHIFT        4464
#define OFF_CONV3_W             4496
#define OFF_CONV3_BIAS          10640
#define OFF_CONV3_SMULT         10704
#define OFF_CONV3_SSHIFT        10768
#define OFF_GAP_RSHIFT          10832
#define OFF_GAP_RMULT           10833
#define OFF_FC_W                10834
#define OFF_FC_BIAS             11474
#define OFF_FC_SMULT            11484
#define OFF_FC_SSHIFT           11494
#define WEIGHT_TOTAL_WORDS      11504

#endif /* CNN_PARAMS_H_ */
