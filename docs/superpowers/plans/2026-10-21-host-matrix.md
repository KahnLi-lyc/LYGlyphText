# LYGlyphText 宿主矩阵实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 UIKit、SwiftUI、表格与集合列表的宿主布局矩阵，以自动测试和真实 UI 证明宽度驱动高度、复用状态及布局失效能够收敛。

**Architecture:** 继续由 `LYGlyphTextLabel` 的同一 Core Text 布局入口承担测量、绘制、附件和动作几何；宿主只提供明确宽度、完整约束链及正常的列表尺寸失效。H1 不新增公开 API，只加入 internal 测量诊断和 SwiftUI proposal 纯测量入口，使测试能直接证明缓存上限、失效次数和两端高度一致。

**Tech Stack:** iOS 16+、Swift tools 6.0／Swift 6 language mode、UIKit、SwiftUI、Core Text、XCTest／XCUITest、XcodeGen 2.46.0、SwiftFormat 0.59.1。

---

## 1. 起点、范围与交付边界

基线为 `003558cd7c72116fcb889162ccf8ecd232e5ec70`，分支为 `codex/host-matrix`；开始规划时本地 `main` 与 `origin/main` 跟踪记录均指向该提交。I1 已以该提交完成交付，正式结果为 276 项宿主测试加 18 项 UI 测试，共 294／294 通过。H1 不重复 I1 的文字命中算法或按下绘制，只在真实宿主重排和复用时验证状态不会串行。

H1 包含以下能力：

- UIKit 横向／纵向 `UIStackView` 的合法 alignment 和 distribution、并排按钮、两个方向的 Hugging／Compression Resistance，以及首末文字基线不在本组件承诺内的边界。
- `UITableView.automaticDimension` 与 `UICollectionView` self-sizing／离屏测量，覆盖长短文本、UIImage／UIView 附件尺寸替换、0→正宽、窄→宽→窄，以及旋转、分屏和窗口缩放等价的 bounds 更新。
- SwiftUI `.frame`、HStack、VStack、List、LazyVStack，覆盖 nil／0／有限／无限宽度 proposal、同文档 callback／provider 更新、清空／替换，以及附件／按压／回调在复用中不串行。
- 组件主动固有尺寸失效次数、布局实际构建次数和缓存项数的可观察证据；稳定输入布局必须收敛，单个 Label 仍最多保留两个布局结果。
- UIKit 与 SwiftUI 对同一文档、配置和有效宽度的自然高度差不超过一个物理像素。
- UIKit／SwiftUI 真实 Demo 操作宽度切换、列表滚动复用、原生附件按钮和文字动作，并保留截图。

H1 明确排除：Dynamic Type 完整字号矩阵、Dark Mode、环境 RTL、VoiceOver 元素与人工朗读属于 A1；100／1000／5000 固定负载、帧率、内存趋势和 Instruments 属于 P1。H1 的混合方向文档只作为已有排版回归，不将其描述为环境 RTL 验收。H1 不增加 firstBaseline／lastBaseline 适配，不声称默认 `UIView` 基线与 `UILabel` 文字基线等价。

所有实现块严格串行。每块由一个源码实施者完成红测试、最小实现、定向绿测试和冻结；随后先做规格审查，再做质量审查。审查发现的问题返回该块原实施者修复并按同一顺序复审；上一块批准后才开始下一块。不得并发改写 `LYGlyphTextLabel.swift`、`LYGlyphTextView.swift` 或共享 Demo 状态。

## 当前执行状态

H1 功能验收完成：正式 docs／format／Swift 6 build 及 319／319 完整回归（298 宿主＋21 UI）通过，0 failed／skipped／expected failures，runtimeWarnings=[]；12 张最终截图已导出并逐张检查。73 个 Swift 文件冻结哈希全匹配，mtime 早于最终测试。H1a／H1b／H1c 已依次通过规格及质量审查；H1d 最终规格与质量证据复审已批准；提交、集成和普通推送待执行，不记录尚未发生的交付结果。当前下一项为 A1，完成 H1 交付后自动实施。详细红绿、环境、截图与未验证项见 [H1 验证记录](../../verification/2026-10-21-host-matrix.md)。

## 2. 实施前覆盖审计

