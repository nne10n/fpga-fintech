/**
 * Golden-only path: tb/golden_cnn → vectors/ ID.golden.bin (glob)
 * Must NOT link hls/cnn_engine.
 */
#include "golden_cnn.hpp"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static std::string join(const std::string &a, const std::string &b) {
    if (a.empty()) return b;
    if (a.back() == '/') return a + b;
    return a + "/" + b;
}

static bool load_i16(const std::string &path, std::vector<int16_t> &out, size_t n) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.resize(n);
    f.read(reinterpret_cast<char *>(out.data()), static_cast<std::streamsize>(n * 2));
    return static_cast<bool>(f) || f.eof();
}

static std::vector<std::string> parse_ids(const std::string &man) {
    std::vector<std::string> ids;
    size_t pos = 0;
    while (true) {
        size_t p = man.find("\"id\":", pos);
        if (p == std::string::npos) break;
        size_t q1 = man.find('"', p + 5);
        size_t q2 = man.find('"', q1 + 1);
        if (q1 == std::string::npos || q2 == std::string::npos) break;
        ids.push_back(man.substr(q1 + 1, q2 - q1 - 1));
        pos = q2 + 1;
    }
    return ids;
}

int main(int argc, char **argv) {
    std::string root = argc >= 2 ? argv[1] : ".";
    std::string vecdir = join(root, "vectors");
    cnn1d::WeightBlob wb;
    if (!wb.load_bin(join(vecdir, "weights.bin"))) {
        std::fprintf(stderr, "FAIL load weights\n");
        return 2;
    }
    std::ifstream mf(join(vecdir, "manifest.json"));
    if (!mf) { std::fprintf(stderr, "FAIL manifest\n"); return 2; }
    std::stringstream ss; ss << mf.rdbuf();
    auto ids = parse_ids(ss.str());
    if (ids.size() < 32) {
        std::fprintf(stderr, "FAIL need ≥32 cases, got %zu\n", ids.size());
        return 2;
    }
    int n = 0;
    for (const auto &id : ids) {
        std::vector<int16_t> win;
        if (!load_i16(join(vecdir, id + ".bin"), win, cnn1d::WIN_LEN)) {
            std::fprintf(stderr, "FAIL load %s\n", id.c_str());
            return 2;
        }
        int16_t scores[cnn1d::NUM_CLASS];
        cnn1d::infer_baseline(win.data(), wb, scores);
        std::ofstream gf(join(vecdir, id + ".golden.bin"), std::ios::binary);
        gf.write(reinterpret_cast<const char *>(scores), sizeof(scores));
        ++n;
    }
    std::printf("golden: wrote %d *.golden.bin via tb/golden_cnn (no HLS DUT)\n", n);
    return 0;
}
