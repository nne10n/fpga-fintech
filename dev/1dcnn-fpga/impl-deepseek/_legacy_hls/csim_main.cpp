/**
 * Host csim — no Vitis HLS required (g++ only).
 * Loads synthetic weights + vectors, runs cnn_engine_infer, 0-bit compare vs golden CSV.
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <iostream>

#include "../hls/cnn_engine.h"
#include "../hls/cnn_params.h"
#include "../include/regs.h"

static std::string join_path(const std::string &a, const std::string &b) {
    if (a.empty()) return b;
    if (a.back() == '/') return a + b;
    return a + "/" + b;
}

static bool read_i16_csv(const std::string &path, std::vector<int16_t> &out) {
    std::ifstream ifs(path);
    if (!ifs) return false;
    std::string line;
    if (!std::getline(ifs, line)) return false;
    out.clear();
    std::stringstream ss(line);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        if (tok.empty()) continue;
        long v = std::strtol(tok.c_str(), nullptr, 10);
        out.push_back((int16_t)v);
    }
    return !out.empty();
}

static bool read_weights_bin(const std::string &path, std::vector<int16_t> &w) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz != (long)(WEIGHT_TOTAL_WORDS * 2)) {
        fprintf(stderr, "weight size %ld != expected %d\n", sz, WEIGHT_TOTAL_WORDS * 2);
        fclose(f);
        return false;
    }
    w.resize(WEIGHT_TOTAL_WORDS);
    size_t n = fread(w.data(), 2, WEIGHT_TOTAL_WORDS, f);
    fclose(f);
    return n == WEIGHT_TOTAL_WORDS;
}

struct CaseResult {
    std::string id;
    bool pass;
    std::string detail;
};

int main(int argc, char **argv) {
    std::string root = ".";
    if (argc >= 2) root = argv[1];

    std::string vec = join_path(root, "vectors");
    std::vector<int16_t> weights;
    if (!read_weights_bin(join_path(vec, "weights_synthetic.bin"), weights)) {
        fprintf(stderr, "FAIL: cannot read weights\n");
        return 2;
    }

    /* Discover cases v00..vNN from cases/ */
    std::vector<CaseResult> results;
    int pass_n = 0, fail_n = 0;

    for (int i = 0; i < 64; i++) {
        char id[16];
        snprintf(id, sizeof(id), "v%02d", i);
        std::string in_path = join_path(vec, std::string("cases/") + id + "_in.csv");
        std::string sc_path = join_path(vec, std::string("cases/") + id + "_score.csv");
        std::ifstream probe(in_path);
        if (!probe) break;
        probe.close();

        std::vector<int16_t> win, golden, dut(N_CLASS);
        if (!read_i16_csv(in_path, win) || !read_i16_csv(sc_path, golden)) {
            results.push_back({id, false, "read_error"});
            fail_n++;
            continue;
        }
        if ((int)win.size() != WIN_LEN_V1 || (int)golden.size() != N_CLASS) {
            results.push_back({id, false, "size_mismatch"});
            fail_n++;
            continue;
        }

        cnn_engine_infer(weights.data(), win.data(), dut.data());

        bool ok = true;
        std::string detail;
        for (int c = 0; c < N_CLASS; c++) {
            if (dut[c] != golden[c]) {
                ok = false;
                char buf[64];
                snprintf(buf, sizeof(buf), "c%d got=%d exp=%d; ", c, (int)dut[c], (int)golden[c]);
                detail += buf;
            }
        }
        results.push_back({id, ok, ok ? "ok" : detail});
        if (ok) pass_n++; else fail_n++;
        printf("%s %s\n", id, ok ? "PASS" : "FAIL");
        if (!ok) printf("  %s\n", detail.c_str());
    }

    /* Write report */
    std::string report_path = join_path(root, "reports/bitexact_result.md");
    FILE *rf = fopen(report_path.c_str(), "w");
    if (rf) {
        fprintf(rf, "# Bit-exact csim result\n\n");
        fprintf(rf, "| Item | Value |\n| --- | --- |\n");
        fprintf(rf, "| Date | 2026-10-17 Asia/Shanghai |\n");
        fprintf(rf, "| Implementer | B (impl-deepseek) |\n");
        fprintf(rf, "| Weight seed | 42 (synthetic) |\n");
        fprintf(rf, "| Vector seed | 20261017 |\n");
        fprintf(rf, "| Cases | %zu |\n", results.size());
        fprintf(rf, "| Pass | %d |\n", pass_n);
        fprintf(rf, "| Fail | %d |\n", fail_n);
        fprintf(rf, "| REG_ID | 0x%08X (doc 0x1DCN0101, N→0) |\n", REG_ID_MAGIC);
        fprintf(rf, "\n## Per-case\n\n| ID | Result | Detail |\n| --- | --- | --- |\n");
        for (auto &r : results) {
            fprintf(rf, "| %s | %s | %s |\n", r.id.c_str(), r.pass ? "PASS" : "FAIL", r.detail.c_str());
        }
        fprintf(rf, "\n## Notes\n\n");
        fprintf(rf, "- 0-bit compare of 10 INT16 scores vs Python golden (`ref/fixed_point_cnn.py`).\n");
        fprintf(rf, "- Synthetic weights replaceable via `weight_map.json` + training export.\n");
        fclose(rf);
    }

    printf("Summary: %d pass / %d fail / %zu total\n", pass_n, fail_n, results.size());
    if (fail_n != 0 || pass_n < 32) return 1;
    return 0;
}