| 现有位置 | 已有证据 | H1 缺口 |
|---|---|---|
| `Tests/LYGlyphTextTests/AutoLayoutTests.swift` | 左右约束、固定／上限宽度、一个横向 StackView、优先级保留、SwiftUI 有限／理想／0 宽度和基础高度对比 | 横纵 StackView 完整合法矩阵、失效计数、缓存上限、无限 proposal 的直接契约、列表宿主 |
| `Sources/LYGlyphText/UIKit/LYGlyphTextLabel.swift` | 三种测量接口共用 `measuredLayout`；宽度变化触发固有尺寸失效；`cachedLayouts` 超过两项即淘汰 | 当前计数和缓存项数为 private，测试无法证明稳定布局不继续构建／失效 |
| `Sources/LYGlyphText/SwiftUI/LYGlyphTextView.swift` | proposal 宽度直接传入 `sizeThatFits`；有限宽度钳制；callback 先更新；dismantle 清理 | proposal 计算未抽成可直接断言的 internal 纯入口；未覆盖 HStack／VStack／List／LazyVStack 复用 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/ReuseDemoController.swift` | UITableView 自动行高、完整四边约束、附件按钮复用清理，已有宽度 390→320→600→390 宿主测试 | 仅 UITableView，数据以 UIView 附件为主；缺 UICollectionView、0 宽、尺寸替换、动作按压与 provider/callback 更新矩阵 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/UIKitDemoController.swift` | 纵向页面 StackView、横向富文本与按钮、宽度切换 | 没有独立合法 alignment／distribution 操作页，也没有列表矩阵状态 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/SwiftUIDemoView.swift` | VStack、一个 HStack、`.frame(width:)` 和内容／宽度切换 | 没有 List／LazyVStack、同 identity 重绑、callback／provider 更新及复用状态证据 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemoUITests/` | 基础宽度、附件列表、文字动作列表的真实操作 | 没有 H1 两端入口、UICollectionView self-sizing、跨容器宽度往返和 H1 截图 |

上述已有用例全部保留。H1 新测试不得用删除旧断言、扩大容差或固定 cell 高度换取通过。

## 3. 文件结构与职责

### 3.1 组件与测试

| 文件 | 操作 | 职责 |
|---|---|---|
| `Sources/LYGlyphText/UIKit/LayoutMeasurementDiagnostics.swift` | Create | internal 只读测量快照值，不持有 Label、文档、UIView 或闭包 |
| `Sources/LYGlyphText/UIKit/LYGlyphTextLabel.swift` | Modify | 记录组件主动失效与缓存 miss；暴露 internal 快照／重置计数；保持最多两个缓存 |
| `Sources/LYGlyphText/SwiftUI/LYGlyphTextView.swift` | Modify | 抽取 internal proposal 纯测量函数，`UIViewRepresentable.sizeThatFits` 继续调用同一函数 |
| `Tests/LYGlyphTextTests/HostLayoutTests.swift` | Create | H1a StackView、CHCR、宽度收敛、缓存与两端高度矩阵 |
| `Tests/LYGlyphTextTests/HostListTests.swift` | Create | H1b UITableView／UICollectionView、离屏测量、附件变化与复用状态 |
| `Tests/LYGlyphTextTests/SwiftUIHostTests.swift` | Create | H1c proposal、HStack／VStack／List／LazyVStack、更新与拆卸 |

### 3.2 Demo、UI 测试与文档

