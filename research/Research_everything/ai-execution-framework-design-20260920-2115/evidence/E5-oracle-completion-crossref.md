# E5 — 「做完了」：Oracle 与仓内交叉引用

**Asia/Shanghai 2026-09-20 21:15**

## 本仓库姊妹路径（待核实是否已落盘）

- 约定目录：`ai-automated-test-verify-code-20260917-0940/`（自动化测试 / 命令 exit code / 产物校验作为 **完成 oracle**）
- **2026-09-20 workspace 快照：** `git ls-tree` 未检出该目录 → 下文为 **推断** 级交叉引用，不重复其报告正文。

## 机制摘要（推断，与执行框架接口）

| Oracle 类型 | 执行框架中的挂载点 | 防「模型自说自话」 |
|-------------|-------------------|-------------------|
| 测试/lint exit code | Gate 层 **成功谓词**；工具 `run_tests` 返回原始 stdout+code | 无 tool output 不得标完成 |
| 文件/目录存在性 | State.`artifacts[]` + `read_file` 二次确认 | 与 trace 留证绑定 |
| CI 远程绿 | IDE/CI 集成维：push 后订阅 workflow（**待核实** 各 Host） | 人审 + CI 双门 |
| 无 oracle 任务 | 仅允许 **人审 ACK** 或 **显式「无法自动验证」** 交付物 | 禁止伪 verified |

## 标注

- 路径存在性：**待核实**
- Oracle 分层：**推断**（与 S1 grounding、S8 tool output 契约一致）
