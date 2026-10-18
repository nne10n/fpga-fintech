/**
 * Verilator harness: SV cnn_engine ↔ vectors/*.golden.bin (0-bit)
 * Usage: obj_dir/Vcnn_engine <impl-glm53-root>
 */
#include "Vcnn_engine.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <chrono>

static vluint64_t main_time = 0;
double sc_time_stamp() { return (double)main_time; }

static void tick(Vcnn_engine *dut) {
  dut->clk = 0;
  dut->eval();
  ++main_time;
  dut->clk = 1;
  dut->eval();
  ++main_time;
}

static std::string joinp(const std::string &a, const std::string &b) {
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
  f.read(reinterpret_cast<char *>(out.data()), (std::streamsize)sz);
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

static void reset_dut(Vcnn_engine *dut) {
  dut->rst_n = 0;
  dut->eng_en = 0;
  dut->weight_ok = 0;
  dut->s_axis_tvalid = 0;
  dut->s_axis_tlast = 0;
  dut->s_axis_tdata = 0;
  dut->m_axis_tready = 1;
  dut->wgt_we = 0;
  dut->wgt_re = 0;
  dut->wgt_waddr = 0;
  dut->wgt_wdata = 0;
  dut->wgt_raddr = 0;
  for (int i = 0; i < 5; i++) tick(dut);
  dut->rst_n = 1;
  for (int i = 0; i < 5; i++) tick(dut);
}

static void load_weights(Vcnn_engine *dut, const std::vector<int16_t> &w) {
  for (size_t i = 0; i < w.size(); i++) {
    dut->wgt_we = 1;
    dut->wgt_waddr = (uint16_t)i;
    dut->wgt_wdata = (uint16_t)(uint16_t)w[i];
    tick(dut);
  }
  dut->wgt_we = 0;
  dut->weight_ok = 1;
  tick(dut);
}

static bool run_window(Vcnn_engine *dut, const std::vector<int16_t> &win,
                       int16_t scores_out[10], uint32_t *cyc_out) {
  const int WIN = 2048;
  const int NCLASS = 10;
  int wr = 0;
  int rd = 0;
  int timeout = WIN * 8 + 2000000; // synthesizable schedule ~17k cyc/win

  dut->eng_en = 1;
  dut->m_axis_tready = 1;
  dut->s_axis_tvalid = 0;
  dut->s_axis_tlast = 0;
  // Allow registered ready to assert before first beat
  tick(dut);

  while (timeout-- > 0) {
    // Registered ready: sample BEFORE posedge (value DUT will use this cycle)
    const int ready_now = dut->s_axis_tready ? 1 : 0;

    if (wr < WIN) {
      dut->s_axis_tdata = (uint16_t)win[wr];
      dut->s_axis_tvalid = 1;
      dut->s_axis_tlast = (wr == WIN - 1) ? 1 : 0;
    } else {
      dut->s_axis_tvalid = 0;
      dut->s_axis_tlast = 0;
    }

    const int valid_now = dut->s_axis_tvalid ? 1 : 0;
    tick(dut);

    if (valid_now && ready_now) {
      wr++;
    }

    if (dut->m_axis_tvalid && dut->m_axis_tready) {
      if (rd < NCLASS) scores_out[rd] = (int16_t)dut->m_axis_tdata;
      bool last = dut->m_axis_tlast;
      rd++;
      if (last) {
        *cyc_out = dut->cyc_cnt;
        dut->eng_en = 0;
        dut->s_axis_tvalid = 0;
        for (int i = 0; i < 4; i++) tick(dut);
        return rd == NCLASS;
      }
    }
  }
  std::fprintf(stderr, "TIMEOUT wr=%d rd=%d busy=%d state-ish done=%d\n",
               wr, rd, (int)dut->busy, (int)dut->done);
  return false;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  std::string root = argc >= 2 ? argv[1] : ".";
  std::string vecdir = joinp(root, "vectors");
  std::string reportdir = joinp(root, "reports");

  std::vector<int16_t> weights;
  if (!load_i16(joinp(vecdir, "weights.bin"), weights, 11504)) {
    std::fprintf(stderr, "FAIL: load weights.bin\n");
    return 2;
  }

  std::ifstream mf(joinp(vecdir, "manifest.json"));
  if (!mf) { std::fprintf(stderr, "FAIL: manifest\n"); return 2; }
  std::stringstream ss; ss << mf.rdbuf();
  auto ids = parse_ids(ss.str());
  if (ids.size() < 32) {
    std::fprintf(stderr, "FAIL: need >=32 cases, got %zu\n", ids.size());
    return 2;
  }

  Vcnn_engine *dut = new Vcnn_engine;
  reset_dut(dut);
  load_weights(dut, weights);

  int pass = 0, fail = 0;
  std::vector<std::string> fail_ids;
  std::ostringstream report;
  report << "# Bit-exact result (impl-glm53) — SV cnn_engine (Verilator) ↔ golden\n\n";
  report << "| Field | Value |\n| --- | --- |\n";
  report << "| DUT | `rtl/cnn_engine.sv` (synthesizable FSM+PE, Verilator) |\n";
  report << "| PE | PE_M=16, PE_K_UNROLL=8 |\n";
  report << "| Behavioral ref | `_behavioral/cnn_engine.sv` (not DUT) |\n";
  report << "| Golden | `vectors/*.golden.bin` (`tb/golden_cnn`) |\n";
  report << "| Simulator | Verilator |\n";
  report << "| Tolerance | **0-bit** |\n";
  report << "| Vectors | " << ids.size() << " |\n";
  report << "| Weight words | " << weights.size() << " |\n\n";
  report << "## Cases\n\n";
  report << "| ID | Result | golden[0..9] | DUT[0..9] | cyc |\n| --- | --- | --- | --- | --- |\n";

  auto t0 = std::chrono::steady_clock::now();
  for (const auto &id : ids) {
    std::vector<int16_t> win, golden;
    if (!load_i16(joinp(vecdir, id + ".bin"), win, 2048)) {
      fail++; fail_ids.push_back(id + ":load_in");
      report << "| " << id << " | FAIL load input | | | |\n";
      continue;
    }
    if (!load_i16(joinp(vecdir, id + ".golden.bin"), golden, 10)) {
      fail++; fail_ids.push_back(id + ":load_golden");
      report << "| " << id << " | FAIL load golden | | | |\n";
      continue;
    }

    dut->weight_ok = 1;
    dut->eng_en = 0;
    for (int i = 0; i < 3; i++) tick(dut);

    int16_t dut_scores[10] = {};
    uint32_t cyc = 0;
    bool ok_run = run_window(dut, win, dut_scores, &cyc);
    bool ok = ok_run;
    if (ok) {
      for (int i = 0; i < 10; i++)
        if (dut_scores[i] != golden[i]) ok = false;
    }

    report << "| " << id << " | " << (ok ? "PASS" : (ok_run ? "FAIL" : "TIMEOUT")) << " |";
    for (int i = 0; i < 10; i++) report << " " << golden[i];
    report << " |";
    for (int i = 0; i < 10; i++) report << " " << dut_scores[i];
    report << " | " << cyc << " |\n";

    if (ok) pass++;
    else { fail++; fail_ids.push_back(id); }

    dut->eng_en = 0;
    for (int i = 0; i < 5; i++) tick(dut);
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
  report << "- Wall time: " << ms << " ms (Asia/Shanghai)\n";
  report << "- Evidence: Verilator sim of SV DUT vs independent golden bins.\n";

  {
    std::ofstream of(joinp(reportdir, "bitexact_result_sv.md"));
    of << report.str();
  }
  {
    std::ofstream of(joinp(reportdir, "bitexact_result.md"));
    of << report.str();
  }
  std::printf("%s", report.str().c_str());

  dut->final();
  delete dut;
  return fail ? 1 : 0;
}