| 文件 | 操作 | 职责 |
|---|---|---|
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/HostMatrixSamples.swift` | Create | 两端共用的短文、长文、图片／UIView 附件尺寸变体、动作行模型 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/UIKitHostMatrixController.swift` | Create | StackView 矩阵、宽度模式、UITableView／UICollectionView 入口与状态 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/HostMatrixTableController.swift` | Create | 自动行高、完整约束链、prepareForReuse 清理与重新绑定 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/HostMatrixCollectionController.swift` | Create | self-sizing cell、estimated size、离屏宽度与宿主布局失效 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/SwiftUIHostMatrixView.swift` | Create | `.frame`、HStack／VStack／List／LazyVStack 的共用状态与 identity 复用 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemo/DemoAppDelegate.swift` | Modify | 增加 UIKit／SwiftUI H1 入口，不改变已有入口标识 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemoTests/HostMatrixDemoHostTests.swift` | Create | Demo 控制器、完整约束、列表 self-sizing 和状态清理的宿主测试 |
| `Examples/LYGlyphTextDemo/LYGlyphTextDemoUITests/HostMatrixUITests.swift` | Create | 两端真实宽度切换、滚动复用、按钮／动作与截图 |
| `README.md` | Modify | 只在验收后写入已验证宿主矩阵与明确的宿主宽度责任 |
| `docs/verification/2026-10-21-host-matrix.md` | Create | 红绿、审查、环境、测试数、截图和未验证项 |
| `docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md` | Modify | H1 状态、真实证据与阶段 6 勾选 |
| `docs/superpowers/plans/2026-10-20-continuous-development.md` | Modify | 当前阶段从 I1 推进 H1；H1 完成后指向 A1 |

`Examples/LYGlyphTextDemo/project.yml` 已递归包含 Demo、宿主测试和 UI 测试目录；H1 不新增 target 或依赖，因此不修改生成工程或 project spec。

## 4. 固定契约

### 4.1 UIKit 测量、失效与缓存

不新增 public 属性。新增 internal 值类型必须使用以下字段和语义：

```swift
@MainActor
struct LayoutMeasurementSnapshot: Equatable {
    let layoutBuildCount: Int
    let intrinsicInvalidationCount: Int
    let cachedLayoutCount: Int
}
```

`LYGlyphTextLabel` 增加 internal 的 `layoutMeasurementSnapshot` 与 `resetLayoutMeasurementCounts()`。`layoutBuildCount` 只在 `measuredLayout(width:)` 缓存 miss 并真正调用 `ResolvedText.layout` 时增加；cache hit 不增加。`intrinsicInvalidationCount` 只统计组件主动请求的 `invalidateIntrinsicContentSize()`，不尝试拦截 UIKit 内部行为。`cachedLayoutCount` 读取当前缓存数，任何时刻必须为 0...2。重置只归零累计计数，不清空缓存、不改变 frame／约束／文档／附件／动作状态。

所有组件主动失效统一经 private `requestIntrinsicSizeInvalidation()`：文档／配置改变、有效 `preferredMaxLayoutWidth` 改变，以及自动模式中有效 bounds 宽度改变时各产生一次请求；相同输入重复赋值、相同有效宽度重复布局、callback 更新和相同 provider 身份更新不产生请求。文档变化仍清除缓存；宽度变化只依赖现有的两项有界缓存，不建立全局缓存，也不要求本阶段改变命中项的既有排序政策。

### 4.2 StackView 与基线边界

- 横向 StackView 验收 alignment `.fill`、`.top`、`.center`、`.bottom`；纵向验收 `.fill`、`.leading`、`.center`、`.trailing`。
- 两个方向均验收 distribution `.fill`、`.fillEqually`、`.fillProportionally`、`.equalSpacing`、`.equalCentering`，断言无 ambiguous layout、尺寸有限非负、arrangedSubview 位于 stack 轴向范围，并在有明确宽度时富文本高度等于同宽 `sizeThatFits` 的像素对齐结果。
- 并排按钮使用宿主设置的 CHCR 决定压缩方；文档、配置、provider、reload 和复用不能把宿主设置重置为默认值。
- `.firstBaseline`／`.lastBaseline` 不进入支持矩阵，Demo 不提供这两个选项，README 保留“当前不保证与 UILabel 首／末文字基线等价”。若宿主自行选择基线 alignment，只获得 UIView 默认行为。

### 4.3 列表与宿主宽度责任

- UITableView cell 的 `contentView` 四边约束完整，`rowHeight = .automaticDimension`；UICollectionView cell 的 `contentView` 四边约束完整，并在 `preferredLayoutAttributesFitting(_:)` 中以 layout attributes 提供的明确内容宽度调用标准 `systemLayoutSizeFitting`。两者只在宿主 cell 内同步 `preferredMaxLayoutWidth`，组件不读取屏幕宽度。
- 列表控制器可实现自己的 dataSource／delegate 和 layout invalidation；`LYGlyphTextLabel` 不成为列表 delegate，不保存 table／collection layout，不调用 reloadData／invalidateLayout。
- 离屏测量传入 required 横向宽度；0 宽得到有限零宽结果且不创建附件 View，变为正宽后恢复正常高度。窄→宽→窄必须回到相同像素高度；bounds origin 不影响自然尺寸。
- 用新文档表达长短文本、图片和 UIView 附件声明尺寸变化。工厂 view 的 frame／intrinsicContentSize 不反向改变文本尺寸。可见 cell 重绑前按顺序清空 `onAction`、`document`、`viewProvider`，再安装当前 row 的回调、文档和 provider；旧按压、附件、按钮计数和事件状态不得出现在新 row。
- 旋转、分屏、窗口缩放以宿主 bounds 序列 `0 → 320 → 600 → 240 → 320` 验收。每个正宽稳定后，cell 高度包含同宽自然内容，连续四次 `layoutIfNeeded` 后诊断计数不再增长。

### 4.4 SwiftUI proposal 与复用

`LYGlyphTextView` 抽取以下 internal 静态函数，公开初始化签名不变：

```swift
static func measuredSize(
    proposal: ProposedViewSize,
    displayHeight: CGFloat?,
    label: LYGlyphTextLabel
) -> CGSize
```

规则固定为：nil／无限宽度传 `.infinity` 给 UIKit，从而使用理想宽度；有限宽度钳制到 `max(0, width)` 并作为返回宽度。proposal.height 不限制自然高度。只有有限非负 `displayHeight` 覆盖高度。函数不改 label bounds／frame／constraints／document／provider，不调用 `layoutIfNeeded`，不创建附件，也不写 Binding。`UIViewRepresentable.sizeThatFits` 只返回该函数结果。

- `.frame(width:)` 使用固定宽度；HStack 通过 `layoutPriority` 决定可用空间，不映射成 UIKit CHCR；VStack 使用父提议宽度。
- List 和 LazyVStack 行必须有稳定 row ID。相同文档 identity 更新 callback／相同 provider identity 时，布局 build／失效计数不增长；发送事件时使用最新 callback。provider 对象替换只重建可见 UIView 附件，不清除布局缓存；文档替换或 nil 清空按已有契约失效布局与交互。
- SwiftUI row 消失、复用或 dismantle 后不得保留 pressedAction、旧 callback 或旧 provider 生成的附件。重新出现时绑定当前 row 状态。
- 与 UIKit 对比时使用同一个 document、configuration、display scale 和有限宽度；高度容差为 `1 / max(displayScale, 1)` point。

### 4.5 共用 Demo fixture

`HostMatrixSamples.swift` 定义且只定义以下宿主数据和行状态，UIKit／SwiftUI 页面消费同一份 `HostMatrixSamples`，但为各自可见 row 创建独立 `HostMatrixRowState`：

```swift
@MainActor
enum HostMatrixContent: Int, CaseIterable {
    case shortText, longText, smallImage, largeImage, smallView, largeView, action
}

