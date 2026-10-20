# 行数限制与尾部省略验证

日期：2026-10-20。基于基础显示提交 `e064f5e` 增量实现；本记录随行数限制功能提交保存。未推送远端，未创建 Tag 或 Release。

## 行为与接口

- 新增 `LYGlyphTextConfiguration.numberOfLines: Int`，初始化默认 0；使用时将负值按 0 处理。UIKit／SwiftUI 共用配置，没有额外 Label 行数属性。
- 0 为无限行，正值限制可见行数。只有原始排版超出限制才生成一个 `…`；显式换行、空行和末尾空行计入行数，刚好容纳时不省略。
- token 使用最后可见行起点的字体与前景色。只容纳 token 时仅绘制 token；连 token 也放不下时不绘制末行文字，但保留该行正常高度。0 宽度保留原安全测量行为。
- 固有宽度仍来自完整内容理想宽度；固有高度、离屏测量和 SwiftUI 尺寸均遵守限制。外部高度不足仅裁切，不触发省略。
- 测量与绘制复用最终 Core Text 行。之前完整可见行保留原 CTLine／基线，末行使用固定原段落方向后的 Core Text shaping；垂直度量继续由 framesetter 决定，不手工累加字体行高。
- 内部 `visibleSourceRanges` 使用原文 UTF-16 索引；`sourceOffset` 将重建末行的局部索引映射到原文，生成 token 使用独立 `truncationTokenRange`。按最终 runs 取得片段，合并组合字符内属性拆分产生的重叠区间；保留双向文本的多片段，不把整条原始行范围当成截断后范围。
- 原有两份布局缓存上限、配置失效及宿主 Hugging／Compression Resistance 保留。

## 环境与执行

| 项目 | 本轮环境 |
|---|---|
| Xcode | 27.1（27A9275） |
| 编译器／语言模式 | Apple Swift 6.4／Swift 6 language mode |
| XcodeGen／SwiftFormat | 2.46.0／0.59.1 |
| Simulator | 本任务独立 LYGlyphText Validation，iPhone 17 Pro，arm64 |
| 运行系统 | iOS 27.0（24A434） |

