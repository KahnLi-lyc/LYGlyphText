# M1 分段、动作与完整样式 Implementation Plan

> **For agentic workers:** 使用 executing-plans 按本计划顺序实施。步骤使用 checkbox；连续开发已获授权，不增加任务间许可检查点。M1a、M1b 各自完成失败测试、实现、验证、记录、提交、集成与普通推送后，立即进入下一项。计划中的目标不表示功能已实现或验证。

**Goal:** 在保持 V1 API 兼容的前提下，先交付安全的分段／动作文档，再交付装饰样式、完整段落值、换行配置及统一展示几何，为 I1 提供稳定输入。

**Architecture:** Document 在 MainActor 将文本、动作和支持的样式复制为不可变值；不持有 UIView、工厂或业务闭包。Core Text 仍为唯一排版内核。最终可见行的原文映射同时服务背景、删除线、附件和后续动作几何；展示偏移不改变测量结果。分成 M1a 与 M1b 两个可独立验证、集成的交付，不发布只有声明的功能。

**Tech Stack:** iOS 16+、Swift tools 6.0、Swift 6 language mode、UIKit、SwiftUI、Core Text、Core Graphics、XCTest；零第三方运行依赖。

---

## 0. 队列、边界与兼容

- 前置：V1 已通过其专项验收并完成集成；先读取其实际验证记录，不能用历史 72 项基线代替最新 V1 结果。
- 将总队列 M1 细化为 **M1a 文档分段／动作／范围** → **M1b 样式／换行／统一展示几何**。I1 依赖 M1b。
- M1a 完成后：业务可构造带动作的文档，但 Label 不发送动作、不显示按下态；README 如实说明输入已支持、交互待 I1。
- M1b 完成后：所有本计划列出的样式可真实绘制；几何有行为测试，但 tap／longPress／取消、onAction 和动作无障碍激活仍由 I1／A1 交付。
- 保留现有 `LYGlyphTextAttachment`、`LYGlyphTextViewAttachment` 和 provider 的类型及初始化语义；不把图片／视图描述改为联合类型。
- 不新增 result builder、文本解析器、选择复制、任意样式字典高亮、View 工厂进入 Document、独立 SwiftUI 排版或公开 Layout API。
- 公开 API 使用简体中文 DocC；源代码与测试遵守 AGENTS、CODING_STYLE、CONTRIBUTING。各交付只提交自身文件。

## 1. 文件职责

M1a：

- 新建 `Sources/LYGlyphText/Document/LYGlyphTextAction.swift`：动作值和两种按下颜色。
- 新建 `Sources/LYGlyphText/Document/LYGlyphTextSegment.swift`：文本／图片／视图段输入。
- 修改 `Sources/LYGlyphText/Document/LYGlyphTextDocument.swift`：追加 actions 入口、分段拼接、错误、统一校验与内部动作数组。
- 新建 `Tests/LYGlyphTextTests/SegmentTests.swift` 与 `Tests/LYGlyphTextTests/ActionTests.swift`；扩展 `DocumentTests.swift`。

M1b：

- 修改 `Sources/LYGlyphText/Document/LYGlyphTextDocument.swift`：样式快照和段落规范化。
- 新建 `Sources/LYGlyphText/Document/ParagraphStyle.swift`：internal 段落值快照；不保留 NSParagraphStyle。
- 修改 `Sources/LYGlyphText/Document/LYGlyphTextConfiguration.swift`：嵌套枚举与默认配置。
- 修改 `Sources/LYGlyphText/Layout/LYGlyphTextLayout.swift`、`TailTruncation.swift`：Core Text 映射、段落上下文、测量与可见行。
- 新建 `Sources/LYGlyphText/Layout/VisibleTextFragments.swift`：内部视觉片段／源范围查询，只消费最终 CTLine。
- 新建 `Sources/LYGlyphText/Layout/TextDecorations.swift`：背景和删除线绘制；不管理业务状态。
- 修改 `Sources/LYGlyphText/UIKit/LYGlyphTextLabel.swift`：统一展示偏移、裁切与附件位置。
- 修改 `Sources/LYGlyphText/SwiftUI/LYGlyphTextView.swift`：仅在实际接口消费需要时调整；继续复用 Label。
- 新建 `Tests/LYGlyphTextTests/StyleTests.swift`、`DecorationDrawingTests.swift`、`TextGeometryTests.swift`；扩展 `LayoutTests.swift`、`TruncationTests.swift`、`ViewAttachmentTests.swift` 和直接宿主测试。
- 修改 `Examples/LYGlyphTextDemo/LYGlyphTextDemo/DemoSamples.swift`、`UIKitDemoController.swift`、`SwiftUIDemoView.swift`：共用一份 M1 样例、展示装饰和配置，不增加未实现的交互入口。

两个交付分别更新 README、总计划队列及自己的 `docs/verification/2026-10-20-m1a-document.md`、`2026-10-20-m1b-styles.md`；发布日期变化时使用实际日期，不保留虚假的日期。

## 2. M1a 精确公开接口

```swift
@MainActor
public struct LYGlyphTextPressedStyle {
    public let foregroundColor: UIColor?
    public let backgroundColor: UIColor?

    public init(
        foregroundColor: UIColor? = nil,
        backgroundColor: UIColor? = .tertiarySystemFill
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

@MainActor
public struct LYGlyphTextAction {
    public let actionID: String
    public let range: NSRange
    public let pressedStyle: LYGlyphTextPressedStyle

    public init(
        actionID: String,
        range: NSRange,
        pressedStyle: LYGlyphTextPressedStyle = .init()
    ) {
        self.actionID = actionID
        self.range = range
        self.pressedStyle = pressedStyle
    }
}

@MainActor
public enum LYGlyphTextSegment {
    case text(
        NSAttributedString,
        actionID: String? = nil,
        pressedStyle: LYGlyphTextPressedStyle
    )
    case image(
        LYGlyphTextAttachment,
        attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil,
        pressedStyle: LYGlyphTextPressedStyle
    )
    case view(
        LYGlyphTextViewAttachment,
        attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil,
        pressedStyle: LYGlyphTextPressedStyle
    )

    public static func text(_ value: NSAttributedString, actionID: String? = nil) -> Self
    public static func image(
        _ value: LYGlyphTextAttachment,
        attributes: [NSAttributedString.Key: Any] = [:], actionID: String? = nil
    ) -> Self
    public static func view(
        _ value: LYGlyphTextViewAttachment,
        attributes: [NSAttributedString.Key: Any] = [:], actionID: String? = nil
    ) -> Self
}
```