@MainActor
struct HostMatrixRow: Identifiable {
    let id: Int
    let documents: [HostMatrixContent: LYGlyphTextDocument]
}

@MainActor
enum HostMatrixCallback: String, CaseIterable {
    case a = "A"
    case b = "B"
}

@MainActor
final class HostMatrixRowState: ObservableObject {
    let rowID: Int
    @Published private(set) var actionCount = 0
    @Published private(set) var buttonCount = 0
    @Published private(set) var callback = HostMatrixCallback.a
    lazy var provider: LYGlyphTextAttachmentViewProvider = makeProvider()

    func receive(_ event: LYGlyphTextActionEvent)
    func selectCallback(_ callback: HostMatrixCallback)
    func resetForReuse()
    private func makeProvider() -> LYGlyphTextAttachmentViewProvider
}
```

`HostMatrixSamples` 生成 40 个稳定 row，全部使用本地 `DemoSamples.makeDirectionImage()` 和现有动作文档构造规则，不访问网络。`resetForReuse()` 把 action／button 数归零并恢复 callback A；cell／SwiftUI identity 清理 Label 输入的顺序仍以第 4.3／4.4 节为准。

## 5. H1a：测量诊断与 StackView

**单一实施者范围：** `LayoutMeasurementDiagnostics.swift`、`LYGlyphTextLabel.swift`、`HostLayoutTests.swift`。本块不改列表和 Demo 文件。

- [x] **Step 1: 建立 H1a 行为红测试**

在 `HostLayoutTests` 创建下列测试，固定使用 system font、明确宽度和 `displayScale = 2` 的 window／trait：

```swift
func testHorizontalStackAcceptsPromisedAlignmentsAndDistributions()
func testVerticalStackAcceptsPromisedAlignmentsAndDistributions()
func testSiblingButtonAndBothAxisPrioritiesSurviveEveryInputUpdate()
func testStableBoundsConvergeAndRecentTwoWidthsStayCached()
func testZeroPositiveAndNarrowWideNarrowWidthsReturnStableHeights()
func testUIKitAndSwiftUIFiniteWidthHeightsDifferByAtMostOnePixel()
```

StackView helper 使用 `UIWindow(frame:)` 挂载并连续执行四次 `layoutIfNeeded`；每个合法组合断言 `hasAmbiguousLayout == false`、frame 全有限、正宽 Label 的高度与 `sizeThatFits` 差值不超过 0.5 point。优先级用横向 249／751 和纵向 260／752 两组非默认值，在 document、configuration、provider、`reloadAttachments()` 及 cell 风格的清空重绑后逐项保持。

宽度缓存测试按 `nil → 160 → 240 → 160 → 320` 测量：第二次 160 是 cache hit；每步 `cachedLayoutCount <= 2`；稳定 bounds 的额外四轮布局不增加 build 或 invalidation。0→160 和 160→280→160 的末尾高度与首次同宽结果精确到一个物理像素。

- [x] **Step 2: 运行 H1a 红测试并保存真实缺口**

```sh
xcodegen generate --spec Examples/LYGlyphTextDemo/project.yml
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/HostLayoutTests \
  -resultBundlePath .build/verification/h1a-red/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

