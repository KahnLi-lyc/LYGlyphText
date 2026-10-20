# 2026-10-20 工程规范与布局计划验收

## 范围与环境

本轮完成阶段 0 的工程规范、工具配置与布局契约修订。组件阶段 1—7 保持未实施；没有新增 Package.swift、Sources、组件 Tests 或 Demo。

- 基线提交：`102bcc8fc0674988893d8df436dad4e3e0c2da12`。
- 任务分支：`codex/layout-engineering-rules`；目标本地 `main`。最终变更提交由本文件所在的 Git 历史确定，避免在提交内引用自身 SHA。
- 本机 Python：3.9.6；SwiftFormat：0.59.1，通过 `LYGLYPHTEXT_SWIFTFORMAT` 指向本机已有固定版本工具，本轮未联网安装工具。
- 工具源码固定提交：`22a472ced4c621a0e41b982a6f32dec868d09392`；bootstrap 实现核对提交与工作区状态，运行已有二进制只核对版本。
- 本次未运行 Xcode 构建、Simulator、最低 Swift 工具链或设备测试；本机工具链存在不作为组件可用证据。

## 已执行检查

| 检查 | 结果 |
|---|---|
| `scripts/verify.sh docs` | PASS：7 份 Markdown、2 个 Shell 脚本语法、文本约定及暂存／未暂存 diff |
| `scripts/verify.sh format` | SKIP／不适用：当前零 Swift 源文件，不是组件格式检查通过 |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v` | PASS：15 项工具回归测试；不属于组件测试 |
| 真实 SwiftFormat 临时样例 | 已通过：原始 lint 非零，格式化后 lint 为零，再格式化字节不变，版权／MIT 标识保留 |

工具回归使用临时 Git 仓库，不读取或改写工作区参考源码，覆盖：有效／失效本地链接、括号／空格路径、代码示例、围栏未闭合、绝对／越界链接、越界符号链接、忽略／生成目录、Shell 与换行约定、零 Swift 文件、工具缺失、版本不符、未知验证模式、格式检查失败传递、未知 bootstrap 源码目录保护。

真实格式工具样例使用临时 `.swift` 文件，包含版权头、SPDX MIT 标识、中文 DocC、缺失空格和分号；经本仓 wrapper 和配置执行 lint→format→lint→format。临时样例不进入组件源码；这只验证工具行为，不验证 Swift 类型检查。

## 布局契约审查

- Core Text 统一几何，首版不使用 TextKit 2。
- 明确 intrinsicContentSize、sizeThatFits、preferredMaxLayoutWidth、systemLayoutSizeFitting 和标准 Hugging／Compression Resistance。
- 测量不创建附件或修改 frame／约束，不用旧高度限制新固有高度；有效宽度改变才触发自动高度失效。
- 宿主原生／SnapKit 约束、StackView、列表自适应、SwiftUI 提议宽度及环境变化均进入未来验收清单。
- 首／末文字基线对齐等价性不属于首版保证；高度裁切、附件可见区域与点击边界均明确。

以上是文档契约覆盖检查，Auto Layout、交互、附件、SwiftUI、VoiceOver、性能和 iOS 16 运行行为均未实现／未验证。

## 尚未验证与交付边界

没有运行 bootstrap 的真实下载／编译流程；已经验证普通检查不会自动安装工具，未知源码目录不会被覆盖。完整工具 bootstrap 需 GitHub 连通与本机 Swift 工具链。

本轮按约定自动提交并合入本地 main，不 push、不创建 PR／Tag／Release。远端内容不代表本次本地交付状态。