上述 static 工厂在 MainActor 内以 `.init()` 提供默认 pressedStyle，调用者仍可使用 `.text(text)`、`.image(attachment)` 或显式 pressedStyle，switch 仍匹配相同三种 case。实际 Swift 6 宿主编译已确认：enum case 的默认参数不继承 enum 的 MainActor，上述 `.init()` 不能直接写成 case 默认值；case 本身也不允许加全局 actor。使用同名便利重载保持调用语法与隔离，不使用并发逃生标记。

在已有 Document 入口末尾追加默认参数，源调用兼容：

```swift
public init(
    attributedText: NSAttributedString,
    attachments: [Int: LYGlyphTextAttachment] = [:],
    viewAttachments: [Int: LYGlyphTextViewAttachment] = [:],
    actions: [LYGlyphTextAction] = []
) throws

public convenience init(segments: [LYGlyphTextSegment]) throws
```

契约：

- 所有 range／location 是最终拼接原文的 UTF-16 单位。Document 内部增加只读 `let actions: [LYGlyphTextAction]`，不额外公开文本／布局访问器。
- 动作描述初始化只赋值；Document 结合完整原文校验，因此可通过同一个 throwing 入口给出明确错误。
- 按下样式只包含颜色。nil 表示继承普通显示值；背景默认 tertiarySystemFill。M1a 保存 UIColor，不预先解析 trait；M1b 也不将其固化为某一个模式的颜色。没有字体、kern、baseline、段落或回调参数。
- Segment 是输入描述，允许暂时引用调用方的 NSAttributedString；**快照时点是 Document 初始化**。Document 不保留 Segment／属性字典／输入 attributed string。
- image／view 的 attributes 作用于自动插入的单个 U+FFFC，支持与 attributedText 入口相同的样式白名单。M1a 仅已有字体／颜色／基本段落能力实际生效；M1b 扩充白名单。缺省 font／color 使用动态 body／label，不隐式继承相邻段。
- 每个带 actionID 的段产生一个独立动作；同 ID 相邻段也不合并。需要跨多个文本／附件段的单个动作时，使用 attributedText＋actions 入口；不增加分组 DSL。
- 空的无动作文本段允许并忽略；带 actionID 的空文本段生成零长度范围并由统一入口报错。空 segments 构造空文档。
- 文本段里的裸 U+FFFC、标准 attachment 属性仍被拒绝；构建器不尝试猜测它属于哪个附件。
- 图片／视图共享 ID 唯一性与位置校验。builder 自动生成的位置也必须经过 V1 校验，避免附件与相邻 combining mark 组合成不独立的 U+FFFC。
- 重复 actionID **允许**；空字符串 ID 不允许。ID 是 opaque 标识，使用 `isEmpty`，不 trim、不做大小写归一化。内部动作身份使用数组下标＋文档身份，不能用 ID 作唯一字典键。

### 2.1 M1a 新错误与失败优先级

```swift
case emptyActionID(range: NSRange)
case invalidActionRange(range: NSRange)
case actionRangeSplitsComposedCharacter(range: NSRange)
case overlappingActionRanges(first: NSRange, second: NSRange)
```

保留所有 V1 错误，且现有附件错误的校验顺序不变。附件通过后，先按输入顺序逐个检查动作：ID → 数值范围 → 字符边界。全部合法后按 location 稳定排序检查重叠，遇到第一个相邻冲突返回其两个范围。Document 内部保存输入顺序；排序副本只用于检测。

安全范围判断不得先调用 NSMaxRange：

```swift
func isValidActionRange(_ range: NSRange, length: Int) -> Bool {
    range.location >= 0 && range.length > 0
        && range.location <= length
        && range.length <= length - range.location
}

func validateBoundaries(
    _ range: NSRange, in string: String, characterBoundaries: Set<String.Index>
) -> Bool {
    guard let converted = Range(range, in: string),
          characterBoundaries.contains(converted.lowerBound),
          characterBoundaries.contains(converted.upperBound) else { return false }
    return (string as NSString).rangeOfComposedCharacterSequences(for: range) == range
}
```

仅当存在动作时，为完整字符串一次建立 `Set(string.indices)` 并插入 endIndex。当前实际 runtime 的 Range 转换及 NSString composed 检查允许 CRLF 两侧的半段，不能单独依赖它们；显式 Swift Character 边界确保 CRLF 也不可拆开。边界集合复用于每个动作，不按动作重复遍历全文。

- NSNotFound、负数、零长度、越界、Int.max 长度统一为 invalidActionRange；数值检查之后转换失败或扩展组合字符范围后不相等，统一为 actionRangeSplitsComposedCharacter。
- 重叠使用半开区间：`first.location + first.length > second.location` 才失败。相邻通过；包含、同范围或不同 ID 相交均失败。
- 必须在完整拼接字符串检查边界；`"e"` 动作段随后追加 `"\u{301}"` 时拒绝，不能仅验证单段。
- 常规 attributedText 的样式范围允许切开组合字符，不能套用动作的额外限制。
- 不新增自定义 String.Index API。公开示例使用系统 `NSRange(swiftRange, in: originalText)`；Document 始终再次校验。

## 3. M1a 实施与测试顺序

### Task A1：动作范围与错误

**文件：** `LYGlyphTextAction.swift`、`LYGlyphTextDocument.swift`、`ActionTests.swift`。

- [x] 先添加以下编译失败的最小测试，再补 API 到可编译，让失败转为实际行为缺口。不要将最终只证明“类型不存在”的失败当作行为复现。

