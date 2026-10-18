// cnn_params.svh — network + weight offsets (match vectors/weight_map.json)
`ifndef CNN_PARAMS_SVH
`define CNN_PARAMS_SVH

`define WIN_LEN_V1       2048
`define N_CLASS          10
`define FEAT_DEPTH       16384
`define WMEM_DEPTH       11504
`define WMEM_ADDR_W      14

`define CONV1_COUT       16
`define CONV1_CIN        1
`define CONV1_K          16
`define CONV1_S          4
`define CONV1_PAD_L      6
`define CONV1_PAD_TOTAL  12
`define CONV1_RIN        2048
`define CONV1_ROUT       512
`define OFF_CONV1_W      0
`define OFF_CONV1_BIAS   256
`define OFF_CONV1_SMULT  272
`define OFF_CONV1_SSHIFT 288

`define CONV2_COUT       32
`define CONV2_CIN        16
`define CONV2_K          8
`define CONV2_S          4
`define CONV2_PAD_L      0
`define CONV2_RIN        512
`define CONV2_ROUT       127
`define OFF_CONV2_W      304
`define OFF_CONV2_BIAS   4400
`define OFF_CONV2_SMULT  4432
`define OFF_CONV2_SSHIFT 4464

`define POOL_K           2
`define POOL_S           2
`define POOL_RIN         127
`define POOL_ROUT        63

`define CONV3_COUT       64
`define CONV3_CIN        32
`define CONV3_K          3
`define CONV3_S          1
`define CONV3_PAD_L      0
`define CONV3_RIN        63
`define CONV3_ROUT       61
`define OFF_CONV3_W      4496
`define OFF_CONV3_BIAS   10640
`define OFF_CONV3_SMULT  10704
`define OFF_CONV3_SSHIFT 10768

`define GAP_T            61
`define GAP_C            64
`define OFF_GAP_RSHIFT   10832
`define OFF_GAP_RMULT    10833

`define FC_COUT          10
`define FC_CIN           64
`define OFF_FC_W         10834
`define OFF_FC_BIAS      11474
`define OFF_FC_SMULT     11484
`define OFF_FC_SSHIFT    11494

`endif
