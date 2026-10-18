/**
 * SIM-HOST RTL twin — cycle-approximate sequential PE mirroring rtl/cnn_engine.sv
 * Quant: MAC -> (acc*smult)>>sshift -> sat_i16 -> ReLU (FC no ReLU)
 * Pad Conv1: pad_left=6 (pad_total=12). Compares vs vectors/cases golden CSV.
 */
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>

static const int WIN=2048, NCLS=10, WTOT=11504;
static const int C1_COUT=16,C1_CIN=1,C1_K=16,C1_S=4,C1_PAD=6,C1_ROUT=512;
static const int C2_COUT=32,C2_CIN=16,C2_K=8,C2_S=4,C2_ROUT=127;
static const int POOL_ROUT=63;
static const int C3_COUT=64,C3_CIN=32,C3_K=3,C3_S=1,C3_ROUT=61;
static const int GAP_T=61,GAP_C=64,FC_COUT=10,FC_CIN=64;
static const int OFF_C1W=0,OFF_C1B=256,OFF_C1SM=272,OFF_C1SS=288;
static const int OFF_C2W=304,OFF_C2B=4400,OFF_C2SM=4432,OFF_C2SS=4464;
static const int OFF_C3W=4496,OFF_C3B=10640,OFF_C3SM=10704,OFF_C3SS=10768;
static const int OFF_GAP_RS=10832,OFF_GAP_RM=10833;
static const int OFF_FCW=10834,OFF_FCB=11474,OFF_FCSM=11484,OFF_FCSS=11494;

static inline int16_t sat_i16(int64_t x) {
    if (x > 32767) return 32767;
    if (x < -32768) return -32768;
    return (int16_t)x;
}

static int16_t act_pad(const int16_t* feat, int rin, int cin, int ot, int stride, int pad, int k, int ic) {
    int t = ot * stride + k - pad;
    if (t < 0 || t >= rin) return 0;
    return feat[t * cin + ic];
}

static void conv(const int16_t* in, int rin, int cin, int16_t* out, int rout, int cout,
                 int ksz, int stride, int pad, const int16_t* wblob, int wbase,
                 int bias_b, int sm_b, int ss_b, bool relu, uint64_t* cycles) {
    for (int oc = 0; oc < cout; ++oc) {
        for (int ot = 0; ot < rout; ++ot) {
            int32_t acc = (int32_t)wblob[bias_b + oc];
            (*cycles) += 2; // bias fetch
            for (int ic = 0; ic < cin; ++ic) {
                for (int k = 0; k < ksz; ++k) {
                    int16_t a = act_pad(in, rin, cin, ot, stride, pad, k, ic);
                    int16_t w = wblob[wbase + oc*cin*ksz + ic*ksz + k];
                    acc += (int32_t)a * (int32_t)w;
                    (*cycles) += 2; // ISS_W + MAC
                }
            }
            int16_t sm = wblob[sm_b + oc];
            uint16_t ss = (uint16_t)wblob[ss_b + oc];
            (*cycles) += 4; // sm/ss
            int64_t scaled = ((int64_t)acc * (int64_t)sm) >> ss;
            int16_t v = sat_i16(scaled);
            if (relu && v < 0) v = 0;
            out[ot * cout + oc] = v;
        }
    }
}

static void pool2(const int16_t* in, int16_t* out, uint64_t* cycles) {
    for (int ot = 0; ot < POOL_ROUT; ++ot) {
        for (int oc = 0; oc < C2_COUT; ++oc) {
            int16_t a0 = in[(ot*2) * C2_COUT + oc];
            int16_t a1 = in[(ot*2+1) * C2_COUT + oc];
            out[ot * C2_COUT + oc] = (a0 > a1) ? a0 : a1;
            (*cycles) += 1;
        }
    }
}

static void gap(const int16_t* in, int16_t* out, const int16_t* wblob, uint64_t* cycles) {
    int16_t rm = wblob[OFF_GAP_RM];
    uint16_t rs = (uint16_t)wblob[OFF_GAP_RS];
    for (int c = 0; c < GAP_C; ++c) {
        int32_t acc = 0;
        for (int t = 0; t < GAP_T; ++t) {
            acc += (int32_t)in[t * GAP_C + c];
            (*cycles) += 1;
        }
        (*cycles) += 4;
        int64_t scaled = ((int64_t)acc * (int64_t)rm) >> rs;
        out[c] = sat_i16(scaled);
    }
}

