# 一页纸速览：AI 跑自动化测试验代码（收紧版）

**Asia/Shanghai 2026-09-17 09:40** · 目录 `ai-automated-test-verify-code-20260917-0940/`

## 禁止混写

不说「AI 自动测一下」，改说三阶段：**需求→断言** | **执行（CI/Agent 跑已有测）** | **判定（log/覆盖率/码测归因）**。

## 默认落地组合（推断，绑 S2,S3,S5）

| 层 | 做法 |
|----|------|
| **Oracle** | **契约/人工 acceptance 用例**（Agent 不可改） |
| **执行** | **CI** 跑全量；Agent 仅补测 scaffold、**失败分类** |
| **禁止** | 同模型 **自写实现+自写测+自签字** |
| **可选增强** | 独立 Test Agent / 交叉模型 / PBT / 变异抽检 / 差分 |
| **终裁** | 隐藏 CI 测 + **PR 人审** |

## 必须人审（推断）

- 首次 acceptance 测清单 sign-off  
- Agent 新增/修改 assertion（S7：<50% 对齐意图）  
- 仅 UI 位图 / 需求模糊 / 无第二实现  
- fix PR、支付/安全/合规路径  
- PBT 报告的 valid bug（S11：56% 基线）

## 循环证明（事实 S2）

同 AI 写码又写测 → 绿测 **≠** 符合需求。缓解：独立 oracle、角色分离、交叉模型、变异、人工门槛。

## 数字锚点（事实，禁编造）

| 指标 | 值 | 出处 |
|------|-----|------|
| 人写测 pass | 94.3% | S1 |
| 自生成测 pass | 68.0% | S1 |
| 差测 vs 好测 | 57.3% vs 65.3% | S2 |
| LLM oracle 对齐预期 | <50% | S7 |

## 证据

- [`evidence/E5-who-verifies-what-matrix.md`](evidence/E5-who-verifies-what-matrix.md)  
- [`evidence/E2-execcritic-false-confidence.md`](evidence/E2-execcritic-false-confidence.md)  
- [`sources.md`](sources.md) S1–S18
