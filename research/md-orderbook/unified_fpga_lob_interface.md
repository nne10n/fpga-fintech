# 沪深逐笔行情 FPGA 订单簿：统一硬件接口语义设计

版本 v0.1（2026-09）。基于公开资料调研（深交所官方规范 Ver1.17、上交所 LDDS 竞价 Level-2 说明书 2.0.10、开源 FPGA/软件订单簿实现），给出深圳、上海两所逐笔行情在**同一套 FPGA 订单簿引擎**上的归一化输入接口语义。所有协议事实均标注来源；无法确认之处显式标记，见 §7。

---

## 0. 范围与目标

- **输入**：深交所 Binary 行情（逐笔委托 300192 / 逐笔成交 300191）与上交所 LDDS 竞价 Level-2 逐笔合并（UA5803）。
- **输出接口**：一套与交易所无关的定长归一化事件流（AXI-Stream），供硬件订单簿引擎消费。
- **不在范围**：期权（深 205x 频道）、债券 L2（上交所另有债券分册、深 206x/207x）、盘后定价（上交所 UA3209）、大宗交易。接口预留扩展位。
- **设计目标**：适配器吸收全部协议差异；订单簿引擎只消费统一事件，不感知交易所；关键更新路径（撤单/成交）O(1)、无数据搬移。

---

## 1. 调研结论速览

### 1.1 两所现行逐笔协议