static void fc(const int16_t* in, int16_t* scores, const int16_t* wblob, uint64_t* cycles) {
    for (int oc = 0; oc < FC_COUT; ++oc) {
        int32_t acc = (int32_t)wblob[OFF_FCB + oc];
        (*cycles) += 2;
        for (int ic = 0; ic < FC_CIN; ++ic) {
            acc += (int32_t)in[ic] * (int32_t)wblob[OFF_FCW + oc*FC_CIN + ic];
            (*cycles) += 2;
        }
        int16_t sm = wblob[OFF_FCSM + oc];
        uint16_t ss = (uint16_t)wblob[OFF_FCSS + oc];
        (*cycles) += 4;
        scores[oc] = sat_i16(((int64_t)acc * (int64_t)sm) >> ss);
    }
}

static void infer(const int16_t* win, const int16_t* w, int16_t* scores, uint64_t* cycles) {
    static int16_t b0[8192], b1[8192];
    *cycles = 0;
    // LOAD_WIN
    for (int i = 0; i < WIN; ++i) { b0[i] = win[i]; (*cycles) += 1; }
    conv(b0, 2048, 1, b1, C1_ROUT, C1_COUT, C1_K, C1_S, C1_PAD, w, OFF_C1W, OFF_C1B, OFF_C1SM, OFF_C1SS, true, cycles);
    conv(b1, 512, 16, b0, C2_ROUT, C2_COUT, C2_K, C2_S, 0, w, OFF_C2W, OFF_C2B, OFF_C2SM, OFF_C2SS, true, cycles);
    pool2(b0, b1, cycles);
    conv(b1, 63, 32, b0, C3_ROUT, C3_COUT, C3_K, C3_S, 0, w, OFF_C3W, OFF_C3B, OFF_C3SM, OFF_C3SS, true, cycles);
    gap(b0, b1, w, cycles);
    fc(b1, scores, w, cycles);
    *cycles += 10; // OUT_SCORE beats
}

static bool read_csv(const std::string& path, std::vector<int16_t>& out) {
    std::ifstream ifs(path);
    if (!ifs) return false;
    std::string line; if (!std::getline(ifs, line)) return false;
    out.clear();
    std::stringstream ss(line); std::string tok;
    while (std::getline(ss, tok, ',')) {
        if (tok.empty()) continue;
        out.push_back((int16_t)std::strtol(tok.c_str(), nullptr, 10));
    }
    return !out.empty();
}

int main(int argc, char** argv) {
    std::string root = argc >= 2 ? argv[1] : ".";
    std::string wpath = root + "/vectors/weights_synthetic.bin";
    FILE* f = fopen(wpath.c_str(), "rb");
    if (!f) { fprintf(stderr, "no weights\n"); return 2; }
    std::vector<int16_t> w(WTOT);
    if (fread(w.data(), 2, WTOT, f) != (size_t)WTOT) { fclose(f); return 2; }
    fclose(f);

    int pass=0, fail=0;
    printf("# SIM-HOST RTL twin bitexact\n");
    for (int i = 0; i < 64; ++i) {
        char id[16]; snprintf(id, sizeof(id), "v%02d", i);
        std::string in_p = root + "/vectors/cases/" + id + "_in.csv";
        std::string sc_p = root + "/vectors/cases/" + id + "_score.csv";
        std::vector<int16_t> in, gold, got(NCLS);
        if (!read_csv(in_p, in)) break;
        if (!read_csv(sc_p, gold)) { printf("%s FAIL missing gold\n", id); fail++; continue; }
        if ((int)in.size() != WIN) { printf("%s FAIL win_len %zu\n", id, in.size()); fail++; continue; }
        uint64_t cyc=0;
        infer(in.data(), w.data(), got.data(), &cyc);
        bool ok = (gold.size() >= 10);
        for (int k = 0; k < 10 && ok; ++k) if (got[k] != gold[k]) ok = false;
        if (ok) { printf("%s PASS cycles~%llu\n", id, (unsigned long long)cyc); pass++; }
        else {
            printf("%s FAIL got=", id);
            for (int k=0;k<10;k++) printf("%d%s", got[k], k==9?"":",");
            printf(" gold=");
            for (int k=0;k<10;k++) printf("%d%s", gold[k], k==9?"":",");
            printf("\n");
            fail++;
        }
    }
    printf("SUMMARY pass=%d fail=%d\n", pass, fail);
    return fail ? 1 : 0;
}
