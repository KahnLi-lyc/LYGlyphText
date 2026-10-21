# LYGlyphText 显示环境与无障碍实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 验证 Dynamic Type、明暗和 RTL 环境，提供最终可见内容的无障碍语义、原生附件与动作激活；自动化和人工 VoiceOver 分开留证。

**Architecture:** 文档保持不可变，Core Text 唯一排版，复用最终 SourceGeometry 和 DisplayGeometry。Label 管理环境失效、弱所有权语义元素及激活生命周期；SwiftUI 继续使用同一 Label。无障碍查询不排版、不创建附件、不改布局。

**Tech Stack:** iOS 16+、Swift tools 6.0／Swift 6 mode、UIKit、SwiftUI、Core Text、XCTest／XCUITest、固定 SwiftFormat 0.59.1。

## 起点与执行边界

分支 `codex/environment-accessibility`，基线为 H1 已推送的 `32ac04a`。H1 正式 319／319（298 宿主＋21 UI）、12 张截图、73 文件冻结和两次最终审查通过。保留现有 checkout 和全部回归；所有实现块串行，单一源码实施者，先规格审查后质量审查。审查问题返回原实施者修复。

唯一 Simulator 为 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`，iPhone 17 Pro／iOS 27；不得并发 xcodebuild。Xcode 27.1／Swift 6.4。Swift 6.0 编译器、iOS 16 实际运行、真机和人工 VoiceOver 独立标记未验证。

## 固定契约

1. 缺省 `.font` 使用当前 trait 的动态 body；显式 UIFont 快照保持固定，包括 preferredFont 或 UIFontMetrics 已产生的快照。不从 descriptor 猜测缩放基准，不新增公开字体参数。trait 更新重新测量默认字体、附件对齐和语义颜色；图片声明尺寸、kern、baseline、段距不额外缩放。
2. 动态前景、背景、线色及按下色使用当前 trait；真实 RTL 宿主保留 Core Text 逻辑源映射，显式段落方向优先。图片不额外镜像，原生 UIView 使用系统语义方向。
3. Label 默认是无障碍容器。按原文 UTF-16 逻辑顺序提供最终可见 grapheme，并按动作、附件边界分区；不暴露截断源，不把生成 token 当原文或动作。使用最终 SourceGeometry 的 cell／piece 及 DisplayGeometry 裁切，不重新 shaping。
4. 图片／非交互 UIView 有非空 alternativeText 才读，nil／空作装饰。动作内替代文本只读一次。已挂载交互 UIView 切出为原生子树，不把其按钮名重复拼进动作；nil／拒绝工厂以可见 alternativeText 回退。不改写工厂视图的 AX label／traits。
5. 动作仅在 callback 非空且存在可见内容时具有 button trait；否则是静态文本。`accessibilityActivate()` 发送现有 `.tap`、完整 action.range 与当前裁切 visibleRects；不增加 VO long press action。先清按压，再调用最新 callback。同步重入最多发送一次；后续独立激活可再次发送。
6. 合成元素弱持有 Label，用文档／几何／附件 revision 校验。document、bounds、configuration、trait、provider、reload、window 移除及 dismantle 后旧元素失效。回调替换非空仍读取最新值。旧元素不保活 owner／document／provider。
7. 合成本地 frame／path 严格裁切，多行 path 在 getter 实时转屏幕坐标，祖先滚动后不冻结。完全隐藏原生附件不暴露；部分可见原生子树保留 UIKit 语义，任意原生后代 AX frame 的裁切不作保证，单独实测记录。
8. 只使用 `accessibilityElements` 一个自动入口；宿主显式数组优先，置 nil 恢复自动。组件初始化 `isAccessibilityElement=false`，不在更新中覆盖宿主 isAccessibilityElement／label／hint／traits／hidden 设置。查询不调用 layoutIfNeeded／reconcile／factory，不每次查询发送 layoutChanged。
9. 两端同文档、配置、宽度与 scale 高度差不超过一个物理像素。SwiftUI 先测 dynamicTypeSize／preferredColorScheme／layoutDirection 的真实 trait 继承，缺口才补内部代码；不增加 public 参数。

### 实施前只读契约复核

- grapheme 任一 piece 经 bounds／contentClip 裁切后面积大于零，则纳入完整 grapheme；完全无交集才排除，不能截取半个 UTF-16／emoji。分别测试水平及垂直部分裁切。
- 仅有已挂载交互原生附件的动作只暴露原生子树；仅有 nil／空 alt 装饰附件不生成空名合成按钮。失败工厂的非空 alt 可生成合成动作。文本—原生按钮—文本必须保持逻辑顺序，不重复拼按钮名。
- callback 的 nil／非 nil 切换即时改变现有自动元素的 traits／可激活性，不依赖下一次 layout；非空替换保持元素有效并读取最新 callback。动作身份使用 actionIndex，不能合并重复 actionID。
- 快照在附件 reconciliation 完成且 revision 匹配后一次发布；工厂／卸载回调同步换文档、provider、reload 或 window 后不得发布过期快照。发送 guard 包住清按压与 callback，callback 创建新元素再激活同样拒绝同步重入。
- 显式 `accessibilityElements=[]` 禁止自动入口，只有 nil 恢复。非交互 UIView 即使包含 AX 子树也只读声明替代文本，不改写其原生属性。实时坐标测试仅滚祖先 contentOffset，不重排 Label，同时验证 frame／path 更新及布局计数不增。
- 同一动作／附件分区按 UTF-16 源顺序拼接 cell。源连续直接拼接；存在 gap 时，只有 gap 全部 scalar 都是换行分隔符（含 CRLF）才规范化为一个空格；其他 gap 拆成两个元素，不补读 gap。软换行不加空格，分隔字符不新增几何。测试 `A\nB`／CRLF／多换行为 `A B`，软换行 `AB` 仍为 `AB`，隐藏正文 gap 只能产生分离的 A、B 元素。自动标签分隔不代替人工朗读停顿验收。

## 文件职责

| 文件 | 职责 |
|---|---|
| `Tests/LYGlyphTextTests/EnvironmentTests.swift` | trait 字号、显式字体、颜色、RTL、两端环境与测量纯度 |
| `Sources/LYGlyphText/UIKit/TextAccessibility.swift` | 内部语义分区、弱 owner UIAccessibilityElement、实时 frame/path |
| `Sources/LYGlyphText/UIKit/LYGlyphTextLabel.swift` | 自动容器、revision 校验、激活 guard、挂载子树入口 |
| `Tests/LYGlyphTextTests/AccessibilityTests.swift` | 可见语义、裁切、生命周期、重入与宿主覆盖 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/EnvironmentSamples.swift` | 共用默认字体、语义色、混合方向及附件／动作输入 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/UIKitEnvironmentController.swift` | UIKit 真实环境控件和状态 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/SwiftUIEnvironmentView.swift` | 同组 SwiftUI 环境控件和状态 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemoTests/EnvironmentDemoHostTests.swift` | 真实导航内 trait／48 配置高度及样本独立性 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemoUITests/EnvironmentUITests.swift` | 真操作、元素／按钮激活和截图 |
| `docs/verification/2026-10-21-environment-accessibility.md` | 红绿、自动化、审查、截图及人工验收缺口 |

