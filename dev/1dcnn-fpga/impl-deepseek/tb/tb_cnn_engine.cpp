#include <verilated.h>
#include "Vtb_cnn_engine_wrap.h"
#include <fstream>
#include <vector>
#include <string>
#include <cstdio>
#include <cstdint>

static bool read_csv(const std::string& p, std::vector<int16_t>& o) {
    std::ifstream ifs(p); if (!ifs) return false;
    std::string line; if (!getline(ifs, line)) return false;
    o.clear(); size_t pos=0;
    while (pos < line.size()) {
        size_t c = line.find(',', pos);
        std::string t = line.substr(pos, c==std::string::npos?std::string::npos:c-pos);
        if (!t.empty()) o.push_back((int16_t)strtol(t.c_str(), nullptr, 10));
        if (c==std::string::npos) break; pos=c+1;
    }
    return !o.empty();
}
static void tick(Vtb_cnn_engine_wrap* top) {
    top->sys_clk = 1; top->eval();
    top->sys_clk = 0; top->eval();
}
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string root = argc>=2 ? argv[1] : ".";
    int max_cases = argc>=3 ? atoi(argv[2]) : 1;
    auto* top = new Vtb_cnn_engine_wrap;
    top->sys_clk=0; top->sys_rst_n=0; top->eval();
    for (int i=0;i<4;i++) tick(top);
    top->sys_rst_n=1; tick(top);

    FILE* f = fopen((root+"/vectors/weights_synthetic.bin").c_str(),"rb");
    if (!f) { fprintf(stderr,"no weights\n"); return 2; }
    int16_t w; int n=0;
    top->load_en=1; tick(top); top->load_en=0;
    while (fread(&w,2,1,f)==1) {
        top->wr_data=w; top->wr_en=1; tick(top); top->wr_en=0; n++;
    }
    fclose(f);
    fprintf(stderr, "loaded %d ok=%d\n", n, top->weight_ok);

    int pass=0, fail=0;
    for (int ci=0; ci<max_cases; ++ci) {
        char id[16]; snprintf(id,sizeof(id),"v%02d",ci);
        std::vector<int16_t> in, gold, got;
        if (!read_csv(root+"/vectors/cases/"+std::string(id)+"_in.csv", in)) break;
        if (!read_csv(root+"/vectors/cases/"+std::string(id)+"_score.csv", gold)) { fail++; continue; }

        top->eng_en=1; top->m_tready=1;
        int fires=0;
        for (size_t i=0;i<in.size();++i) {
            top->s_tdata=in[i]; top->s_tvalid=1; top->s_tlast=(i+1==in.size());
            for (int spin=0; spin<100000; ++spin) {
                int ready = top->s_tready;
                tick(top);
                if (ready) { fires++; break; }
            }
        }
        top->s_tvalid=0; top->s_tlast=0;
        fprintf(stderr, "%s fires=%d feat0[0]=%d cs=%d ms=%d\n", id, fires, (int16_t)top->dbg_feat0_0, top->dbg_cs, top->dbg_ms);

        got.clear();
        for (int spin=0; spin<8000000 && (int)got.size()<10; ++spin) {
            if (top->m_tvalid) got.push_back((int16_t)top->m_tdata);
            tick(top);
            if ((spin % 500000)==0)
                fprintf(stderr, "  spin=%d cs=%d ms=%d feat1_0=%d score0=%d cyc=%u\n",
                    spin, top->dbg_cs, top->dbg_ms, (int16_t)top->dbg_feat1_0, (int16_t)top->dbg_score0, top->cyc_cnt);
        }
        bool ok = got.size()==10;
        for (int k=0;k<10 && ok;k++) if (got[k]!=gold[k]) ok=false;
        if (ok) { printf("%s PASS cyc=%u\n", id, top->cyc_cnt); pass++; }
        else {
            printf("%s FAIL got=", id);
            for (size_t k=0;k<got.size();k++) printf("%d%s", got[k], k+1==got.size()?"":",");
            printf(" gold=");
            for (size_t k=0;k<gold.size() && k<10;k++) printf("%d%s", gold[k], k+1==gold.size()||k==9?"":",");
            printf(" cyc=%u score0_reg=%d\n", top->cyc_cnt, (int16_t)top->dbg_score0);
            fail++;
        }
        top->eng_en=0;
        for (int i=0;i<20;i++) tick(top);
        // isolate cases
        top->sys_rst_n=0; for (int i=0;i<4;i++) tick(top); top->sys_rst_n=1; tick(top);
        // reload weights after reset (weight_mem clears ok)
        FILE* f2 = fopen((root+"/vectors/weights_synthetic.bin").c_str(),"rb");
        int16_t ww; top->load_en=1; tick(top); top->load_en=0;
        while (f2 && fread(&ww,2,1,f2)==1) { top->wr_data=ww; top->wr_en=1; tick(top); top->wr_en=0; }
        if (f2) fclose(f2);
    }
    printf("SUMMARY pass=%d fail=%d\n", pass, fail);
    top->final(); delete top;
    return fail?1:0;
}