Expected: named 收敛断言失败；必须保存实际失败摘要。仅有编译错误时，补最小 internal 类型后重跑，直到至少一个失败来自缓存／失效／StackView 行为，不能把类型缺失作为最终红证据。

- [x] **Step 3: 实现只读诊断和单一失效入口**

创建 `LayoutMeasurementSnapshot`。在 Label 内保存两个累计整数，所有组件主动固有尺寸失效改为：

```swift
private func requestIntrinsicSizeInvalidation() {
    intrinsicInvalidationCount &+= 1
    invalidateIntrinsicContentSize()
}

var layoutMeasurementSnapshot: LayoutMeasurementSnapshot {
    .init(
        layoutBuildCount: layoutBuildCount,
        intrinsicInvalidationCount: intrinsicInvalidationCount,
        cachedLayoutCount: cachedLayouts.count
    )
}

func resetLayoutMeasurementCounts() {
    layoutBuildCount = 0
    intrinsicInvalidationCount = 0
}
```

`measuredLayout` 只在 cache miss 后、调用 `text.layout` 前增加 build count。保持 `cachedLayouts.insert(..., at: 0)` 和 `count > 2` 删除末项，不为统计改变缓存键或淘汰政策。相同 `preferredMaxLayoutWidth` 有效值和相同 bounds 宽度不失效。

- [x] **Step 4: 让 StackView 契约通过而不接管宿主**

只修正红测试证明的组件测量或失效问题。不得在 Label 中添加自身宽高约束、调用 `layoutIfNeeded`、调整宿主 StackView 或覆盖宿主 CHCR。若现有实现已经满足布局断言，本步只保留诊断接入，不制造行为改动。

- [x] **Step 5: 运行 H1a 绿测试、既有 Auto Layout 回归和格式检查**

```sh
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/HostLayoutTests \
  -only-testing:LYGlyphTextDemoTests/AutoLayoutTests \
  -resultBundlePath .build/verification/h1a-green/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
LYGLYPHTEXT_SWIFTFORMAT=/Users/kahnli/Desktop/club-circle-workspace/club-circle-ios/.build/tools/swiftformat/0.59.1/build/out/Products/Release/swiftformat \
  scripts/swiftformat.sh --lint \
  Sources/LYGlyphText/UIKit/LayoutMeasurementDiagnostics.swift \
  Sources/LYGlyphText/UIKit/LYGlyphTextLabel.swift \
  Tests/LYGlyphTextTests/HostLayoutTests.swift
git diff --check
```

Expected: 两个 test class 全部通过、非零测试、0 failed／skipped；SwiftFormat 报告 0 个需改文件。

- [x] **Step 6: 冻结 H1a 并依次规格、质量审查**

将本块三个文件 SHA-256、测试 summary 和环境写入 `.build/verification/h1a-green/`。规格审查逐项核对第 4.1／4.2 节和六个 named tests；批准后质量审查检查诊断是否改变缓存行为、计数溢出是否仅使用 wrapping、是否引入布局递归或公开 API。两次批准前不进入 H1b。

## 6. H1b：UITableView 与 UICollectionView

**单一实施者范围：** `HostMatrixSamples.swift`、两个列表控制器、`HostListTests.swift`、`HostMatrixDemoHostTests.swift` 的列表部分。不得改 SwiftUI 页面。

- [x] **Step 1: 建立共用宿主 fixture 和列表红测试**

`HostMatrixSamples` 提供稳定 `rowID`，每种 row 同时保存短／长文档、small／large 图片附件文档、small／large UIView 附件文档及动作回调标识。尺寸变体必须创建新 `LYGlyphTextDocument`，例如图片 20×20→48×64、UIView 44×24→96×52，不修改工厂视图 intrinsic size 冒充排版变化。

`HostListTests` 创建以下测试：

```swift
func testTableAutomaticRowsFitLongShortAndAttachmentSizeReplacements()
func testCollectionSelfSizingUsesAttributesWidthAndMatchesOffscreenMeasurement()
func testOfflineMeasurementAtZeroAndPositiveWidthNeverCallsFactory()
func testTableAndCollectionNarrowWideNarrowBoundsReturnOriginalHeights()
func testListReuseClearsPressedCallbackProviderAndMountedAttachmentState()
func testRepeatedStableListLayoutConvergesWithoutOwningDelegateOrLayout()
```

宿主测试使用 `UIWindow` 和 `0 → 320 → 600 → 240 → 320` bounds 序列；每个正宽连续四轮 layout 后读取所有可见 Label 的 snapshot，额外布局不增加计数。离屏测量同时记录 factory count == 0。列表 dataSource／delegate 和 collection layout 的对象身份在 Label 更新前后保持宿主持有的实例。

