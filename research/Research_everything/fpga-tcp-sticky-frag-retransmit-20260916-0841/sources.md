# 出处清单与抓取备注

**调研目录：** `fpga-tcp-sticky-frag-retransmit-20260916-0841`  
**抓取时间：** Asia/Shanghai 2026-09-16 08:41  
**修订：** 第二轮提示词收紧（三层拆分、冻结对比维、交易 TX 默认）

---

## 主出处（report.md §12 扩展）

| ID | URL | 抓取状态 | 事实/推断/待核实 | 备注 |
|----|-----|----------|------------------|------|
| S1 | https://www.rfc-editor.org/rfc/rfc9293.html | ✅ 全文可读 | **事实** | TCP 现行标准；seq/ACK/去重/排序 |
| S1b | https://www.rfc-editor.org/info/rfc793 | ✅ 全文可读 | **事实** | 历史 TCP；与 9293 一致核心语义 |
| S2 | https://www.rfc-editor.org/rfc/rfc2018.html | ✅ 摘要+正文 | **事实** | SACK option、乱序块描述 |
| S3 | https://www.rfc-editor.org/rfc/rfc5681.html | ✅ 摘要 | **事实** | 拥塞控制、duplicate ACK 背景 |
| S4 | https://trea.com/information/data-flow-architecture-for-a-tcp-offload-engine/patentgrant/571f29aa-74dc-434c-91c0-55f568fe3e53 | ✅ 专利摘要 | **事实** | OOO handler method 500：drop past、OOO window、gap fill |
| S5 | https://dgway.com/products/IP/TOE100G-IP/TOExxG-PRES-XE.pdf | ✅ PDF 摘要页 | **事实** | Data reordering、duplicate trim、buffer 参数 |
| S6 | https://doi.org/10.1109/iscit.2011.6089757 | ⚠️ 摘要页 | **事实**（摘要级） | 多连接 FPGA reorder；175 MHz **事实**（摘要） |
| S7 | https://pmc.ncbi.nlm.nih.gov/articles/PMC9865474/ | ✅ 全文 | **事实** | shift-register pipeline OOO；外存+指针 |
| S7b | https://uh-ir.tdl.org/server/api/core/bitstreams/79b8a56e-8f79-45e5-ac2e-b7e7b543cb06/content | ✅ PDF | **事实** | 与 S7 同源论文 |
| S8 | https://doi.org/10.1109/jssc.2003.818294 | ⚠️ 摘要 | **事实**（摘要级） | Hoskote 10Gb TOE accelerator 架构 |
| S9 | https://docs.amd.com/r/en-US/pg051-10gig-eth | ⚠️ 索引页 | **待核实** | Xilinx 10G MAC；需按具体 TOE IP 核对 |
| S10 | https://www.intel.com/content/www/us/en/docs/programmable/683082/current/low-latency-ethernet.html | ⚠️ 索引页 | **待核实** | Intel LLE；集成边界因设计而异 |
| S11 | https://docs.kernel.org/networking/ip-sysctl.html | ✅ HTML | **事实** | 内核 TCP 行为 sysctl 对照 |
| S12 | Stevens, *TCP/IP Illustrated Vol.1* | 📚 书籍 | **事实** | 字节流抽象、segment vs 应用记录 |

---

## 次要 / 对比引用

| URL | 用途 | 标注 |
|-----|------|------|
| https://datatracker.ietf.org/doc/html/rfc9293 | S1 镜像 | **事实** |
| https://www.rfc-editor.org/rfc/rfc793.html | S1b 镜像 | **事实** |
| https://github.com/Xilinx/open-nic-ovs | SmartNIC 参考栈 | **待核实**（非 TCP 专论） |
| DPDK `rte_flow` / `net/i40e` 文档 | kernel bypass 对照 | **待核实** |

---

## 抓取限制说明

1. **IEEE Xplore** S6/S8 仅摘要；细节标 **待核实**，不写入未证实 cycle 数到选型硬指标。
2. **商用 TOE IP**（S5 等）Marketing 数字（80%/90% 线速）**不**作为本报告延迟结论（任务 Out）。
3. **FPGA 资源 LUT/BRAM** 为 report 内 **推断**，无实测 bench。
4. agent-tools 缓存为抓取中间文件，**不提交 git**。

---

## Bib 风格快捷引用

```bibtex
@rfc{rfc9293,
  title={Transmission Control Protocol (TCP)},
  author={Eddy, W.},
  year={2022},
  number={9293},
  publisher={RFC Editor}
}

@rfc{rfc2018,
  title={TCP Selective Acknowledgment Options},
  author={Mathis, M. and others},
  year={1996},
  number={2018}
}

@inproceedings{iscit2011reorder,
  title={High-performance FPGA implementation of packet reordering for multiple TCP connections},
  booktitle={ISCIT},
  year={2011},
  doi={10.1109/iscit.2011.6089757}
}

@article{fpgaReorder2023,
  title={Cost-Effective Network Reordering Using FPGA},
  journal={Electronics},
  year={2023},
  pmcid={PMC9865474}
}
```
