/**
 * DUT↔golden 0-bit comparator
 *   Golden path: vectors/ ID.golden.bin  (from tb/gen_golden → tb/golden_cnn only)
 *   DUT path:    hls/cnn_engine        (synthesizable HLS sources only)
 * Must NOT call cnn1d::infer_baseline.
 */
#include "cnn_engine.hpp"
#include "../include/regs.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <cstdint>
#include <chrono>

static std::string join(const std::string &a, const std::string &b) {
    if (a.empty()) return b;
    if (a.back() == '/') return a + b;
    return a + "/" + b;
}

static bool load_i16(const std::string &path, std::vector<int16_t> &out, size_t n) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    auto sz = f.tellg();
    f.seekg(0, std::ios::beg);
    if (sz < 0 || (size_t)sz != n * 2) return false;
    out.resize(n);
    f.read(reinterpret_cast<char *>(out.data()), sz);
    return true;
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
    std::string reportdir = join(root, "reports");

    std::vector<int16_t> weights;
    if (!load_i16(join(vecdir, "weights.bin"), weights, WEIGHT_BLOB_WORDS)) {
        std::fprintf(stderr, "FAIL: load weights.bin (expect %d words)\n", WEIGHT_BLOB_WORDS);
        return 2;
    }

    std::ifstream mf(join(vecdir, "manifest.json"));
    if (!mf) { std::fprintf(stderr, "FAIL: manifest\n"); return 2; }
    std::stringstream ss; ss << mf.rdbuf();
    auto ids = parse_ids(ss.str());
    if (ids.size() < 32) {
        std::fprintf(stderr, "FAIL: need ≥32 cases, got %zu\n", ids.size());
        return 2;
    }

    int pass = 0, fail = 0;
    std::vector<std::string> fail_ids;
    std::ostringstream report;

    report << "# Bit-exact result (impl-glm53) — DUT ↔ independent golden\n\n";
    report << "| Field | Value |\n| --- | --- |\n";
    report << "| DUT path | `hls/cnn_engine.cpp` → `cnn_engine()` |\n";
    report << "| Golden path | `tb/golden_cnn.cpp` → `vectors/ ID.golden.bin` (via `tb/gen_golden`) |\n";
    report << "| Comparator | `tb/run_bitexact.cpp` (links HLS only; does not call golden) |\n";
    report << "| REG_ID | 0x" << std::hex << REG_ID_VALUE << std::dec << " |\n";
    report << "| STATUS feat_hotswap | 0 |\n";
    report << "| Weight words | " << weights.size() << " |\n";
    report << "| Vectors | " << ids.size() << " |\n";
    report << "| Quant order | MAC → scale/shift → sat INT16 → ReLU |\n";
    report << "| Tolerance | **0-bit** |\n\n";
    report << "## Cases\n\n";
    report << "| ID | Result | golden[0..9] | DUT[0..9] |\n| --- | --- | --- | --- |\n";

    auto t0 = std::chrono::steady_clock::now();
    for (const auto &id : ids) {
        std::vector<int16_t> win, golden;
        if (!load_i16(join(vecdir, id + ".bin"), win, 2048)) {
            fail++; fail_ids.push_back(id + ":load_in");
            report << "| " << id << " | FAIL load input | | |\n";
            continue;
        }
        if (!load_i16(join(vecdir, id + ".golden.bin"), golden, N_CLASS)) {
            fail++; fail_ids.push_back(id + ":load_golden");
            report << "| " << id << " | FAIL load golden | | |\n";
            continue;
        }

        score_t dut[N_CLASS];
        uint32_t cyc = 0;
        cnn_engine(win.data(), 2048, weights.data(), dut, &cyc);

        bool ok = true;
        for (int i = 0; i < N_CLASS; ++i) {
            if (static_cast<int16_t>(dut[i]) != golden[i]) ok = false;
        }

        report << "| " << id << " | " << (ok ? "PASS" : "FAIL") << " |";
        for (int i = 0; i < N_CLASS; ++i) report << " " << golden[i];
        report << " |";
        for (int i = 0; i < N_CLASS; ++i) report << " " << static_cast<int>(dut[i]);
        report << " |\n";

        if (ok) pass++;
        else { fail++; fail_ids.push_back(id); }
    }
    auto t1 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    report << "\n## Summary\n\n";
    report << "- **PASS: " << pass << " / " << (pass + fail) << "**\n";
    report << "- FAIL: " << fail << "\n";
    if (!fail_ids.empty()) {
        report << "- Fail IDs:";
        for (auto &x : fail_ids) report << " `" << x << "`";
        report << "\n";
    }
    report << "- Wall time: " << ms << " ms\n";
    report << "- Independence: golden binary built from `tb/golden_cnn*.cpp` only; "
              "DUT binary from `hls/cnn_engine.cpp` only; comparator never invokes golden API.\n";

    std::string outp = join(reportdir, "bitexact_result.md");
    {
        std::ofstream of(outp);
        of << report.str();
    }
    std::printf("%s", report.str().c_str());
    std::printf("wrote %s\n", outp.c_str());
    return fail ? 1 : 0;
}