- [x] **Step 2: 运行 H1b 红测试**

```sh
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/HostListTests \
  -only-testing:LYGlyphTextDemoTests/HostMatrixDemoHostTests \
  -resultBundlePath .build/verification/h1b-red/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

Expected: Demo 类型缺失后补最小壳并重跑，最终保留至少一个 automatic row／self-sizing／复用状态断言失败作为行为红证据。

- [x] **Step 3: 实现 UITableView 完整约束和重绑顺序**

Table cell 使用四边约束和自动行高；离屏 fitting 时从 `targetSize.width` 扣除左右 inset 得到明确 Label 宽度。重绑顺序固定：

```swift
func prepareForBinding() {
    glyphLabel.onAction = nil
    glyphLabel.document = nil
    glyphLabel.viewProvider = nil
    rowID = nil
    eventCount = 0
}
```

随后一次性安装当前 row 的 callback、document、provider。`prepareForReuse()` 调用同一清理函数。不得固定 cell 高度或让 controller 根据文本内容手算行数。

- [x] **Step 4: 实现 UICollectionView self-sizing 与离屏测量**

Collection cell 的 `preferredLayoutAttributesFitting(_:)` 复制 attributes，以 attributes 宽度作为 required 横向约束：

```swift
let target = CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height)
let fitted = contentView.systemLayoutSizeFitting(
    target,
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
)
attributes.size.height = ceil(fitted.height * scale) / scale
```

宿主使用 estimated item height，并在 bounds 宽度改变时由 controller 的 collection layout 正常 invalidate；Label 不接触 layout object。0 宽先返回有限结果，得到正宽 attributes 后重新计算。

- [x] **Step 5: 运行 H1b 绿测试及附件／动作复用回归**

```sh
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/HostListTests \
  -only-testing:LYGlyphTextDemoTests/HostMatrixDemoHostTests \
  -only-testing:LYGlyphTextDemoTests/ViewAttachmentTests \
  -only-testing:LYGlyphTextDemoTests/ActionInteractionTests \
  -resultBundlePath .build/verification/h1b-green/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

Expected: named tests 全通过、factory 在离屏测量仍为 0、列表稳定轮次计数不增长、既有附件和动作生命周期回归全绿。

- [x] **Step 6: 格式、冻结和两阶段审查**

对本块新增／修改 Swift 文件运行固定 SwiftFormat lint 和 `git diff --check`，在 `.build/verification/h1b-green/` 保存 SHA-256。规格审查核对第 4.3 节所有宽度、附件和复用条件；质量审查重点检查 cell 完整约束、estimated sizing、是否接管 delegate/layout、回调闭包是否强持有 cell/controller，以及 reload／layout invalidation 是否形成循环。

## 7. H1c：SwiftUI 宿主与真实 Demo/UI

**单一实施者范围：** `LYGlyphTextView.swift`、`SwiftUIHostTests.swift`、UIKit／SwiftUI H1 页面、首页入口、H1 UI 测试。不得修改 Core Text Layout 文件。

- [x] **Step 1: 建立 proposal 与 SwiftUI 容器红测试**

`SwiftUIHostTests` 创建：

```swift
func testProposalNilZeroFiniteInfinityAndDisplayHeightUsePureMeasurement()
func testFrameHStackAndVStackMatchUIKitAtTheSameEffectiveWidth()
func testListAndLazyVStackRowsUseStableIdentityAndCurrentDocument()
func testSameDocumentCallbackAndProviderUpdatesDoNotInvalidateLayout()
func testClearReplaceAndDismantleReleasePressedAttachmentAndCallbackState()
```

proposal 直接调用第 4.4 节 internal `measuredSize`，快照前后断言 frame、bounds、constraints、provider 和 factory count 不变。UIHostingController 场景从实际底层 Label 读取最终 bounds 宽度，再用同一 document/configuration 的 UIKit Label 比较高度，容差为 `1 / displayScale`。List／LazyVStack 用 40 个稳定 row ID，首行产生一次 action／button 状态后滚出并复用，当前可见其他 row 必须仍是 0。

- [x] **Step 2: 运行 H1c 红测试**