```swift
func testRepeatedActionIDKeepsTwoDistinctAdjacentRanges() throws {
    let actions = [
        LYGlyphTextAction(actionID: "same", range: NSRange(location: 0, length: 1)),
        LYGlyphTextAction(actionID: "same", range: NSRange(location: 1, length: 1))
    ]
    let document = try LYGlyphTextDocument(
        attributedText: NSAttributedString(string: "fi"), actions: actions
    )
    XCTAssertEqual(document.actions.map(\.range), actions.map(\.range))
    XCTAssertEqual(document.actions.map(\.actionID), ["same", "same"])
}

func testActionCannotSplitComposedCharacter() {
    XCTAssertThrowsError(try LYGlyphTextDocument(
        attributedText: NSAttributedString(string: "e\u{301}"),
        actions: [.init(actionID: "accent", range: NSRange(location: 0, length: 1))]
    )) {
        XCTAssertEqual(
            $0 as? LYGlyphTextDocumentError,
            .actionRangeSplitsComposedCharacter(range: NSRange(location: 0, length: 1))
        )
    }
}
```

- [x] 将表格用例加入 ActionTests：空 ID、NSNotFound、负 location／length、length 0、location 超过文末、Int.max location／length、文末零范围；有效完整 UTF-16 范围；surrogate pair、家庭 emoji、肤色、旗帜、组合重音、CRLF 中间边界；相邻、相交、包含、同范围；同 ID 非相邻通过。
- [x] 用 CONTRIBUTING 的宿主测试入口运行目标类，核对实际失败断言与非零测试数。
- [x] 加入接口、内部数组与上节数值／字符边界算法；不改 Label 交互。
- [x] 在 Swift 6 language mode 的宿主编译中实际消费三种 enum case 的所有默认参数、显式 pressedStyle，以及两个 Document 初始化入口；确认 MainActor 初始化默认值及 enum associated-value 默认表达式可用。仅主线程 XCTest 调用，不通过并发逃生标记绕过诊断。
- [x] 运行目标类和 DocumentTests／AttachmentTests／ViewAttachmentTests，核对新的范围校验不改变附件错误。

### Task A2：分段拼接与快照

**文件：** `LYGlyphTextSegment.swift`、`LYGlyphTextDocument.swift`、`SegmentTests.swift`、`DocumentTests.swift`。

- [x] 写混合 fixture：`"😀"`、图片、`"e\u{301}"`、视图。预期 string 为 `"😀\u{FFFC}e\u{301}\u{FFFC}"`，附件位置分别 2／5，动作范围分别按 2／1／2／1 UTF-16 长度累计。图片和 view 各带相同 actionID，确认仍为两个独立范围。
- [x] 写空输入、带动作空段、跨段组合字符、裸 U+FFFC、重复图片／视图附件 ID、附件与 combining mark 的失败测试。
- [x] 写 mutable 输入回归：先创建 Segment，再在 Document 初始化前修改输入，Document 应使用初始化时内容；Document 构造后再次修改原文本和 NSMutableParagraphStyle，已构造文档保持原值。
- [x] 确认测试在现有 API／缺失构建逻辑下失败；实现拼接时使用 `NSMutableAttributedString.length` 获取起点，图片／view 各 append 单个 U+FFFC，收集独立 action，然后调用统一 designated initializer。
- [x] 起点直接读取拼接器当前 UTF-16 length，append 后用新旧 length 形成范围；不额外维护另一个累计计数器。手写 action range 的加法只在上节数值边界验证成功后执行，不添加不可实际分配的巨量字符串测试或额外溢出 API。
- [x] 运行 A1／A2 与已有 Document／附件目标回归，确认没有 UIView 创建／provider 调用。

### Task A3：M1a 交付

- [x] 在至少一组共用样例中用 segments 构造已有图片或 view 内容，保持可见文本和声明几何；emoji 前缀的 UTF-16 累计由 SegmentTests 与直接消费者验证。仅替换构造方式，不增加交互假按钮或宣称动作已经可点击。
- [x] 更新实际 API 文档、总队列 M1a 状态与专项验证记录。保留 M1b／I1 未完成状态。
- [x] 运行第 9 节 M1a 检查：127／127 Passed，docs／format／build 通过；提交／集成／推送状态见总队列及专项记录。
- [ ] 完成后自动执行 M1b，不请求继续许可。

## 4. M1b 样式快照与段落规范化

### 4.1 支持白名单与缺省值

Document 不存原属性字典。StyleRun 保存下表类型的 `let` 字段；除 font／UIColor 这些语义 UIKit 值外，不保留可变 Foundation 属性对象。

| 输入 NSAttributedString.Key | 快照字段类型／缺省值 | 解析／绘制 |
| --- | --- | --- |
| font | UIFont?／nil | nil 按当前 trait 取 preferred body；显式 font 保持固定 |
| foregroundColor | UIColor?／nil | nil 为 label；resolve 当前 trait 后转 CGColor |
| backgroundColor | UIColor?／nil | nil 不绘制；显式色按 trait resolve，自绘背景 |
| kern | CGFloat?／nil | nil 省略 CT key，保持字体标准 kerning；显式有限 0／正／负值完整保留 |
| baselineOffset | CGFloat／0 | Core Text baseline offset，有限正负值均接受 |
| underlineStyle | Int／0 | NSUnderlineStyle 原始值；经像素验证的 Core Text bits 原生绘制，byWord 见第 7 节回退 |
| underlineColor | UIColor?／nil | nil 继承 resolved foreground |
| strikethroughStyle | Int／0 | 同样的标准 style 位值，自绘删除线 |
| strikethroughColor | UIColor?／nil | nil 继承 resolved foreground |
| ligature | Int／1 | 0／1／2；交给 Core Text shaping，不因动作边界禁用 |
| paragraphStyle | internal ParagraphStyle 值 | 下节所有值；不保留 NSParagraphStyle 引用 |

