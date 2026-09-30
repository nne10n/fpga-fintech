# E4 — 机制留证：ReAct  grounding 与纯推理对比

**Asia/Shanghai 2026-09-20 21:15**

## 摘录（事实）

来源：ReAct 论文摘要（S1）

> ReAct … generating both reasoning traces and task-specific actions in an **interleaved** manner … actions allow it to **interface with and gather additional information from external sources** … on HotpotQA and Fever, ReAct overcomes prevalent issues of **hallucination and error propagation in chain-of-thought reasoning** by interacting with a simple Wikipedia API.

来源：Google Research 博文（S1 同论文）

> with chain-of-thought prompting, a model is **not grounded in the external world** and uses its own internal representations … limiting its ability to reactively explore

## 用于「空转 vs 跑完」论证

- **事实：** 无工具观测的 CoT/ReAct 纯文本循环无法引入新事实，易 **自洽幻觉**（S1）。
- **推断：** 执行框架应强制：**终止条件** 必须绑定 **外部可验证信号**（测试 exit code、HTTP 200+schema、文件 hash、人审 ACK），而非仅「模型说完成了」。
- **边界：** ReAct 论文实验依赖特定 API/环境；迁移到 coding agent 时，**grounding 源** = 编译器/测试/ git diff，需自行接入工具层（S8）。

标注：**事实**（论文）+ **推断**（工程映射）。