执行入口：

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test <本任务独立Simulator的UDID>
```

本轮没有改动检查工具；组件、宿主与 UI 测试由 shared scheme 一次执行，不额外重复 Package tests。

## 验收矩阵

| 场景 | 验证方式 |
|---|---|
| 无限／负值／1／2／3 行，exact-fit | TruncationTests；行数、高度、生成 token 数与原始几何 |
| 显式换行、末尾换行、空文本／纯换行／空白 | TruncationTests、LayoutTests；包括 CRLF、U+2028、U+2029 |
| token 恰好容纳／无法容纳、0 宽 | TruncationTests；实际 glyph 数、空映射、正常行高与有限尺寸 |
| 中英文、长单词、混合字号／颜色 | TruncationTests；保留字形、token 起点字体和前景色；隐藏大字号不撑高 |
| 家庭 emoji／肤色／旗帜／组合重音 | TruncationTests；多个宽度和限制组合，映射端点在 Character 边界 |
| emoji 内属性拆分 | TruncationTests；部分 surrogate 的颜色属性不使可见映射切开整颗 emoji |
| RTL／双向片段 | TruncationTests；自然／显式对齐、英文续行、首 strong 位于隐藏尾部，生成 token 在逻辑尾部 |
| 原文省略号与生成 token | TruncationTests；原文 `…` 保留原文索引，生成 token 单独标记 |
| 行距稳定 | TruncationTests；Helvetica 多行溢出后，前面完整行基线不变 |
| Auto Layout／缓存失效／离屏测量 | TruncationTests、AutoLayoutTests；行数与宽度反复切换、完整固有宽度、required 宽度和优先级保持 |
| UIKit／SwiftUI 一致 | TruncationTests、AutoLayoutTests；同输入高度差不超过一个物理像素 |
| 外部高度压缩 | TruncationTests、LayoutTests；无自动 token、原有绘制裁切回归 |
| 实际操作两端 Demo | DemoUITests；内容、宽度、无限／1／2／3 行切换及截图 |

最终结果：

- docs 与 SwiftFormat 0.59.1 检查通过，18 个 Swift 文件无需改写。
- `.build/verification/20261020T053147Z-73643-build/`：最终 Package／Demo Simulator 构建成功，保留 generate、package-build、demo-build 日志与 environment.json。
- `.build/verification/20261020T052907Z-72998-test/`：**46／46 Passed，0 failed，0 skipped**。包括 44 项宿主测试（其中 19 项截断专项）和 2 项真实 UI 测试；保留 tests.log、test-summary.json、Tests.xcresult 及截图 manifest。
- 全量截图复核后，仅将 SwiftUI 示例的固定宽度 frame 改为 leading 对齐，防止内容理想宽度小于 frame 时居中；组件内核与宿主测试源码未再变化。最终 build／format 已复验，2 项 UI 测试另行针对性复验，结果如下节记录。

## Demo 截图

截图来自上述专用 iOS 27.0 Simulator 的 XCTest 操作。核对两端 3 行尾部省略、混合样式单行 token 字体／颜色、显式空行的 token，以及恢复无限行。截图只证明该组 fixture，范围／emoji／RTL 结论来自专项几何测试。

最终 UI 复验 **2／2 Passed，0 failed，0 skipped**，结果见本地 `.build/verification/line-limits-final-ui.xcresult`、`line-limits-final-ui.log`、`line-limits-final-ui-summary.json`。附件导出为 `line-limits-final-ui-attachments/`，manifest 保留导出文件与测试附件名称的对应关系；本仓库保存以下 8 张最终截图：

| 场景 | UIKit | SwiftUI |
|---|---|---|
| 无限行，宽 160 | [截图](images/line-limits-uikit-multiline-160-unlimited.png) | [截图](images/line-limits-swiftui-multiline-160-unlimited.png) |
| 3 行，宽 160 | [截图](images/line-limits-uikit-multiline-160-three-lines.png) | [截图](images/line-limits-swiftui-multiline-160-three-lines.png) |
| 混合样式 1 行，宽 320 | [截图](images/line-limits-uikit-mixed-320-one-line.png) | [截图](images/line-limits-swiftui-mixed-320-one-line.png) |
| 显式换行 2 行，宽 320 | [截图](images/line-limits-uikit-explicit-newlines-two-lines.png) | [截图](images/line-limits-swiftui-explicit-newlines-two-lines.png) |

人工核对：两端 3 行换行位置和省略号一致；混合样式 token 保持紫色大字体；显式空行作为第二行保留并显示 token。SwiftUI 的示例容器现显式 leading 对齐，与 UIKit 的文本起点一致。



## 测试驱动与审查发现

- `line-limits-red.log`：先建立行数／高度行为测试，实际执行 3 项测试，9 个断言失败；旧行为仍显示 18 行，限制行数后高度不变。
- 第一版手工累加可见行度量，审查发现会改变 Helvetica 的原始行距；改为保留前面基线并复用 Core Text 的最终两行垂直度量。
- 第二版尝试对带人工分隔符的完整可见前缀重新排版，窄宽度下超宽 emoji 可使分隔符独占额外行，阿拉伯文上下文改变也可重排前面行；专项测试复现后放弃该方式。
- run 属性可在 emoji 内部分段，仅按 run 原样输出范围会切开组合字符；现将范围扩展到完整组合字符并合并重叠片段。
- 仅保存原文前缀仍不足以处理隐藏首 strong 字符的自然 RTL；现从完整源段落解析并固定基本方向，再 shaping 最终末行。覆盖英文续行、数字开头且隐藏阿拉伯文等回归。
- 格式工具会把 XCTest 中的强制 CF 类型转换改成条件转换，导致当前编译器拒绝；颜色断言改用 CFEqual，保持固定格式检查与真实编译均可验证。
- 独立规格审查与代码质量审查均通过；审查的 macOS Core Text 探针仅用于发现问题，运行验收仍以 iOS Simulator 测试为准。
- 原始失败／诊断日志保留在本地 `.build/verification/line-limits-*.log`，没有覆盖成成功结果。

## 未验证与边界

- **Swift 6.0 编译器兼容未验证**：实际编译器为 Swift 6.4；tools-version 和 Swift 6 语言模式不是旧编译器运行证据。
- **iOS 16 实际运行未验证**：本轮重新列出 runtime，仅有 iOS 18.x／27.x，没有 iOS 16。最低部署目标不替代运行验证。
- 本轮 RTL 范围仅限展示／截断验收，不代表完整国际化交互矩阵已完成。尚未实现附件、局部点击、长按、高亮和装饰样式。
- 未执行真实设备、完整 VoiceOver／Dynamic Type／列表矩阵或性能基线；后续阶段任务继续保留待办。