支持 underline／strike 的 base 为 none(0)、single(1)、thick(2)、double(9)，pattern 为 solid、dot、dash、dashDot、dashDotDot，并接受 byWord。只允许这些标准位组合；style 为 none 时其他 pattern 不产生线。不要在文档中声称支持任意未知 style bits。

对已有 font／foregroundColor 的类型处理保持兼容：不匹配类型视为缺省。新增颜色键同样只接受 UIColor，不匹配类型视为缺省。未知 key 忽略且不保留，不因此宣称支持 shadow、stroke、URL、writingDirection override、tabs、hyphenation 或自定义属性渲染。

不增加泛化样式错误枚举。新增数值键不是 NSNumber／可桥接数值时忽略，使用字段缺省值；NaN／正负 infinity 也规范化为字段缺省值。有限负 kern／baselineOffset 完整保留，不能按尺寸规则归零。**kern 缺省为 nil 而不是 0**：Core Text 中省略 key 才保留字体标准 kerning，显式 0 会禁用 kerning。非法／非有限 kern 因此变为 nil 并省略 key；显式有限 0 仍传入。ligature 非整数或不在 0／1／2 时使用 1；underline／strike 非整数、未知 base／pattern／bits 使用 0。数值转换先检查有限与取值范围，不能直接把 Int.max 之外的浮点数转换成 Int。

Document 顺序仍为 V1 附件校验 → M1a actions 校验 → paragraph 与字符样式的值规范化；前两项保持 throwing 错误，样式规范化不改变错误集合。所有本计划新支持数值为 typed Swift 值；不可将 NSNumber／NSMutableParagraphStyle 原样存入快照。规范化发生在快照时，传入 Core Text 的所有数值必须有限，调用方之后修改原输入不改变该结果。

### 4.2 极大有限值与派生几何保护

仅检查输入 `.isFinite` 不足以保证 Core Text 安全：有限 kern 与字符数相乘、lineHeightMultiple 与字体高度相乘，以及 inset／baseline／缩进的加减可能溢出，CGFloat 有限也可能超出 Core Text 内部浮点的有限范围。下述保护属于内部数值安全，不新增公共错误／样式范围 API，也不把正常的正负样式统一截断到某个屏幕尺寸。

- 保留原快照的普通合法值。ResolvedText 在进入 CTParagraphStyleCreate、CTFramesetter／CTLineCreate 前做数值 preflight：检查 CGFloat 值到 Float 的有限表示、并以 checked-finite 加减乘分别检查本次文本长度／字体度量下的最坏 kern advance、baseline 上下界、lineHeightMultiple×自然行高、段距×潜在行数、head／tail 区域和 path 尺寸。运算结果不有限或不能保持所需有限表示时，将**参与溢出的极端可选样式**归回其系统缺省值，然后重新计算；kern 归 nil，其他新增距离／倍数归 0。绝不能先把溢出值传入 Core Text 再依靠返回值补救。
- 对超大但上述相乘尚未溢出的值也运行 extreme-finite 测试；若平台 Core Text 在该输入下产生无效度量，在其调用前沿用同一内部安全检查缩小允许的计算包络，将导致该无效度量的极端值归缺省。安全包络与理由必须由失败测试留证，不得用 blanket clamp 改写普通 font／spacing／负缩进或用另一个任意样式值取代输入。
- 所有派生 geometry 运算均先检查再存储：CTFramesetterSuggestFrameSizeWithConstraints 返回 size、frame height、CTLine typographic bounds、baseline、glyph positions／advances、source fragment rect、尾行区域、垂直 offset 和像素取整前后的值都必须有限。拒绝将 NaN／infinity 存入缓存、CGRect、CGPath 或 CGContext。`ceil(value * scale)` 先检查乘积，不能以结果 `.isFinite` 代替乘前保护。
- 若 Core Text 仍返回无效度量，最多重试一次使用这些新增可选度量样式缺省值的 resolved 输入；不改变原 Document、不创建 view、不进入循环。仍无有效度量的行不产生字形／附件／动作片段；输出使用已知有限的容器／inset 安全尺寸，不能泄露非有限结果。记录这一技术异常的测试，不将无效原输出宣称为成功布局。
- 样式无效值处理继续为缺省规范化，没有 invalidStyleValue 或其他 broad throwing API。普通有限正负 kern／baseline／spacing／head／firstLine／tail 必须通过保留原值和行为回归，不能因极值保护而被夹紧。

### 4.3 ParagraphStyle 的确切值

internal `ParagraphStyle` 为 MainActor 内使用的 struct，其字段全部 `let`：

```swift
struct ParagraphStyle {
    let alignment: NSTextAlignment
    let writingDirection: NSWritingDirection
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let paragraphSpacingBefore: CGFloat
    let firstLineHeadIndent: CGFloat
    let headIndent: CGFloat
    let tailIndent: CGFloat
    let minimumLineHeight: CGFloat
    let maximumLineHeight: CGFloat
    let lineHeightMultiple: CGFloat
}
```

