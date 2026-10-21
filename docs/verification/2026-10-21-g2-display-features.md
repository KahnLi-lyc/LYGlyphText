# G2 显示能力验证记录

日期：2026-10-21。基于 G1，分支 `codex/g2-display-features`。执行契约见 [2.x Label 路线图](../superpowers/plans/2026-10-21-label-roadmap.md) G2。

## 交付的公开接口

| 接口 | 行为 |
|---|---|
| `LYGlyphTextTruncationToken` 与 `LYGlyphTextConfiguration.truncationToken` | 默认 nil 时保持 `…` 与既有行为。可设置文字、字体、颜色；nil 字体／颜色继承末行起点。换行符按空格显示，空字符串表示截断但不追加内容。token 与末行前缀共同排版，空间不足时与 `…` 一样整体省略。 |
| token 动作 | `actionID` 非空时 token 可点击／长按，序号位于全部文档动作之后；事件 `isTruncationToken == true`，`range` 为 `NSRange(location: NSNotFound, length: 0)`。按下时使用 `pressedForegroundColor`、`pressedBackgroundColor` 与 `pressedCornerRadius`。可交互 token 作为最后一个 AX 元素，不可交互 token 不单独朗读。 |
| `LYGlyphTextActionEvent.isTruncationToken` | 新增只读属性；文档动作为 false。 |
| `LYGlyphTextPressedStyle.cornerRadius` | 默认 0 保持直角合成。大于 0 时同一行相邻片段先合并，再按片段绘制圆角背景；非有限值和负值按 0 处理，半径不超过片段宽高的一半。 |
| `NSShadow`（`.shadow`） | 偏移、模糊、颜色（nil 为 1/3 不透明黑色）随字形绘制，动态颜色按显示环境解析；不改变测量。按下局部着色的字形部分不绘制阴影，以免阴影进入合成遮罩。阴影超出内容区域时由现有裁切处理。 |
| `.strokeWidth`／`.strokeColor` | 宽度为字号百分比，正值只描边、负值填充并描边；颜色缺省使用前景色。绝对值超过 100 或非有限值忽略。不改变测量。 |
| `LYGlyphTextDocument(... linkPressedStyle:)` | 默认 nil 忽略 `.link`（与既有行为相同）。非 nil 时把 URL 或非空 String 的最长连续 `.link` 范围追加为动作，actionID 为 absoluteString 或该字符串；与显式动作重叠时按既有规则抛出 `overlappingActionRanges`。 |

## 范围调整

路线图 G2 列出的以下项本阶段不交付，记录原因，后续如需再立项：

- **head／middle 截断**：现有可见原文映射假设每行只有一个原文起点偏移；头部／中间截断需要把一行拆成多段原文映射，影响命中、选区（G5）和附件定位，风险高于收益。
- **整段点击回调**：组件动作识别器只在命中动作时接收触摸，宿主可直接为 Label 添加自己的 `UITapGestureRecognizer`；组件内建需要真实手势的冲突矩阵验证，留待 G5 选择手势一并设计。
- **纯文本便捷构造**：唯一可能失败的纯文本输入是 U+FFFC；不抛错的便捷入口只能静默改写或吞掉错误，违反“不以默认值掩盖非法输入”。保持 `try LYGlyphTextDocument(attributedText:)`。
- **文档级圆角背景**：普通 `.backgroundColor` 仍为直角；圆角只用于按下样式与 token。

## 行为证据

新增 `Tests/LYGlyphTextTests/DisplayFeatureTests.swift`（15 项）：默认 token 不变、自定义文字／字体／颜色、空 token 与换行、token 放不下时整体省略、Label 配置变化失效、真实窗口中 token 点击事件与文档动作并存、空／nil actionID 不可交互、按下 token 的背景与前景像素、可交互 token 的 AX 元素、按下圆角（角点像素）、阴影向下偏移（像素均值）、正负描边、描边不改测量、`.link` 转动作及与显式动作重叠报错、圆角参数清洗。

- 失败证据：`.build/verification/g2-targeted-01/`（worktree 内）169 项中 `testPressedTokenDrawsBackgroundAndForegroundColor` 失败：按下 token 时蓝色像素 0、绿色 4960。原因是 token 属性未设置“前景色取自上下文”，Core Text 继续用属性色。修复为 token 与原文 run 一样从绘制上下文取填充色（未按下时上下文颜色即 token 颜色，外观不变）。
- 修复后定向：`g2-targeted-02/` 104 项通过。

## 正式检查

环境同 G1：Xcode 27.1／Swift 6.4／Swift 6 模式，iPhone 17 Pro Simulator iOS 27.0（`5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`）。

| 检查 | 结果 |
|---|---|
| 固定 SwiftFormat 0.59.1 | 94 个 Swift 文件 0 需格式化 |
| `scripts/verify.sh docs`／`build` | PASS；Package 与 Demo Swift 6 模式构建通过 |
| `scripts/verify.sh test` | **386／386 Passed（362 宿主＋24 UI）**，0 失败／跳过／预期失败，`runtimeWarnings=[]` |

G1 的 371 个测试方法全部保留，新增 15 项。证据在 G2 worktree 的 `.build/verification/20261021T103643Z-72012-test/` 与 `g2-test-tree.json`。按路线图验收项自查规格与质量（新增公开 API 均为可选、默认值保持原行为；无并发逃生标记；无新依赖）。Swift 6.0 编译器与 iOS 16 运行仍未验证。
