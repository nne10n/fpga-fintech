# 高意 EDFA 面试口述提纲

来源：`coherent-edfa-primer.md` Q&A + 30 秒稿。数字只记有出处的；SKU/市占率不编。

## 30 秒开场（可背）

EDFA 用 980 nm 泵浦在掺铒光纤里直接放大 C/L 波段多波长信号，是长距和 DCI 的光层增益主力。高意不只卖放大器模块，更把自己的 980 nm 泵浦和微光学无源垂直做进去，产品从固定/可变增益、ROADM 阵列、拉曼混合，做到 FlexSOM 和 QSFP 形态的 POLS。面试里我讲两条线：放大器规格（增益、NF、功率、瞬态），以及可插拔化 + 自研泵浦；并分清公司名 Coherent/高意 与 coherent optics 技术词。

## 必答口述（Q1–Q10 压缩）

1. EDFA ≠ 相干模块：相干做调制/接收，EDFA 做光功率放大；高意两边都做。
2. 为何 AI/DCI 还谈 EDFA：机房内短距常不用；DCI/园区多波长相干仍要过损耗与插损；POLS 把 BA/PA 塞进 QSFP，免独立线路机架。
3. 竞争力三句：自研 980 nm 泵浦；自研微光学无源；形态覆盖到可插拔 POLS/FlexSOM。垂直整合 → 体积、功耗、定制速度。
4. Fixed vs Variable：增益块简单低功耗、模块内固定补偿；可变增益服务 ROADM/多跨段功率变化，要控制环与瞬态。
5. 瞬态：某波长上下线导致总功率跳变，反应慢会过冲/凹陷打到别的波长；ROADM 硬指标。
6. Arrayed：CDC-ROADM 多方向多端口同时放大、空间紧；多放大器进紧凑模块。
7. Hybrid Raman-EDFA：拉曼前置改善有效噪声与带宽，再接 VG EDFA；适合超长距，泵浦与激光安全更复杂。不背未公开的 NF 数。
8. POLS 硬数字（数据表）：满 C 约 1529–1567 nm；32 波 ×150 GHz；最大输出 21 dBm；BA NF ≤6.7 dB（@17 dB 增益）；成对 QSFP；面向 400G/800G ZR；新闻稿容量口径最高约 25.6 Tbps/纤对。
9. Mid-stage access：两级 EDFA 中间可插 DCM；说时区分「架构能力」和「某 SKU 是否引出端口」。MSA 在放大器语境说全称 Mid-Stage Access。
10. NF：每级加 ASE；NF 差 → OSNR 差 → 跨段/频谱效率吃亏。和输出功率、增益平坦度一起谈。

## 加分

- 泵浦制冷 → 非制冷微泵浦：可插拔功耗/空间紧，TEC 贵；非制冷是 FlexSOM/POLS 的器件前提。
- 反问面试官：贵司更偏板卡级 VG/Arrayed，还是可插拔 POLS？C/L 各占多少？要不要 MSA/DCM 联调？

## 红线

- 不编造未公开型号矩阵、NF、市占率。
- 公司名 Coherent/高意 ≠ coherent optics（相干光技术）。