| 维度 | 深交所 | 上交所 |
|---|---|---|
| 规范 | 《深圳证券交易所 Binary 行情数据接口规范》Ver1.17（2025-03） | 《LDDS系统竞价Level-2行情接口说明书》2.0.10（2024-07-01） |
| 逐笔消息 | 逐笔委托 300192、逐笔成交 300191（两条分离流） | **UA5803 竞价逐笔合并**（委托/成交/产品状态单流，Type=A/D/S/T） |
| 已下线/废弃 | — | UA5801（逐笔委托）、UA3201（逐笔成交）于 2024-07-01 下线；2023-11 合并流上线 |
| 传输 | TCP（现场/网络版）+ 组播 MDDP | TCP（VDE 实时端口 + 重建端口） |
| 编码 | 二进制定长字段，**大端** | FAST 1.1 内嵌 STEP（tag95/96），操作符 copy/increment/default，**大端** |
| 帧校验 | MsgType u32 + BodyLen u32 头 + 尾 CheckSum（字节累加 mod 256） | STEP/Binary 会话头 24B + 尾 CheckSum（字节累加） |
| 恢复机制 | 重传请求 390094（ChannelNo + 起止 ApplSeqNum），快照不支持重传 | UA1201 回补（tag10075=3，通道 + 起止 BizIndex，≤1000 条/批），快照不支持回补 |
| 来源 | [官方规范 PDF](http://www.szse.cn/marketServices/technicalservice/interface/P020250328368568358456.pdf) | [官方说明书 PDF](https://www.sseinfo.com/services/assortment/document/interface/c/10759998/files/f3ca62e905764efaa3983a7c20d9e1d9.pdf) |

### 1.2 版本时间线（影响选型）

- 深交所：规范谱系 0.10(2013)→1.17(2025)；2023-06-05 第五代交易系统切换**未更换行情协议**（当月 1.13 仅增加基金净值消息）。开源资料里的 "V5/SZSE binary" 即本协议。
- 上交所：2.0.4(2021-04) 新增逐笔委托 UA5801 与 BizIndex → 2.0.8/2.0.9 引入 UA5803 → 2.0.10(2024-07-01) **分离式下线，合并流成为唯一逐笔源**。注意：GitHub 上 AXOrderBook 等项目的上交所结构体基于已下线的 UA5801/UA3201，移植到 UA5803 需按 §5.2 调整。

---

## 2. 逐笔消息字段对照（线上原始格式）

### 2.1 深交所

逐笔委托 **300192**（来源：官方规范表 4-14-1；[szse_v5_parser 摘录](https://github.com/yzcpleo/szse_v5_parser)）：

| 字段 | 类型 | 语义 |
|---|---|---|
| ChannelNo | uInt16 | 频道号，逐笔为 201x~205x（股票/基金/转债/权证/期权，x=0-9） |
| ApplSeqNum | Int64 | 消息记录号，**同一频道内逐笔委托与逐笔成交共用、从 1 连续递增** |
| MDStreamID | char[3] | "011"=现货集中竞价 |
| SecurityID / SecurityIDSource | char[8]/char[4] | 证券代码 / "102" |
| Price | Int64 | 委托价，定点 **×10⁴**（186400=18.6400）；**市价单价格无效（0）** |
| OrderQty | Int64 | 委托数量，**原始申报数量**（股票股/基金份/转债张） |
| Side | char[1] | '1'=买，'2'=卖，G=借入，F=出借 |
| TransactTime | Int64 | YYYYMMDDHHMMSSsss（毫秒） |
| OrdType | char[1] | 1=市价，2=限价，U=本方最优（不细分市价单子类） |

逐笔成交 **300191**：

| 字段 | 类型 | 语义 |
|---|---|---|
| ChannelNo / ApplSeqNum / MDStreamID / SecurityID / SecurityIDSource | 同上 | ApplSeqNum 与委托流共用连续序号 |
| **BidApplSeqNum** | Int64 | 买方委托索引（= 对应逐笔委托的 ApplSeqNum），**0=无对应委托** |
| **OfferApplSeqNum** | Int64 | 卖方委托索引，0=无对应委托 |
| LastPx | Int64 | 成交价 ×10⁴；**撤单记录为 0** |
| LastQty | Int64 | 成交数量；**撤单记录 = 被撤销的剩余委托量** |
| **ExecType** | char[1] | **'F'=成交，'4'=撤销** |
| TransactTime | Int64 | 同上 |

**深交所撤单语义（关键）**：撤单记录藏在**逐笔成交流**中，ExecType='4'；**被撤委托号放在 Bid/OfferApplSeqNum 中非 0 的一侧**（另一侧为 0），LastPx=0，LastQty=被撤数量，撤单价格需回查逐笔委托。官方协议中**无**主买/主卖字段（TradeBSFlag 是数据商落地数据私有扩展；社区以"委托号较大一侧为主动方"推导，非官方语义）。

### 2.2 上交所（现行 UA5803，来源：官方说明书表 4-14）

| Tag | 域名 | FAST 操作符 | 语义 |
|---|---|---|---|
| 10021 | **BizIndex** | **Increment** | 逐笔序号，**从 1 起按通道连续**（委托+成交+状态统一编号） |
| 10115 | Channel | Copy | 通道号（同一证券固定一个通道，逐日可能变化；总数未公开） |
| 48 | SecurityID | Copy | 证券代码 |
| 10013 | TickTime | Copy | HHMMSScc，**百分之一秒（10ms 精度）** |
| 10022 | **Type** | Copy | **A=新增委托；D=删除委托（撤单）；S=产品状态；T=成交** |
| 10023 / 10024 | BuyOrderNO / SellOrderNO | Default | 买/卖方订单号（64b；与方向不符的一侧无意义） |
| 44 | Price | Default | 价格（元，**3 位小数**）；S、D 类无意义 |
| 39 | Qty | Default | 数量（3 位小数）；S 类无意义 |
| 10016 | TradeMoney | Default | **Type=A 时=该委托已成交数量；Type=T 时=成交金额（5 位小数）**；其余无意义 |
| 10192 | TickBSFlag | Default | A/D：B=买，S=卖；S：START/OCALL/TRADE/SUSP/CCALL/CLOSE/ENDTR；T：**B=外盘主动买，S=内盘主动卖，N=未知** |

**上交所关键发布规则（官方原文，重建逻辑必读）**：

1. 新增委托**仅在首次撮合后发布**——从未成交过的委托不发布，逐笔委托簿系统性小于真实簿。
2. 连续竞价阶段委托的 Qty 为**撮合后剩余数量**（绝对量）；集合竞价/停牌阶段补发时为原始委托量（阶段内不实时发布）。
3. 同一笔委托的主动成交与剩余委托：**先发成交（T），再发剩余委托（A）**。
4. 集合竞价/停牌结束统一补发，顺序：**委托(A) → 成交(T) → 产品状态(S)**。
5. 撤单 = 逐笔委托流中 Type='D' 的消息（与深交所相反）。D 消息中 Qty 的精确语义官方未单独定义（见 §7）。
6. UA5815（通道空闲时发布该通道当前最大 BizIndex）可作通道末端水位确认。

---

## 3. 关键语义差异及对订单簿构建的影响

| # | 差异 | 深交所 | 上交所 | 对引擎的影响 |
|---|---|---|---|---|
| 1 | **撤单位置** | 逐笔成交流，ExecType='4'，引用号在 Bid/OfferApplSeqNum 非 0 侧 | 逐笔委托流，Type='D' | 归一化后同为 CANCEL(order_ref)，适配器负责归位 |
| 2 | **委托发布时机** | 先发布、后撮合；OrderQty=原始量 | **首次撮合后才发布**；Qty=剩余量（绝对） | NEW 事件需携带 qty_abs 标志（增量 vs 绝对 upsert），见 §4.3 |
| 3 | **成交归因** | BidApplSeqNum/OfferApplSeqNum（0=无） | BuyOrderNO/SellOrderNO | **两所都可精确归因**，订单簿无需价格-时间撮合推断；先成交后发布的引用走 shadow 条目（§4.3） |
| 4 | 价格刻度 | ×10⁴（4 位小数） | ×10³（3 位小数） | 内部统一 ×10⁴ 定点，SH 适配器 ×10 |
| 5 | 序号体系 | 每通道 ApplSeqNum 从 1 连续（委托+成交共序列） | 每通道 BizIndex 从 1 连续（统一序列） | 统一为每通道 seq32 连续检查，规则完全同构 |
| 6 | 时间精度 | 毫秒（17 位全时间戳） | 10ms（HHMMSScc） | 统一 ms-of-day；SH 粒度粗，细排序依赖本地到达时间 |
| 7 | 主买/主卖 | 线上无（数据商扩展） | TickBSFlag B/S/N | 归一化为 aggressor 字段，SH 透传、SZ 可选推导；**不影响建簿** |
| 8 | 集合竞价 | 竞价期间委托/撤单照常流入（实践）；竞价撮合成交是否逐笔发布未确认（§7） | 竞价期间**不发逐笔**，阶段末按 A→T→S 补发 | 统一 PHASE 事件 + 引擎语义天然兼容两所（SH 的补发顺序与 upsert/绝对量语义自洽） |
| 9 | 市价单 | OrdType='1'，Price=0 | 流内无类型字段（市价/限价不可区分） | price=0 或 MKT 的委托入表但不入深度，供撤单/成交引用对账 |
| 10 | 缺口恢复 | 390094 重传（范围式） | UA1201 回补（≤1000 条/批，短连接） | 统一 GAP→冻结→影子重建→换入，触发方式由主机侧差异处理 |

---

## 4. 统一接口语义设计（规范性内容）

### 4.1 设计决策记录

| 决策 | 内容 | 理由 |
|---|---|---|
| D1 | 归一化事件集收敛为 **NEW / CANCEL / TRADE / PHASE / SNAPSHOT / CTRL** 六类，32B 定长，AXI-Stream | 与公开实践一致（mbattyani 297b 命令流、HFTConsultancy 命令接口、yibo-hou 32B 事件）；ITCH 的最小完备事件集是单序号模型，沪深需加"成交双引用"维度 |
| D2 | 订单引用 = {channel(16b, 事件头), seq(32b, 载荷)} 复合 48b | SZ ApplSeqNum 与 SH OrderNO/BizIndex 线上均为 64b，但均为每通道从 1 计数；实测量级远小于 2³²（SH OrderNO 全日约千万级）。适配器校验 ≤0xFFFFFFFF，越界报 CTRL(ERROR) |
| D3 | NEW 语义 = **upsert**，携带 qty_abs 位：0=qty 为新增原始量（SZ），1=qty 为当前剩余绝对量（SH） | 差异 #2 的直接推论。SH "T 先于 A"与"首撮全成交不发布"两条规则用 upsert+绝对量即可无状态正确处理 |
| D4 | 成交按**双引用直接归因**，不做撮合推断；未知引用在 SH 下创建 shadow 条目、在 SZ 下计为异常 | SH 的成交先于剩余委托发布是官方规则，属正常路径；SZ 委托先于成交发布，引用应必然可解析 |
| D5 | 撤单以订单表为准整单移除；事件中携带的撤销量仅作校验 | SZ 撤单量为"被撤剩余量"（权威）；SH D 消息 Qty 语义未定义（§7）。表内余量是唯一可信量 |
| D6 | 价格统一 ×10⁻⁴ 元 u32 定点；数量统一申报单位（股/份/张）整数 u32 | SZ 透传、SH ×10；u32 价格上限 42.9 万元、数量上限 42.9 亿，均覆盖。深度聚合量 u32+8b |
| D7 | 恢复策略 = 影子重建（回补/重放） + 快照仅校验 | SH 快照不支持回补且逐笔簿系统性小于快照（未发布委托），快照不能作种子；SZ 快照虽可作十档种子但订单表无法从快照重建（快照无订单号），仍走同一路径保持单一逻辑 |
| D8 | 阶段（PHASE）双来源：SH 用 S 消息（逐符号），SZ 用快照 TradingPhaseCode（3s）+ 本地时钟表 | SZ 无产品状态逐笔消息；两者统一映射到同一阶段枚举 |
| D9 | 适配器吸收成帧差异（SZ 定长偏移解析；SH FAST PMAP/stop-bit/copy/increment 状态机），统一层与协议无关 | SZ 解析常数拍；SH FAST 有跨消息字典状态，是两所适配复杂度的主要不对称点 |

### 4.2 统一事件格式（32 字节定长）

事件头（字节 0–15，各事件共用）：

| 字节 | 字段 | 说明 |
|---|---|---|
| 0 | ev_type[2:0] + rsvd | 0=NEW，1=CANCEL，2=TRADE，3=PHASE，4=SNAPSHOT，5=CTRL，6=IDLE，7=ERROR |
| 1 | flags[7:0] | 事件类型专用（见下） |
| 2 | src_id | bit[1:0] 市场（0=SZ，1=SH）；bit[3:2] 接入线 A/B；bit[7] 补发（replay）标记 |
| 3 | rsvd | — |
| 4–9 | ts_local_ns (u48) | 本地到达时刻（纳秒，自日始） |
| 10–11 | channel (u16) | 通道号（经适配器映射后的内部通道 ID） |
| 12–13 | symbol (u16) | 内部证券索引（适配器用 CAM/哈希将 6 字符代码索引化；0xFFFF=无效/全局） |
| 14–15 | rsvd | — |

载荷（字节 16–31，按事件类型）：

**NEW**（新增/重发布委托）

| 字节 | 字段 | 说明 |
|---|---|---|
| 16–19 | order_seq (u32) | 订单引用低 32 位（复合 channel 构成 48b 订单号） |
| 20 | side[1:0] + qty_abs[2] + ordtype[4:3] | side: 0=买 1=卖；ordtype: 0=限价 1=市价 2=本方最优 3=其他 |
| 21–23 | rsvd | — |
| 24–27 | price (u32) | ×10⁻⁴ 元；市价单为 0 |
| 28–31 | qty (u32) | 申报单位；qty_abs=0 时为原始申报量，=1 时为当前剩余量 |
| （备选） | exch_ts_ms (u32) | 如需交易所时间可占用 21–24，见 §4.4 时间语义 |

**CANCEL**（整单撤销）

| 字节 | 字段 | 说明 |
|---|---|---|
| 16–19 | order_seq (u32) | 被撤订单引用 |
| 20 | side[1:0] + reason[3:2] | side 来自协议方向字段（SZ 取非 0 引用侧 / SH 取 TickBSFlag），仅作校验 |
| 21–23 | rsvd | — |
| 24–27 | cancel_qty (u32) | 事件携带的撤销量（SZ=被撤剩余量；SH 未定义，可为 0）；**仅供校验，不参与建簿** |
| 28–31 | exch_ts_ms (u32) | ms-of-day |

**TRADE**（成交，双引用）

| 字节 | 字段 | 说明 |
|---|---|---|
| 16–19 | buy_seq (u32) | 买方订单引用低 32 位；0=该侧无对应委托 |
| 20–23 | sell_seq (u32) | 卖方订单引用低 32 位；0=无 |
| 24–27 | price (u32) | 成交价 ×10⁻⁴ 元 |
| 28–31 | qty (u32) | 成交量（申报单位） |
| 头 flags | aggressor[1:0] + auction[2] + broken[3] | aggressor: 0=B 主动买 1=S 主动卖 2=N/未知；仅元数据 |

**PHASE**（交易阶段变更）

| 字节 | 字段 | 说明 |
|---|---|---|
| 16–19 | phase (u32) | 枚举：PRE / OPEN_CALL / CONT / CLOSE_CALL / HALT / CLOSE / POST / END |
| 20–23 | source + exch_ts_ms | 来源（S 消息 / 快照 / 本地时钟）；symbol=0xFFFF 表示全市场 |
| 24–31 | rsvd | — |

**SNAPSHOT / CTRL**：SNAPSHOT 走独立低优先级流（§4.6）；CTRL 承载 GAP、RESYNC、MISMATCH、ERROR 等控制语义（载荷含通道、期望序号区间、原因码）。

> 注：32B 打包中 TRADE 无独立 exch_ts（载荷已满）。两所逐笔自带时间精度仅 1ms/10ms，本地纳秒时间戳区分度更高，成交带（tape）消费方建议使用 ts_local_ns；如强需求可将事件加宽到 64B，字段语义不变。

### 4.3 引擎处理语义（规范性伪代码）

数据结构：每证券一个订单表（order_ref → {side, price, qty, state∈{VISIBLE, HIDDEN, SHADOW}}）与价格档位 ladder（每档聚合 qty、order_count、可选 FIFO 队列）。price=0 或市价单为 HIDDEN（入表不入深度）。

```
on NEW(e):                                   # upsert 语义
  ent = table.find(e.ref)
  if ent:                                    # 仅 SH 会发生（撮合后重发布）
    if !e.qty_abs: anomaly("dup-new"); return
    d = (i64)e.qty - (i64)ent.qty
    ent.qty = e.qty
    if ent.state != HIDDEN: depth[e.price].qty += d   # d 可为负
    if ent.qty == 0: table.remove(ent)（并从档位队列摘除）
  else:
    table.insert(e.ref, {side, price, qty: e.qty,
                         state: (e.price==0 || e.ordtype==MKT) ? HIDDEN : VISIBLE})
    if state==VISIBLE: depth[price].qty += qty; depth[price].count++; 队列入队

on CANCEL(e):
  ent = table.find(e.ref)
  if !ent:
    # SZ: 异常（委托必先发布）；SH: 被撤委托可能从未发布过，属预期
    count_anomaly(e.src==SZ ? HARD : SOFT); return
  if ent.state != HIDDEN: depth[ent.price].qty -= ent.qty; count--
  if e.cancel_qty != 0 && e.cancel_qty != ent.qty: count_mismatch()
  table.remove(ent)

on TRADE(e):
  for (ref, side) in {(e.buy_seq, BUY), (e.sell_seq, SELL)} 若 ref != 0:
    ent = table.find(ref)
    if !ent:
      if e.src == SH:                        # 官方规则：成交先于剩余委托发布
        table.insert(ref, {side, price:e.price, qty:0, state:SHADOW})
      else: count_anomaly(HARD)              # SZ 引用必须可解析
      continue                               # 不可见订单不扣深度
    if ent.qty >= e.qty: ent.qty -= e.qty
    else: count_anomaly(); ent.qty = 0       # 超扣钳位
    if ent.state != HIDDEN: depth[ent.price].qty -= e.qty
    if ent.qty == 0: table.remove(ent)
  tape.emit(e)

on PHASE(e): 更新阶段状态机；驱动 tape/快照比对窗口、竞价语义门控
```

要点说明：

1. **SH "T 先于 A"**：T 引用未发布订单 → 建 SHADOW 条目（qty=0，不动深度）→ 随后 A 以绝对量 upsert → 深度补上剩余量。全程无需记忆成交历史。
2. **SH "首撮全成交不发布"**：T 建 SHADOW 后无 A 到来，条目自然滞留为 0 量影子——需在日终/阶段边界清理，或以 LRU/容量压力淘汰。
3. **SZ 路径**：NEW 恒为插入、CANCEL/TRADE 引用恒可解析；凡不满足即硬异常（计数并上抛 CTRL），说明丢包或语义版本变化。
4. **深度不变式**：VISIBLE 订单集合的 (价格, 剩余量) 聚合 ≡ ladder。每个事件后聚合可增量维护；order_count 用于档位清空判断（参考 08-fpga-order-book 的 level entry 设计）。
5. **队列（可选特性）**：档位 FIFO 保存 order_ref 链，撤单/成交经订单表 O(1) 摘链。SZ 队列精确；SH 队列缺"未发布订单"，位置为下界。

### 4.4 标度、索引与时间

- **价格**：内部一律 ×10⁻⁴ 元 u32。SH 适配器 ×10（×10³→×10⁴）；SZ 透传。ladder 用每证券 tick（股票 0.01=100 单位，基金/转债 0.001=10 单位，来自静态配置）做直接寻址索引——中国市场 tick 固定 + ±10%（科创/创业 ±20%）涨跌停使价位空间有界，直接寻址优于哈希/CAM（FPL17 结论，[论文](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf)）。
- **数量**：申报单位整数。SH 线上 ×10³，须整除校验（非整除计异常）。
- **证券索引**：6 字符代码 → 16b 内部索引，哈希/CAM 集中在适配器；跨日通道-证券映射不持久（SH 同一证券当日通道固定、逐日可能变化），每日开盘由静态数据/首见事件重建。
- **时间**：ts_exch_ms = ms-of-day（SZ 由 17 位时间戳解析；SH 由 HHMMSScc 解析，精度 10ms）；ts_local_ns 由事件入口打点。跨通道合并不依赖时间戳（见 §4.5）。

### 4.5 序列完整性与缺口恢复

1. 每通道一个期望序号 `last_seq`；新事件 seq = last+1 → 通过；seq ≤ last → 重复，丢弃计数；seq > last+1 → **GAP**。
2. GAP 处理：置通道 STALLED → 上抛 CTRL(GAP, channel, [last+1, seq-1]) → 冻结该通道全部绑定证券的簿（停止输出、事件转入影子缓冲）→ 主机侧按所别触发回补（SZ 390094 范围重传；SH UA1201，≤1000 条/批，短连接重建端口）→ 补发事件置 replay 位、注入影子重建 → 追平后与冻结期实时流按序号归并、换入、解除冻结。
3. 跨通道合并：N 路通道各自保序，合并器不重排（两所均无跨通道全序），按到达序输出；通道间仅做水位对账（UA5815 / SZ 频道心跳 390095 提供通道末端序号）。
4. 双路冗余（可选）：两所对客户端均为单路 TCP（非 MOLDUDP64 式同内容组播），A/B 择优应在**解码归一之后**按 (channel, seq) 做有界窗口首到者优先（HotI'09 位图窗口法），D4 语义不受影响。

### 4.6 快照校验语义

SNAPSHOT 事件流（独立端口）承载每证券：阶段码、十档 {price, qty, order_count}、买卖委托总量与加权均价（SZ x3/x4；SH 10039/10040/10043/10044）、成交笔数/总量/总金额、**SH 撤单统计（10184–10189 买入/卖出撤单笔数、数量、金额）**。

- **SZ**：逐笔簿十档与快照逐档比对，容差 = 快照周期内的漂移（3s）；偏差超阈 → CTRL(MISMATCH)。
- **SH**：逐笔簿系统性 ≤ 快照（未发布委托），比对语义为"逐笔簿 ≤ 快照总量且差值随时间收敛"显著偏离才告警；撤单笔数/数量累计可与 CANCEL 计数对账。
- 快照**不用于**建簿种子或恢复（D7），仅校验与监控。

---

## 5. 适配器映射规范

### 5.1 深交所适配器（SZSE Binary Ver1.17）

| 线上 | 条件 | 统一事件 |
|---|---|---|
| 300192 | — | NEW{seq=ApplSeqNum, side: '1'→BUY/'2'→SELL, price(透传×10⁴), qty, qty_abs=0, ordtype: '2'→LMT/'1'→MKT/'U'→MBEST}；Side G/F（融资融券借贷）按配置过滤或映射 |
| 300191 | ExecType='F' | TRADE{buy_seq=BidApplSeqNum, sell_seq=OfferApplSeqNum, price=LastPx, qty=LastQty, aggressor=可选推导} |
| 300191 | ExecType='4' | CANCEL{seq=非 0 一侧引用, side=该侧, cancel_qty=LastQty} |
| 300111 | 快照 | SNAPSHOT 流 |
| 390094/390095 | 重传/心跳 | CTRL/IDLE |

成帧：大端；头 {MsgType u32, BodyLength u32} + 体 + CheckSum（字节累加 mod 256）；定长偏移解析，无跨消息状态。

### 5.2 上交所适配器（LDDS 竞价 L2 2.0.10，UA5803）

| 线上 | 条件 | 统一事件 |
|---|---|---|
| Type='A' | — | NEW{seq=BizIndex, ref=BuyOrderNO(买)/SellOrderNO(卖) 按 TickBSFlag, side=TickBSFlag, price=Price×10, qty=Qty÷10³, **qty_abs=1**, ordtype=3(未知)}；TradeMoney(已成交量)记入校验账 |
| Type='D' | — | CANCEL{seq=BizIndex, ref=方向侧订单号, cancel_qty=0(语义未定义)} |
| Type='T' | — | TRADE{seq=BizIndex, buy_seq=BuyOrderNO, sell_seq=SellOrderNO, price=Price×10, qty=Qty÷10³, aggressor=TickBSFlag(B/S/N)} |
| Type='S' | — | PHASE{symbol=本消息证券, phase: START/OCALL/TRADE/SUSP/CCALL/CLOSE/ENDTR} |
| UA5815 | — | CTRL(CHANNEL_WATERMARK) |

成帧：TCP 字节流 → STEP 剥壳（SOH 分隔，取第二个 tag95 为 FAST 长度、tag96 为 FAST 数据）→ FAST 1.1 解码（PMAP、stop-bit、模板 5803 的 Copy/Increment/Default 字典状态；BizIndex 线上为增量，解码即 prev+delta）。价格 ×10³→×10⁴、数量 ÷10³ 需整除校验。PMap/字典状态使 SH 适配器存在跨消息依赖——不可对单消息独立重放，回补注入时须与实时流共用同一解码器实例或按通道分段重建。

---

## 6. 存储与位宽预算（参考公开数据）

| 部件 | 方案 | 参考点 |
|---|---|---|
| 订单表 | order_ref 48b → 4 路组相联哈希 → 条目 {symbol 16b, price 25-32b, qty 30-32b, side 1b, state 2b, 队列指针}，URAM/HBM | yibo-hou 4 路组相联（Artix-7）；AXOrderBook 16B 订单结构 + HBM 分区（读 120–150ns） |
| 价格 ladder | 每证券直接寻址数组（tick×涨跌停有界）+ top-N 档 BRAM 缓存；档位条目含聚合 qty(u40) + order_count(u16) | FPL17（132–288ns/update，CFFEX 数据，结论适用于沪深）；CN108269188A 分层缓存 |
| 逐笔解析 | SZ 定长偏移常数拍；SH FAST 状态机；参考实现末字节→命令 8 拍 @322MHz ≈ 25ns | mbattyani sub-25ns ITCH parser |
| 撤单路径 | 必须 O(1) 无搬移（约 95% 消息为随机位置撤单） | arXiv 2606.01183 |

量级估算（每市场）：证券 ≤8K（16b 索引）；全日逐笔消息 深市数千万级/日、通道内峰值约 10⁵ msg/s 量级；并发活跃订单峰值 10⁶ 量级 → 订单表 24–64MB（HBM/URAM 混合），活跃档位表与 top-10 档 BRAM 常驻。

---

## 7. 待实测确认清单（开放问题）

1. **SH 'D' 消息 Qty 语义**（撤单后剩余量 vs 本次撤销量）——官方未单独定义；本设计不依赖该字段（D5），实测仅用于校验策略。
2. **SZ 集合竞价撮合成交**是否以带 Bid/OfferApplSeqNum 的逐笔成交发布（9:25/15:00）——官方无明文，开源实现存在分歧；影响竞价成交是否可归因（引擎语义两者都兼容）。
3. **SH 市价单在流中的 Price 值**（0？转换后限价？）——L2 流无类型字段，需实测；price=0 策略已兜底。
4. **通道总数**：SZ 集中竞价逐笔 2010–2019 实际使用数、SH 通道取值范围——官方"在使用指南中发布"但指南未公开；实现按 u16 通道空间全量配置，不做数量假设。
5. **SH OrderNO 分配规则与 32b 上限**——官方未公开（属撮合平台 IS101 范畴）；按日校验 max(OrderNO) < 2³²。
6. **SH UA5803 'A' 消息 Qty 是否沿用 2.0.8 注 3 的"剩余量"语义**——2.0.10 未复述，倾向沿用；以对账验证。
7. SZ OrderQty 对可转债的申报单位（张/张×10）与基金（份）的统一折算——由静态配置承载。
8. SZ 除权除息日逐笔口径、停牌期逐笔静默的确切行为——官方未规定，以快照 TradingPhaseCode 门控。

---

## 8. 参考资料来源

**深交所（官方）**
- 《深圳证券交易所 Binary 行情数据接口规范》Ver1.17（2025-03）：http://www.szse.cn/marketServices/technicalservice/interface/P020250328368568358456.pdf （STEP 版同页；接口目录：http://www.szse.cn/marketServices/technicalservice/interface/index.html）
- MDDP 组播行情数据分发协议 Ver1.01：http://www.szse.cn/marketServices/technicalservice/interface/P020250219508489616817.pdf
- 英文版 5th Trading System Binary Feed 规范（Ver1.10/1.11 镜像）：http://www.szsi.cn/cpfw/overseas/market/technical/

**上交所（官方）**
- 《LDDS系统竞价Level-2行情接口说明书》2.0.10（2024-07-01）：https://www.sseinfo.com/services/assortment/document/interface/c/10759998/files/f3ca62e905764efaa3983a7c20d9e1d9.pdf
- 《LDDS系统接口说明书（基础分册）》1.1.5：https://www.sseinfo.com/services/assortment/document/interface/c/10759673/files/28f7e7b73ab24a1d972f9a78f628380c.pdf
- 上证信息服务文档索引：https://www.sseinfo.com/services/assortment/document/
- MDGW（Level-1，IS120 STEP 卷 0.612）：https://www.sse.com.cn/services/tradingtech/development/c/10816478/files/51a3e4c6b92345689c682448582c019d.pdf

**开源实现**
- 深交所 V5 行情解析库（C++，字段与官方一致）：https://github.com/yzcpleo/szse_v5_parser
- AXOrderBook（A 股逐笔订单簿，Python 模型 + HLS；上交所结构基于已下线 UA5801/UA3201）：https://github.com/LyricalBernardin/AXOrderBook （fork: https://github.com/cosmo86/forked_AXOrderBook）
- sub-25ns ITCH FPGA parser（NovaSparks）：https://github.com/mbattyani/sub-25-ns-nasdaq-itch-fpga-parser
- fpga-limit-order-book（SystemVerilog，32B 事件 + 组相联哈希）：https://github.com/yibo-hou/fpga-limit-order-book
- 08-fpga-order-book（VHDL/ITCH）：https://github.com/adilsondias-engineer/08-fpga-order-book
- Order-Book-FPGA（PITCH 归一化命令接口）：https://github.com/HFTConsultancy/Order-Book-FPGA
- ITCH 5.0 规范：https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHSpecification.pdf

**论文与专利**
- He, Fu, Luk 等, "Exploring the Potential of Reconfigurable Platforms for Order Book Update", FPL 2017（tick 直接寻址 + top-N 缓存）：https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf
- Morris 等, "FPGA Accelerated Low-Latency Market Data Feed Processing", HotI 2009（A/B 有界窗口仲裁）：https://www.doc.ic.ac.uk/~wl/papers/09/hoti09dt.pdf
- "The World's Fastest Matching Engine Algorithm", arXiv 2606.01183（撤单 O(1) 论证）：https://arxiv.org/html/2606.01183v1
- CN108269188A《一种基于FPGA的交易所行情信息处理方法和系统》（分层缓存参照）：https://patents.google.com/patent/CN108269188A/zh

**语义参照（软件侧）**
- DolphinDB 订单簿快照引擎教程（沪深逐笔语义与解析实例）：https://docs.dolphindb.cn/zh/tutorials/orderBookSnapshotEngine.html 、https://docs.dolphindb.cn/zh/tutorials/l2_stk_data_proc_2.html
- LOB-Reconstruction（深交所逐笔重建，集合竞价阶段处理）：https://github.com/Agnes252/LOB-Reconstruction
- 上交所逐笔重建原理（知乎，撤单在委托流）：https://zhuanlan.zhihu.com/p/649400934
- FAST 协议源码级分析（kuangtu/fixfast）与 MDGW 会话实现（kuangtu/ssemdgw）：https://github.com/kuangtu/fixfast 、https://github.com/kuangtu/ssemdgw
