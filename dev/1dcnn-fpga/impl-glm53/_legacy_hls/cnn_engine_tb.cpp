#include "cnn_engine.hpp"
#include <cstdio>
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>

static bool load_bin(const char *path, std::vector<int16_t> &o) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    auto n = f.tellg();
    f.seekg(0);
    o.resize((size_t)n / 2);
    f.read((char *)o.data(), n);
    return true;
}

int main(int argc, char **argv) {
    std::string root = argc > 1 ? argv[1] : ".";
    std::vector<int16_t> w, act, gold;
    if (!load_bin((root + "/vectors/weights.bin").c_str(), w)) return 2;
    if (!load_bin((root + "/vectors/v00_allzero.bin").c_str(), act)) return 2;
    score_t scores[N_CLASS];
    uint32_t cyc = 0;
    cnn_engine(act.data(), 2048, w.data(), scores, &cyc);
    std::printf("csim v00 scores:");
    for (int i = 0; i < N_CLASS; ++i) std::printf(" %d", (int)scores[i]);
    std::printf(" cyc=%u\n", cyc);
    return 0;
}