```sh
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/SwiftUIHostTests \
  -resultBundlePath .build/verification/h1c-red/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

Expected: `measuredSize` 缺失时先补签名并重跑；最终红证据必须来自 proposal／容器／更新／复用行为，而不是未声明类型。

- [x] **Step 3: 抽取纯 proposal 测量函数**

按第 4.4 节实现 `measuredSize`，并让现有协议方法只转发：

```swift
public func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: LYGlyphTextLabel,
    context: Context
) -> CGSize? {
    Self.measuredSize(proposal: proposal, displayHeight: displayHeight, label: uiView)
}
```

保持 `apply` 顺序为 callback → configuration → document → provider；不改变 public init 参数、默认值或拆卸事务。

- [x] **Step 4: 建立 UIKit／SwiftUI H1 可操作页面**

UIKit 页提供 StackView alignment／distribution、160／240／320／容器宽度、短／长／图片／UIView／动作、Table／Collection 入口。SwiftUI 页提供 `.frame`／HStack／VStack／List／LazyVStack 模式和同样的内容／宽度选择。两端都显示当前 row ID、自然高度、事件数、按钮数和 callback A／B；状态文本使用稳定 accessibility identifier。

真实动作目标继续使用 Debug 下现有 `ActionDiagnosticOverlay`／`ActionDiagnosticProbe` 从实际 Layout 几何导出坐标，不增加 public 或 SPI 几何接口。原生 UIButton 直接接受真实点击。UI 页面不显示内部缓存、测试说明、快捷键或实现细节。

- [x] **Step 5: 建立并运行真实 H1 UI 矩阵**

`HostMatrixUITests` 创建：

```swift
func testUIKitStackWidthsTableAndCollectionReuse()
func testSwiftUIFrameStacksListAndLazyVStackReuse()
func testBothHostsKeepNativeButtonAndActionStateWithCurrentRow()
```

每项实际点击宽度、容器和内容控件；UITableView、UICollectionView、List、LazyVStack 分别滚出首行再返回。验证原生按钮只改变当前 row，文字动作只调用当前 callback B，旧 row pressed/event 状态不出现在复用 row。宽度序列至少包含 160→320→160，并在每端保存窄、宽、列表滚动后、返回首行四类截图。

```sh
xcodebuild test \
  -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
  -scheme LYGlyphTextDemo \
  -destination 'platform=iOS Simulator,id=5260ADE6-ADC2-44AA-9EEB-CDEC90196D08' \
  -derivedDataPath .build/DemoDerivedData \
  -parallel-testing-enabled NO \
  -only-testing:LYGlyphTextDemoTests/SwiftUIHostTests \
  -only-testing:LYGlyphTextDemoTests/HostMatrixDemoHostTests \
  -only-testing:LYGlyphTextDemoUITests/HostMatrixUITests \
  -resultBundlePath .build/verification/h1c-ui-green/Tests.xcresult \
  SWIFT_VERSION=6 CODE_SIGNING_ALLOWED=NO
