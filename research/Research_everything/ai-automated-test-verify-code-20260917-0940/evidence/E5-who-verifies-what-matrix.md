# E5：「谁在验证什么」分解矩阵

- **标注：** 推断（本报告框架）；各格机制断言绑 S1–S5,S15
- **用途：** 禁止混写「AI 自动测一下」；供 report §3 审计

## 三阶段 × 执行者

| 阶段 | 输入 | 输出 | 典型执行者 | 留证物 | 出处 |
|------|------|------|------------|--------|------|
| **A. 需求→断言** | AC/OpenAPI/issue/CSR 表 | 可执行 assertion / 性质 / 差分输入 | 人 / 独立 Test Agent / LLM（需 qualify） | 测源文件 diff、契约版本号 | S3,S1,S16 |
| **B. 测试执行** | 测 + 被测实现 | exit code、stdout/stderr、JUnit XML、VCD | **CI runner** / Agent Shell / `make sim` | 日志路径、artifact URL、退出码 | S3,S4,S15 |
| **C. 结果判定** | 执行输出 | pass/fail 分类、码错/测错归因、覆盖率 | Harness 规则 + **可选** AI 分类 + **人** | 失败分类标签、覆盖率报告 | S2,S11 |

## 被测对象与「同模型」维度

| 场景 | 写实现 | 写测 | 跑测 | 终裁 oracle | 循环证明风险 | 出处 |
|------|--------|------|------|-------------|--------------|------|
| **危险默认** | 模型 M | 模型 M | M/CI | M 生成 assertion | **高** | S2,S7 |
| **EXECCRITIC** | Repair(M) | Test(M′) 冻结 | Harness | 隐藏官方 evaluator | 中（测质量） | S2 |
| **TDFlow 人写测** | Agent | **人** | Harness | 人写 reproduction | 低-中 | S1 |
| **CI autofix** | Agent | **已有 CI** | GHA | 既有 CI 测集 | 低-中 | S5 |
| **契约优先** | Agent | **人/契约** OpenAPI | CI | 契约 + 隐藏测 | 低 | 推断+S3 |

## 码错 vs 测错判定（机制行）

| 信号 | 倾向 | 动作 | 出处 |
|------|------|------|------|
| 改实现后仍 fail，改测（在允许时）后 pass | 原测可能错或弱 | 人审测；BTR/金 patch qualify | S1,S2 |
| 测 fail 于**金/官方 patch** 上 | **测错** | 丢弃测（S8 ~40% 丢弃先例） | S8 |
| 测仅在 buggy 代码 fail、金 patch pass | **测有效** | 冻结测，只改实现 | S1,S2 |
| LLM assertion 与文档矛盾 | **oracle 错** | 差分/PBT/人审 | S7 |
| 同轨迹 patch+测 同时绿但 issue 未关 | **循环证明** | 独立 oracle；交叉模型 Test | S2,E2 |