- 缺省 alignment／direction 为 natural，其余为 0；0 maximumLineHeight 表示不限制，0 lineHeightMultiple 表示自然值。
- 每个数值先检查有限；NaN／正负 infinity 规范化为 0。lineSpacing、paragraphSpacing、paragraphSpacingBefore、firstLineHeadIndent、headIndent、tailIndent 的有限正负值完整保留，支持紧密排版、悬挂缩进及 outdent，不扩大为本组件额外的数值限制。minimumLineHeight、maximumLineHeight、lineHeightMultiple 的有限负值规范化为系统缺省 0。所有源坐标即使超出内容区域仍保留，实际显示服从统一 contentClip。
- maximumLineHeight 非零但小于 minimumLineHeight 时将 maximumLineHeight 规范化为 0（系统缺省、不设上限），保留 minimumLineHeight；此确定性行为写入公开文档。不抛新错误，也不通过交换 min／max 猜测意图。显式 maximumLineHeight 小于字形／附件自然高度但不与 minimumLineHeight 矛盾时，按 Core Text 语义允许内容重叠，不偷偷扩大配置。
- 使用 NSString paragraphRange 按完整逻辑段落规范化。每段首 UTF-16 字符位置的 NSParagraphStyle 决定该段所有值；后续 run 中不同段落 style 不覆盖首字符。空文档没有段落；CRLF 视为段落分隔符整体，尾随换行产生的显示空行继承结束分隔符所属段落值。
- 文本属性 run 必须在规范化 paragraph 边界进一步切分，以使每个 run 引用正确的 ParagraphStyle 值；不能仅按 enumerateAttributes 的原始分段保存段落。
- 不能只调用 `paragraph.copy()` 并保存结果。构造后修改调用方 mutable text、paragraph、颜色属性所在范围，都不得改变已构造文档的输入值。
- Core Text `.lineSpacing` spec 已弃用；映射到 `.lineSpacingAdjustment`。其余分别映射 alignment、baseWritingDirection、firstLineHeadIndent、headIndent、tailIndent、paragraphSpacing／Before、minimum／maximumLineHeight、lineHeightMultiple。
- CTParagraphStyleCreate 必须在值指针有效的作用域内调用，函数复制后指针不逃逸；不保存临时裸指针。

## 5. M1b 配置与统一展示坐标

```swift
public struct LYGlyphTextConfiguration: Equatable {
    public enum Wrapping: Equatable { case word, character }
    public enum VerticalAlignment: Equatable { case top, center, bottom }

    public var textContainerInset: UIEdgeInsets
    public var numberOfLines: Int
    public var wrapping: Wrapping
    public var verticalAlignment: VerticalAlignment

    public init(
        textContainerInset: UIEdgeInsets = .zero,
        numberOfLines: Int = 0,
        wrapping: Wrapping = .word,
        verticalAlignment: VerticalAlignment = .top
    ) {
        self.textContainerInset = textContainerInset
        self.numberOfLines = numberOfLines
        self.wrapping = wrapping
        self.verticalAlignment = verticalAlignment
    }
}
```

- 保持 inset 非有限／负值归零、numberOfLines 负值按无限行的已有语义。configuration.wrapping **统一覆盖**输入 paragraph.lineBreakMode，避免两套换行配置互相竞争。只提供 word／character；行数超限仍只尾部省略。
- wrapping 传入 ResolvedText 创建 CTParagraphStyle 的过程，配置变更清除该 label 的 resolved input 与最多两份宽度缓存。垂直对齐无需重排，但允许沿用配置变更统一失效的简单路径；不新增全局缓存。
- 垂直对齐只影响展示，不影响 intrinsicContentSize、sizeThatFits、systemLayoutSizeFitting 或 SwiftUI proposal 测量。
- `extra = max(0, bounds.height - measuredLayout.size.height)`；top／center／bottom 的 y 偏移分别 0／extra÷2／extra。measured size 已包含上下 inset，因此不得再次扣除 inset。内容更高时偏移固定 0，继续顶部裁切。
- 归一化布局仍以容器左上角为原点、已含 inset；展示变换为 `bounds.origin + CGPoint(x: 0, y: offset)`，应用一次。Label 的内容裁切区固定为 bounds 内扣 inset 的矩形，不跟着文字向下移动。
- 绘制背景／字形／删除线／图片、V1 的可见 view 过滤和 view 容器 frame、未来动作／无障碍矩形使用同一个 internal 展示变换。测量不安装 view；offset 不能反向反馈到文档或附件尺寸。
- 部分可见附件与装饰只在固定 contentClip 内显示／响应。I1 命中前也必须将片段变换后与 clip 相交。

## 6. 段落、尾部省略与最终原文映射

### 6.1 原文方向及有效尾行宽度

- 保留现有 `Line.visibleSourceRanges`、`sourceOffset`、`truncationTokenRange`，并且所有新几何只读取**最终存入 Layout 的 CTLine**。
- TailTruncation 不能再创建仅含 alignment／direction 的 CTParagraphStyle。它要从规范化 ParagraphStyle 的完整值生成样式，只将 natural writingDirection 固定为完整原段落解析出的方向。
- natural 方向必须由完整原逻辑段落解析，隐藏首 strong 字符不得改变尾行方向。方向探测若暂时改 alignment 为 natural，其他段落值保持；如缩进影响探测的 x，应将缩进扣除或用纯方向探测副本固定零缩进，不能用“origin.x > 1”把缩进误判成 RTL。
- 判断最后一条可见行是否为逻辑段落首行，使用其原文起点与原 paragraph 范围比较，不以截断子串起点当作首行。
- 尾行排版区域按方向及首／续行 headIndent、tailIndent 计算。leading 端取 firstLineHeadIndent 或 headIndent；tailIndent > 0 表示距离 leading 的终点，否则表示距 trailing 的终点；有效宽度不得小于 0。RTL 将同一 leading 坐标区间镜像到容器。
- token 的容量和 flush 都用这个有效区域；最终 baseline.x 是内容 inset＋区域物理起点＋区域内 flush。不能直接用整 contentWidth 或原行 baseline.x 作为区域左边界。
- 生成的省略号只继承该尾行首位置的字体／前景色及固定方向／完整段落值，沿用当前 token 继承规则；不继承动作、附件 delegate、位置标记、背景、kern、baseline、underline、strike 或业务属性。
- 继续按原字符簇边界收缩逻辑尾部并重新 shaping；保留真实原文 `…` 与生成 token 的区别。token 无法容纳时不绘制 token／源字形，保持已有空尾行度量语义。

### 6.2 修正截断高度，不将续行改成新段落

现有 truncatedLines 把上一软换行行拼成普通 `\n` 后只测两行；新增段前后距、首行缩进及行高后不正确。实施时使用完整可见上下文的**度量副本**：