```

Expected: 宿主和 UI 测试均为非零并全绿；截图非空，UIKit／SwiftUI 对应宽度没有文本或按钮重叠，滚动返回后 row 标识、按钮数和事件数正确。

- [x] **Step 6: 冻结并依次规格、质量审查**

固定 SwiftFormat lint 本块全部 Swift 文件，保存 SHA-256、test summary、xcresult attachments manifest 和实际截图检查结论。规格审查核对第 4.4 节、五种 SwiftUI 容器／proposal 及三项 UI 测试；批准后质量审查检查稳定 identity、闭包释放、provider 复用、UI 测试是否真正操作而非直接调用回调，以及 Demo 是否引入不可见调试行为。

## 8. H1d：正式回归、文档与交付

**单一实施者范围：** README、验证记录、两份路线图；只修复最终审查发现的 H1 文件，不扩大到 A1/P1。

- [x] **Step 1: 运行正式 docs、format、build 与完整测试**

开始前用 `xcrun simctl list devices available --json` 确认 `5260ADE6-ADC2-44AA-9EEB-CDEC90196D08` 可用且未被其他任务占用。串行执行：

```sh
scripts/verify.sh docs
LYGLYPHTEXT_SWIFTFORMAT=/Users/kahnli/Desktop/club-circle-workspace/club-circle-ios/.build/tools/swiftformat/0.59.1/build/out/Products/Release/swiftformat scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08
git diff --check
```

Expected: docs、format、Package/Demo Swift 6 mode build 与 shared scheme 完整测试全部通过；`test-summary.json` 的 totalTestCount、宿主数、UI 数均大于 0，0 failed／skipped／expected failures，runtime warnings 单独核查。本任务仅使用上述独占 UDID；若设备被占用，停止相关测试并核实归属，不切换或接管其他任务的设备。

- [x] **Step 2: 人工检查截图和状态对应关系**

从正式 xcresult 导出全部 H1 screenshot attachments，生成文件名／尺寸／SHA-256 manifest。逐张检查：窄宽切换后内容完整或按契约截断；横纵 StackView 无重叠；Table／Collection／List／LazyVStack 当前 row 正确；原生按钮和文字动作状态未串行；图片方向与 UIView 外框正确。至少将 UIKit 窄／宽／列表复用和 SwiftUI 窄／宽／列表复用六张最终图保存到 `docs/verification/images/host-matrix-*.png`。

- [x] **Step 3: 更新真实证据文档**

创建 `docs/verification/2026-10-21-host-matrix.md`，记录基线、最终提交候选、Xcode／Swift、Simulator runtime／UDID、所有红／绿 result bundle、正式命令、真实宿主／UI 测试数量、计数断言、截图路径、规格／质量审查结论。README 只写已通过的宿主能力和宿主提供宽度／完整约束责任。

总计划只有在正式证据通过后才勾选阶段 6 的 H1 项，并将 H1 队列状态更新为“功能已验收，待交付”，实际提交／集成／推送另按 Step 5 留证；Dynamic Type／暗黑／环境 RTL／VoiceOver 仍未勾选。连续计划把当前阶段推进到 A1。Swift 6.0 编译器、iOS 16 实际运行、真机、人工 VoiceOver、固定负载性能和 Instruments 保持“未验证”。

- [x] **Step 4: 最终跨块规格审查，再做质量审查**

规格审查按本计划第 1 节逐项映射到 named test、Demo 操作、正式结果和截图。质量审查检查公共 API diff 为空、Core Text 仍为唯一内核、缓存上限两项、诊断不持有对象、不形成 layout loop、列表与 SwiftUI 生命周期无泄漏。发现问题回对应块原实施者修复；修复触及 Swift 时重跑定向测试、format、build 和完整 test，并重新冻结。

- [ ] **Step 5: 中文提交、锁内快进、普通 push 与清理**

只暂存本计划列出的 H1 文件和已检查截图：

```sh
git add README.md Sources/LYGlyphText Tests/LYGlyphTextTests \
  Examples/LYGlyphTextDemo/LYGlyphTextDemo \
  Examples/LYGlyphTextDemo/LYGlyphTextDemoTests \
  Examples/LYGlyphTextDemo/LYGlyphTextDemoUITests \
  docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md \
  docs/superpowers/plans/2026-10-20-continuous-development.md \
  docs/superpowers/plans/2026-10-21-host-matrix.md \
  docs/verification/2026-10-21-host-matrix.md \
  docs/verification/images/host-matrix-*.png
git diff --cached --check
git commit -m 'feat: 完成宿主布局与列表适配矩阵'
bash .build/integrate-task.sh codex/host-matrix 003558cd7c72116fcb889162ccf8ecd232e5ec70
```

集成脚本必须在锁内确认 main 仍为固定基线、feature 为快进候选、工作区干净、origin 指向本仓库；随后 fast-forward 本地 main、普通 push 一次并核对远端 SHA。push 失败保留本地合入并报告，不自动 pull／rebase／force-push。只有 feature tip 已由 main 持有且工作区无未知文件时才用 `git branch -d` 清理本任务分支。成功后按连续队列进入 A1，不创建 PR、Tag 或 Release。

## 9. 完成门槛与自审映射

H1 只有同时满足以下条件才完成：

- StackView 所有承诺 alignment／distribution 有宿主测试，并排按钮和两轴 CHCR 更新不重置；first／last baseline 排除边界保持清楚。
- UITableView 自动行高、UICollectionView self-sizing／离屏测量覆盖长短文、两类附件尺寸替换和完整宽度序列，组件未接管列表 delegate/layout。
- `.frame`、HStack、VStack、List、LazyVStack 及 nil／0／有限／无限 proposal 有行为证据；callback／provider／文档更新和 dismantle 不残留旧状态。
- 稳定输入的 build／invalidation 计数收敛，任何时刻 cache count ≤ 2；宽度往返高度可重复。
- UIKit／SwiftUI 同文档同宽高度差 ≤ 1 物理像素。
- 真实 UI 操作宽度、滚动复用、原生按钮和文字动作；最终截图已导出并逐张检查。
- docs、固定 format、Swift 6 mode build、完整 shared scheme 非零测试均通过，规格审查后质量审查批准。
- A1 和 P1 范围没有被提前标记完成；缺失环境逐项保留未验证。

计划自审映射：总计划 4.2.1／4.2.2 对应 H1a；4.2.3 对应 H1a／H1b；4.2.4 对应 H1c；阶段 6 的 StackView、列表、SwiftUI 容器和复用对应 H1a—H1c；第 6 节矩阵的约束、离屏、StackView、列表、宽度收敛和 SwiftUI 行对应 named tests 与 H1d 正式回归。计划未使用未定义的公开类型；internal 类型和函数均在第 4 节给出唯一签名。
