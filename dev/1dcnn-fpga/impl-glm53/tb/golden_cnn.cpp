#include "golden_cnn.hpp"
#include <fstream>
#include <stdexcept>
#include <algorithm>
#include <cstring>

namespace cnn1d {

bool WeightBlob::load_bin(const std::string &path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    auto sz = f.tellg();
    f.seekg(0, std::ios::beg);
    if (sz < 0 || (sz % 2) != 0) return false;
    w.resize(static_cast<size_t>(sz) / 2);
    f.read(reinterpret_cast<char *>(w.data()), sz);
    return static_cast<bool>(f) || f.eof();
}

static int16_t sample_at(const int16_t *in, int rin, int cin, int t, int c, int pad_l) {
    int idx = t - pad_l;
    if (idx < 0 || idx >= rin) return 0;
    return in[idx * cin + c];
}

void conv1d(
    const int16_t *in, int rin, int cin,
    int16_t *out, int rout, int cout,
    int k, int stride, int pad_l, int pad_r,
    const int16_t *wgt, const int16_t *bias,
    const int16_t *smult, const int16_t *sshift,
    bool do_relu)
{
    (void)pad_r;
    for (int oc = 0; oc < cout; ++oc) {
        for (int ot = 0; ot < rout; ++ot) {
            int32_t acc = static_cast<int32_t>(bias[oc]);
            int t0 = ot * stride;
            for (int ic = 0; ic < cin; ++ic) {
                for (int kk = 0; kk < k; ++kk) {
                    int16_t a = sample_at(in, rin, cin, t0 + kk, ic, pad_l);
                    int16_t ww = wgt[((oc * cin) + ic) * k + kk];
                    acc += static_cast<int32_t>(a) * static_cast<int32_t>(ww);
                }
            }
            int32_t scaled = (acc * static_cast<int32_t>(smult[oc])) >> static_cast<uint32_t>(sshift[oc] & 0xFFFF);
            int16_t v = sat_i16(scaled);
            if (do_relu) v = relu_i16(v);
            out[ot * cout + oc] = v;
        }
    }
}

void maxpool1d(const int16_t *in, int rin, int cin, int16_t *out, int rout, int k, int stride) {
    for (int c = 0; c < cin; ++c) {
        for (int ot = 0; ot < rout; ++ot) {
            int t0 = ot * stride;
            int16_t mx = in[t0 * cin + c];
            for (int kk = 1; kk < k; ++kk) {
                int t = t0 + kk;
                if (t < rin) {
                    int16_t v = in[t * cin + c];
                    if (v > mx) mx = v;
                }
            }
            out[ot * cin + c] = mx;
        }
    }
}

void gap1d(const int16_t *in, int rin, int cin, int16_t *out,
           int16_t recip_mult, uint16_t recip_shift) {
    for (int c = 0; c < cin; ++c) {
        int32_t sum = 0;
        for (int t = 0; t < rin; ++t) sum += static_cast<int32_t>(in[t * cin + c]);
        int32_t avg = (sum * static_cast<int32_t>(recip_mult)) >> recip_shift;
        out[c] = sat_i16(avg);
    }
}

void fc_layer(const int16_t *in, int cin, int16_t *out, int cout,
              const int16_t *wgt, const int16_t *bias,
              const int16_t *smult, const int16_t *sshift) {
    for (int oc = 0; oc < cout; ++oc) {
        int32_t acc = static_cast<int32_t>(bias[oc]);
        for (int ic = 0; ic < cin; ++ic) {
            acc += static_cast<int32_t>(in[ic]) * static_cast<int32_t>(wgt[oc * cin + ic]);
        }
        int32_t scaled = (acc * static_cast<int32_t>(smult[oc])) >> static_cast<uint32_t>(sshift[oc] & 0xFFFF);
        out[oc] = sat_i16(scaled);  /* no ReLU on logits */
    }
}

void infer_baseline(const int16_t *window, const WeightBlob &wb, int16_t scores[NUM_CLASS]) {
    using L = WeightLayout;
    if (wb.w.size() < L::TOTAL) throw std::runtime_error("weight blob too small");

    std::vector<int16_t> y1(512 * 16), y2(127 * 32), y3(63 * 32), y4(61 * 64), gap(64);

    conv1d(window, 2048, 1, y1.data(), 512, 16, 16, 4, 6, 6,
           wb.ptr(L::CONV1_W), wb.ptr(L::CONV1_B), wb.ptr(L::CONV1_SM), wb.ptr(L::CONV1_SS), true);

    conv1d(y1.data(), 512, 16, y2.data(), 127, 32, 8, 4, 0, 0,
           wb.ptr(L::CONV2_W), wb.ptr(L::CONV2_B), wb.ptr(L::CONV2_SM), wb.ptr(L::CONV2_SS), true);

    maxpool1d(y2.data(), 127, 32, y3.data(), 63, 2, 2);

    conv1d(y3.data(), 63, 32, y4.data(), 61, 64, 3, 1, 0, 0,
           wb.ptr(L::CONV3_W), wb.ptr(L::CONV3_B), wb.ptr(L::CONV3_SM), wb.ptr(L::CONV3_SS), true);

    gap1d(y4.data(), 61, 64, gap.data(),
          wb.w[L::GAP_RM], static_cast<uint16_t>(wb.w[L::GAP_RS]));

    fc_layer(gap.data(), 64, scores, 10,
             wb.ptr(L::FC_W), wb.ptr(L::FC_B), wb.ptr(L::FC_SM), wb.ptr(L::FC_SS));
}

}  // namespace cnn1d