1. 保留原先所有可见行及其 CTLine；只替换最后一行的显示 CTLine。
2. 为高度测量从原文第 0 个 UTF-16 开始，按可见行逐行 append 各自源子串。原行若已有 paragraph 分隔符，原样保留；若是软换行，追加 U+2028 LINE SEPARATOR 强制同一段落的续行，不能追加 U+000A。
3. 最后 append TailTruncation 的最终候选文本（包含 token 的字体度量，即便 token 宽度不足导致不绘制）。度量副本的字体、baseline、附件 delegate 和完整段落值均来自最终可见源；隐藏附件／大字不得参与。
4. 对度量副本用无限有效宽度 TextFrame 取行基线和 contentHeight；已有强制行分隔符固定可见行数，完整前缀保留段距与首／续行身份。只将其最后基线和最终高度用于输出；之前可见行的实际 CTLine／baseline 不被重新 shaping 或移动。
5. 度量副本仅用于度量，不参与原文映射。U+2028、token、末尾保行 sentinel 永远不是原文 action／装饰片段。新 helper 明确区分真实原文分隔符与人工插入符。

先用测试确认本平台 CTFramesetter 将 U+2028 视为同段落续行且准确保留 lineSpacing；如果出现反复验证失败，保留现场报告实际差异，不切回普通换行、丢弃段距或减小验收样例来绕过。

### 6.3 背景／删除线及后续 I1 的共同片段

`VisibleTextFragments.swift` 提供 internal 查询，输入 Layout.Line、原文字符串和待查源范围，输出 sourceRange＋UIKit 本地 rect 的多个视觉片段。无 UIView、provider、业务闭包或公开 ABI。

- 遍历最终 CTLine 的视觉 CTRun；读取 glyph positions、advances、string indices、run direction 和字体。CTRun 索引加 line.sourceOffset 后映射原文，先与 visibleSourceRanges 相交，再排除 truncationTokenRange。不能仅判断整个原文 range 在 CTFrame visibleRange 内。
- 将 glyph 的字符串覆盖按相邻不同 string index 和 run range 推导；同一组合字符的多个 glyph／多个属性 run 合并到同一源簇，再在视觉连续、同一行时合并矩形。不能因源范围连续就横跨 RTL 视觉间隔或行间空白。
- 一个逻辑 range 在一条混合方向行可产生多个 rect；禁止用全局 minX／maxX 得到包围空白的大矩形。
- rect 的水平范围采用 advance／caret 区间；垂直范围采用所属最终 run 的字体 ascender／descender 和实际 glyph baseline shift。只计算一次 baselineOffset：先用实际 glyph y 验证 Core Text 的位置，再补入未包含的 offset，不能无条件同时加两遍。
- 背景使用 typographic 片段高度，不铺满 lineSpacing／paragraphSpacing。空格可以有背景 advance；换行／无 advance 控制字符不产生背景／动作 rect。行尾 whitespace 的命中排除由 I1 执行，不将装饰背景强行等同命中政策。
- 图片／view 的 U+FFFC 若属于查询范围，以 V1 placement rect 作为其片段；背景可在其后显示，图片／view 自身绘制在装饰之上。interactive view 的事件优先级仍由 V1／I1 决定。

**连字边界契约，必须在 M1b 验证：** `"fi"` 的两个相邻动作合法，不能通过禁用 ligature 或把两动作合并规避。保持同一 CTLine／glyph shaping。首先使用 CTLineGetOffsetForStringIndex 的主／次 caret，并限制在所属视觉 run；若 ligature 内 caret 未区分，使用 CTFontGetLigatureCaretPositions；字体未提供 caret 时按该 glyph 覆盖的完整 grapheme 数将其 advance 等分，RTL 逆序。区间采用半开，最多在外侧向显示像素对齐；内部相邻边界使用同一数值，保证无重叠和无多归属。该 fallback 只决定片段，不修改字形、字体或源范围。

后续 I1 先查触点属于哪个可见片段，再定位字符；不可仅用最近字符返回动作。M1b 只交付几何与按下色的解析能力，不接管手势。I1 将临时 pressedStyle 作为绘制覆盖，不生成新 Document、不修改原文、不改变排版。

## 7. 背景与装饰的明确绘制政策

- 顺序：背景 → Core Text 字形／经验证的原生下划线 → 必要的下划线回退与自绘删除线 → UIImage；UIView 延续 V1 的子视图层次，位于这些内容之上。附件区域内的 underline／strike 可以被图片／view 遮盖，不另建浮在控件上方的装饰层。
- Core Text 字符属性明确映射 font、foreground CGColor、kern、baseline、ligature、underline style／color；不要依赖 UIKit 属性键碰巧同名。
- SDK 确实存在 iOS 10+ 的 kCTBackgroundColorAttributeName，不能写“没有背景 key”。本组件背景统一自绘，因此不同时把背景键交给 CTLineDraw，以免重复透明混色。删除线没有对应的 Core Text key。
- 背景按第 6.3 节的最终可见源片段填充；无圆角／padding 新 API。普通属性色与将来的 pressedStyle 色都按当前 trait resolve。
- 删除线的中心为实际 glyph baseline 上方 CTFontGetXHeight(font)／2；单线厚度为 max(CTFontGetUnderlineThickness(font), 1/displayScale)，thick 为两倍，double 为两条单线、中心间距两倍单线厚度。线的物理像素对齐只在绘制时进行，不改变测量／源片段。
- 标准 pattern dash 长度按该单线厚度的倍数：dot=[1,2]、dash=[4,2]、dashDot=[4,2,1,2]、dashDotDot=[4,2,1,2,1,2]；solid 无 dash。相邻同样式片段的 dash 相位按视觉连续片段累计，不每个 glyph 重新起点。byWord 按原完整字符簇分割 whitespace，空白不画线。
- underline 的 base／pattern 只有经过实际像素测试的 Core Text 支持 bits 才走原生绘制；CTUnderlineStyleModifiers 并未承诺 NSUnderlineStyle.byWord，不能仅凭 rawValue 桥接就宣称支持。必须用 `"AA AA"` 的实际 byWord underline 像素测试，确认空白 advance 区域没有下划线且两端字词有线。
- 如果 native 忽略 byWord，则仅对带该 modifier 的 run 使用内部下划线回退：从共享最终可见源片段按完整字符簇 whitespace 分词，采用 CTFontGetUnderlinePosition／Thickness、相同标准 base／pattern、resolved underlineColor（缺省 foreground）绘制。该 run 在传入 Core Text 的绘制属性中将 native underlineStyle 设为 none／移除，确保只绘一次；不改 shaping、Document 或公开 API。不带 byWord 且已验证支持的 style 继续原生路径。回退同样排除生成 token、隐藏源和人工分隔符。
- strike 颜色同样默认 foreground；显式色不被 fallback 覆盖。所有原生／回退装饰路径共享 trait 解析、baseline 与 contentClip，不新增专用布局或业务文档。
- 生成 token 不继承这些装饰，其下方／后方不得残留隐藏源字形的装饰。高度裁切、inset 和非零 bounds.origin 仍只在 Label 边界应用一次。