## A1a：环境矩阵

- [x] 写 `EnvironmentTests`：`testDefaultBodyTracksContentSizeCategory`、`testExplicitFixedFontDoesNotScale`、`testAttachmentAlignmentTracksDefaultFontWithoutResizing`、`testSemanticColorsResolveForLightAndDark`、`testRTLHostPreservesSourceMappingAndImageOrientation`、`testSwiftUIEnvironmentReachesLabelAndMatchesUIKit`、`testEnvironmentMeasurementDoesNotMountAttachments`。字号至少 large／extraExtraExtraLarge／accessibilityExtraExtraExtraLarge；字体 traits、三附件对齐、语义前景／背景／线色／按下色均保留证据。
- [x] 用真实 child controller／UIHostingController 覆盖 trait；保存测试源码及旧实现实际行为结果。已有能力可直接绿，不虚构红测试；发现缺口先保留失败结果，再最小修复，不扩大字体 API。
- [x] 单独运行 EnvironmentTests 和既有 Attachment／PressedDrawing／SwiftUIHost 回归；非零测试、固定 format、源码哈希及环境保存在 `.build/verification/a1a-*`。
- [x] 规格审查逐项映射上述契约；批准后质量审查，检查 trait 失效／缓存两项／无测量副作用。A1a 最终规格及质量复审批准，进入 A1b。

