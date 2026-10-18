/**
 * Bit-exact INT16 1D-CNN reference (software golden).
 * Quant order (microarch §0.3): MAC → scale/shift → saturate INT16 → ReLU
 * Baseline net Phase0 §6.1 / microarch §4.2.
 */
#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace cnn1d {

constexpr int WIN_LEN = 2048;
constexpr int NUM_CLASS = 10;

inline int16_t sat_i16(int32_t x) {
    if (x > 32767) return 32767;
    if (x < -32768) return -32768;
    return static_cast<int16_t>(x);
}

inline int16_t relu_i16(int16_t x) { return x < 0 ? 0 : x; }

struct WeightBlob {
    std::vector<int16_t> w;  // linear INT16 words per weight_map.json
    bool load_bin(const std::string &path);
    const int16_t *ptr(size_t off) const { return w.data() + off; }
};

/* Offsets matching scripts/gen_weights.py / weight_map.json order */
struct WeightLayout {
    static constexpr size_t CONV1_W = 0;
    static constexpr size_t CONV1_B = 256;
    static constexpr size_t CONV1_SM = 272;
    static constexpr size_t CONV1_SS = 288;
    static constexpr size_t CONV2_W = 304;
    static constexpr size_t CONV2_B = 4400;
    static constexpr size_t CONV2_SM = 4432;
    static constexpr size_t CONV2_SS = 4464;
    static constexpr size_t CONV3_W = 4496;
    static constexpr size_t CONV3_B = 10640;
    static constexpr size_t CONV3_SM = 10704;
    static constexpr size_t CONV3_SS = 10768;
    static constexpr size_t GAP_RM = 10832;
    static constexpr size_t GAP_RS = 10833;
    static constexpr size_t FC_W = 10834;
    static constexpr size_t FC_B = 11474;
    static constexpr size_t FC_SM = 11484;
    static constexpr size_t FC_SS = 11494;
    static constexpr size_t TOTAL = 11504;
};

void conv1d(
    const int16_t *in, int rin, int cin,
    int16_t *out, int rout, int cout,
    int k, int stride, int pad_l, int pad_r,
    const int16_t *wgt,   /* [cout][cin][k] */
    const int16_t *bias,
    const int16_t *smult,
    const int16_t *sshift,
    bool do_relu);

void maxpool1d(const int16_t *in, int rin, int cin, int16_t *out, int rout, int k, int stride);

void gap1d(const int16_t *in, int rin, int cin, int16_t *out,
           int16_t recip_mult, uint16_t recip_shift);

void fc_layer(const int16_t *in, int cin, int16_t *out, int cout,
              const int16_t *wgt, const int16_t *bias,
              const int16_t *smult, const int16_t *sshift);

/** Full baseline forward: 2048 → 10 scores INT16 */
void infer_baseline(const int16_t *window, const WeightBlob &wb, int16_t scores[NUM_CLASS]);

}  // namespace cnn1d