## 8. M1b 实施和测试顺序

### Task B1：样式快照和段落规范化

- [ ] 先写 StyleTests 中 mutable 属性／paragraph 隔离和逐字段快照断言；纳入两个字符样式 run 横跨 paragraph 边界，以及同段落后续 paragraph style 冲突。预期段落首字符值获胜；第二段按自己的首字符值。
- [ ] 写数值规范化用例：NaN／正负 infinity kern 变为 nil 且省略 CT key，baseline 变为 0；有限负 kern／baseline 保留；缺省 kern 与显式 0 的 CT key 不同且不改变原默认 shaping；非数值类型忽略；ligature=-1／3／非整数变为 1；未知 underline／strike base 或 bits 变为 0；段落非有限变为 0，有限负 spacing／firstLineHeadIndent／headIndent／tailIndent 保留，有限负 min／max／multiple 变为 0；min > 非零 max 时 max 变为 0。断言 typed snapshot 与最终 Core Text 取值都有限，不只检查“没有崩溃”。
- [ ] 写 extreme-finite 回归：分别给 kern、baseline、每个 spacing／indent、min／max／multiple 输入 `CGFloat.greatestFiniteMagnitude`、其负值、`CGFloat(Float.greatestFiniteMagnitude)` 及会在字符数／行数／字体高度乘法中溢出的组合；不要只测试 NaN／infinity。断言预处理不会将危险值传给 Core Text，最终 size／baseline／glyph／rect／缓存／像素取整均有限，fallback 次数最多一次、provider 调用为 0；并列断言普通 ±2 kern、±8 baseline、±12 spacing／head／tail 与普通 min／max／multiple 原值及行为保持不变。
- [ ] 添加 typed immutable StyleRun／ParagraphStyle 字段，复制原输入值；分离段落规范化与字符 run 快照。先不宣称绘制已完成。
- [ ] 运行 StyleTests／DocumentTests／ActionTests／SegmentTests，确保所有既有动作／附件错误稳定，原输入修改不影响文档。

### Task B2：Core Text 属性及段落行为

- [ ] 固定 UIFont、宽度和 scale，写 kern 改变 advance／换行、ligature 0 与 1 shaping、正负 baseline 的实际 glyph／图片位置测试；测量不依赖旧 bounds.height。
- [ ] 写两段三行 fixture，分别变化 lineSpacing、paragraphSpacingBefore／After、firstLineHeadIndent／headIndent、tailIndent 正负、minimum／maximum／multiple，断言正确基线差与排版区域；包含负 spacing、悬挂缩进、RTL 和尾随换行空行。增加无外部宽度约束＋正 headIndent 的用例，确认理想宽度包含必要缩进，不因原先仅测字形 advance 而意外软换行；正 tailIndent 的系统固定 trailing 位置仍应遵守。
- [ ] 将白名单映射到 Core Text keys 与完整 CTParagraphStyle；用当前 traits resolve 所有颜色，默认 body／label 不变。实现 wrapping 注入，先用 `.word` 保持现有调用兼容。
- [ ] 写并运行固定英文短语的 word／character 不同断行测试；使用文本 `"alpha beta gamma"`，宽度设为固定字体 `"alpha b"` 的测量 advance＋一个物理像素，避免硬编码恰巧边界。
- [ ] 运行 LayoutTests／AttachmentTests／ViewAttachmentTests 与 B2 目标类，确认 maximumLineHeight 的显式限制不会被附件反向改写。

### Task B3：尾部省略保持完整段落上下文

- [ ] 写失败用例：首行与续行不同 headIndent、两种 tailIndent、center／right／natural RTL；numberOfLines=1 与 2 的 token 必须位于有效区域内；隐藏首 strong 字符不能改变方向；仅 LTR 缩进不能误判成 RTL。
- [ ] 写含 lineSpacing、段前后距、min／max／multiple 的软换行截断；上一可见行为 continuation，下一行为 continuation／新 paragraph 两种情况；隐藏超高图片／view 不抬高末行。比较未截断参考前缀的前面各行 baseline 和最终可见布局高度。
- [ ] 实现第 6.1／6.2 节：完整段落值、有效尾行区域、保留原字符簇收缩、完整可见上下文度量副本。度量副本不参加原文 range 查询。
- [ ] 确认真实 `…` 有 source range，生成 token 无 source range；仅 token／无法容纳 token 的既有回归继续通过。
- [ ] 运行完整 TruncationTests 和附件截断目标测试；失败时保留日志，禁止去掉 indent／spacing 测试或改为普通换行以绕过。

### Task B4：共同视觉片段与装饰绘制