定向命令模板（每次使用新的结果目录）：

```sh
xcodegen generate --spec Examples/LYGlyphTextDemo/project.yml
xcodebuild test -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj -scheme LYGlyphTextDemo -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' -derivedDataPath .build/DemoDerivedData -parallel-testing-enabled NO -only-testing:LYGlyphTextDemoTests/EnvironmentTests -resultBundlePath .build/verification/a1a-green/Tests.xcresult SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

## A1b：可见语义与激活

- [x] 先建立失败行为测试：`testVisibleSemanticsExcludeTokenAndHiddenSource`、`testLogicalOrderIncludesEmojiRTLAndAlternativeTextOnce`、`testInteractiveAttachmentAppearsOnceInActionRange`、`testAccessibilityActivationReadsLatestCallback`、`testOldElementCannotActivateAfterReload`、`testActivationReentrySendsOnce`、`testAccessibilityQueryDoesNotMountAttachments`、`testAccessibilityPathTracksAncestorScroll`、`testHostAccessibilityOverridesSurviveUpdates`、`testPartiallyClippedNativeButtonAccessibility`。另覆盖 clear／provider／bounds／trait／window／dismantle、weak owner 和双宿主独立。
- [x] 新内部 `TextAccessibility` 从已构建的最终布局与挂载快照分区。Label 在展示布局时准备语义快照；查询只读。源字符串取 document.string，range 按 grapheme cell 组成；附件占位符替换非空 alt，native interactive 子树单列。保留可见 source discontinuity，不能读被截断／裁切文字。
- [x] Label 以 revision 元组和 isSendingAccessibilityAction 校验激活；先 cancelActionInteraction，再以最新 onAction 调用 ActionGeometry 的当前 entry.event(kind:.tap)。全部同步重入测试必须通过；不要让元件持有 callback。
- [x] 跑 AccessibilityTests 及 ActionInteraction／ViewAttachment／EnvironmentTests；保存红绿、固定 format 和冻结，先规格再质量审查。

## A1c：共用 Demo 与真实 UI

- [x] 两端添加同一文档的字号（三档）、Light／Dark、LTR／RTL、宽度（160／320）、行数（1／不限）、动作和原生按钮控件；状态同时显示当前选择与事件计数，产品界面不显示内部几何。
- [x] UI 测试实际操作各控件，并以无障碍元素查找可见动作和原生按钮，真实 tap／激活验证最新回调。覆盖浅深、大字号、RTL，至少两端各三张截图，截断与宽度切换排除隐藏源。宿主矩阵使用真实 UINavigationController 嵌入，等待当前文档的存活 Label；Dark 必须核对实际 trait 和语义色，最大字号尾标记必须真正进入可见区，不能只看 selected／isHittable。
- [x] 逐张导出检查文字／附件方向、裁切、基线和两端高度；自动化元素查询／激活不等同人工 VoiceOver。完成定向测试、format、冻结、规格及质量审查。

## A1d：完整回归、文档和交付

- [x] 执行 `scripts/verify.sh docs`、固定版本 `format`、`build`、`test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`；保留 319 既有回归，报告实际新增 host/UI 数量、零失败／跳过与 runtimeWarnings。测试前冻结全部 Swift，测试后核哈希。
- [x] 更新 README、总计划、连续计划及专项记录。自动化环境和 AX 已验证项单独勾选；人工朗读／重复朗读／焦点体验、旧编译器、iOS16、真机均保留未验证，不将整项人工 VO 勾选。
- [x] 最终跨块规格审查后质量审查；有问题返回原实施者修复，Swift 改动后按风险重跑并冻结。
- [ ] 中文 Conventional Commit，按 CONTRIBUTING 独占锁核基线／clean／候选，快进 main，普通 push 一次并核远端 SHA，只清理安全合入的临时分支。不创建 PR／Tag／Release，不 pull／rebase／强推。
- [ ] 自动进入 P1 固定负载、释放／性能及发布准备；缺失环境列发布阻塞，不冒领发布资格。