- [ ] 写 TextGeometryTests：跨行 action 返回多片段；混合 Arabic／English 同行片段不覆盖视觉间隙；字符簇内分段属性仍映射到完整源簇；token、人工 separator、保行 sentinel 不产生片段。
- [ ] 写相邻 `f`／`i` 动作测试，选固定系统可用的连字字体（先断言 fixture 确有少于两个 glyph 的 fi 连字，不能零命中／不成连字却标通过）。同文档有／无 actions 的 glyph 数、positions、baselines 完全一致；两个 action 各有非零 rect，内部边界相同且交集宽度为 0；同 ID 也不能合并。
- [ ] 对未提供 ligature caret 的字体路径使用 internal 纯函数输入测试 fallback 的等分与 RTL 顺序，不把系统字体未触发的分支误写为已覆盖。
- [ ] 实现 VisibleTextFragments；装饰与动作查询共享最终源映射，不先做 I1 手势。
- [ ] 写 DecorationDrawingTests：固定背景色形成真实像素块；single／thick／double strike 与自定义色；每种 pattern／byWord 空白断开；underline 自定义色；baseline 正负、mixed font、RTL、被截断装饰和生成 token；透明背景不能重复混色。
- [ ] 单独运行 `"AA AA"` 的 native underline `.single.union(.byWord)` 像素试验，记录 native 是否真正跳过空白，不用属性字典存在性代替渲染结果；若失败实现第 7 节共享片段回退并在该 run 抑制 native underline。验证普通单词有线、空白无线、自定义色／baseline／RTL／截断正确，以及透明线色没有双重绘制加深。不添加新的 public API。
- [ ] 先确认像素测试在现有缺失绘制下失败，再实现 TextDecorations 和 Core Text underline。像素采样取色块内部并同时检查裁切外无变化，避免依赖抗锯齿边缘完全相等。
- [ ] 明暗 trait 变化使用同一个 Document，确认默认前景／显式动态背景／underline／strike 色更新；PressedStyle 的 UIColor 解析也随 trait 更新，但不声称已实现按下反馈。

### Task B5：垂直对齐及 UIKit／SwiftUI 消费

- [ ] 写 top／center／bottom 的同宽同内容测试：测量尺寸保持相等，bounds 高度多出 60pt 时文字／image／view 的可见位置分别增加 0／30／60pt；inset 已计入一次。
- [ ] 写受压高度偏移为 0、非零 bounds.origin、宽度往返、部分附件裁切。沿用 V1 provider 计数断言：上述纯测量与几何查询 factory 调用为 0。
- [ ] 加入配置枚举与统一展示 offset helper；draw 和 V1 附件同步消费同一变换，contentClip 固定。不得在测量中创建 view 或 layoutIfNeeded。
- [ ] 更新两端共用样例：装饰、混合段落、word／character、top／center／bottom；UIKit／SwiftUI 相同输入同宽高度差不超过一个物理像素，展示截图记录系统和 scale。
- [ ] 运行直接 UIKit／SwiftUI 宿主测试、V1 生命周期／按钮自身交互／复用回归，确保展示偏移未破坏附件点击或导致重复挂载。

### Task B6：M1b 交付

- [ ] 将实际支持白名单、paragraph 首字符规则、换行优先级、垂直对齐和 ligature caret fallback 写入 README／DocC，未知属性不写成“保留全部富文本属性”。
- [ ] 更新总计划：M1a／M1b 按真实证据完成，I1 开始前尚无文字 tap／longPress／取消／动作无障碍结论。记录仍未验证的 iOS 16、Swift 6.0 编译器、真机、人工 VoiceOver，不阻塞独立本地实现。
- [ ] 运行第 9 节 M1b 检查，按 CONTRIBUTING 独占集成与普通推送；通过后自动进入 I1，使用本计划的动作和片段契约。

## 9. 验证、提交和真实证据

以下命令在仓库根执行，目标测试实际使用的 Simulator UDID 在 V1 结束后重新读取可用设备并选本任务独占设备，不把某个历史 UDID 写成必然可用。目标类测试仍必须通过 iOS 宿主 scheme，不能用 macOS swift test 代替。

```sh
scripts/verify.sh docs
scripts/verify.sh format
swift package dump-package
scripts/verify.sh build
xcrun simctl list devices available
```

针对性测试使用现有 shared scheme、固定本任务选定的 UDID 和唯一 resultBundlePath；命令形态如下，执行时填写实际 UDID、结果路径，并核对 scheme 的实际宿主测试 target 名称：

```sh
xcodebuild test \
    -project Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj \
    -scheme LYGlyphTextDemo \
    -destination 'platform=iOS Simulator,id=ACTUAL_TASK_UDID' \
    -only-testing:LYGlyphTextDemoTests/ActionTests \
    -resultBundlePath .build/verification/UNIQUE_M1A_ACTIONS.xcresult
```

M1a 接口变化、M1b 布局／绘制／展示变换均扩大到直接消费者；每个交付最终运行一次仓库标准完整宿主／UI 回归：

```sh
scripts/verify.sh test ACTUAL_TASK_UDID
git diff --check
```

- 记录确切命令、环境、SHA、测试总数／失败／跳过、截图、日志和 xcresult。上面的 ACTUAL_TASK_UDID／UNIQUE 名称是运行参数说明，不能原样执行，也不应在最终验证记录中保留。
- 只有非零目标测试数和成功状态才可报告通过；缺工具／零匹配／全跳过／最低环境不可用均不能写通过。不自动安装工具，不下载 runtime，不接管其他任务 Simulator。
- 先跑对应失败测试，再实现最小行为；针对性通过后做相应交付的一次完整回归。相同已验证 SHA 不重复同套检查，后续代码变化或实际失败才扩大复验。
- M1a 建议提交标题 `feat: 增加安全分段与动作文档`；M1b 建议 `feat: 完善富文本样式与统一展示几何`。只暂存本交付文件，按 CONTRIBUTING 的独占集成锁、最终候选验证、普通合入 main 和一次 `git push origin main` 交付。push 失败保留成果并报告，不自动 rebase／pull／force-push。

## 10. 实施前自审结论

- 公开类型、参数、默认值、错误、输入快照时点、动作身份、范围和段落值规则在本计划中均已确定；无待用户选择的产品歧义。
- 最主要实现风险是 Core Text 的截断度量上下文和双向／连字 caret；分别由 B3 与 B4 的失败测试先固定。其失败是需要查证的技术问题，不是新增许可检查点。
- 本计划不把 native background key 的存在推导成 CTLineDraw 的验证结果；背景统一自绘。也不把静态几何测试推导为 I1 的实际手势验收。
