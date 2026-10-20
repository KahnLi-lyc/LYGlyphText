# I1 文本动作、按下态与取消 Implementation Plan

> **For agentic workers:** 使用 executing-plans 与 subagent-driven-development 顺序实施；连续开发已获授权，不增加任务间许可检查点。每次仅一个源码／测试实施者，块内先红后绿、规格审查再质量审查；根代理负责 Markdown、正式验收及 Git。计划不是能力或验证结论。

**Goal:** 让现有动作文档通过 UIKit／SwiftUI 发出准确且至多一次的 tap／longPress，使用统一可见几何显示按下颜色，并在取消时立即恢复。

**Architecture:** Document 继续是无闭包的快照；M1b 的最终 CTLine、VisibleTextFragments 与展示变换是唯一几何来源。Label 持有回调和短生命周期交互状态，自定义局部手势识别器只接收真正命中动作的序列；SwiftUI 只更新 Label。

**Tech Stack:** iOS 16+、Swift tools 6.0／Swift 6、UIKit、SwiftUI、Core Text、XCTest／XCUITest，零第三方运行依赖。

---

## 0. 依据、范围与源码风险

依据总计划第 3、4.3、4.5、4.6 和阶段 5，以及已批准的 `docs/superpowers/plans/2026-10-20-document-actions-styles.md`。M1a 负责动作输入／范围验证，M1b 负责样式／最终源片段／统一展示坐标。I1 不重复做这些输入层，不添加选择复制、路由、公开布局接口、手势选项、额外可点击 padding 或新的按下样式字段。完整宿主矩阵与动作 VoiceOver 元素仍分别属于 H1／A1；I1 必须有最小的真实列表选择／滚动夹具，不能借后续任务跳过本任务手势验收。

实施基线为 M1b `6dbeaeeade114c63dac8574e11b0860488882b15`：215／215 正式回归、10 张原图、两阶段与最终集成审查已通过；已合入并推送 main、远端 SHA 一致、原临时分支已清理。当前使用 `codex/text-interactions`。本计划已对照实际 M1b 文件及 SwiftUI displayHeight 接口，不覆盖其他任务修改。尤其注意：

- `LYGlyphTextLabel` 当前只有附件 revision，没有动作回调／状态；`document.didSet` 仅在对象身份变化时失效，`bounds.didSet`、`invalidateText()`、`didMoveToWindow()` 和 `clearForDismantle()` 是需要接入的取消边界。
- `clearForDismantle()` 当前先置拆卸标志，再清 document/provider，并在附件清理重入后再次清空。新增回调必须参与相同事务，不能被同步 onUnmount 重入恢复。
- `AttachmentContainer.hitTest` 返回实际交互子视图，普通区域返回 nil；父 Label 的 recognizer 仍会看到子视图的触摸，必须显式拒绝实际交互附件子树。
- 当前 SwiftUI `apply` 仅赋 configuration/document/provider；应每次刷新 onAction，不能在 makeUIView 捕获初始闭包。
- 现有 `ReuseDemoCell` 的 selectionStyle 为 none，也没有 didSelect 可观察计数；现有滑动／附件按钮测试不能证明普通区域仍能选择 cell。
- 当前 CTLine 内嵌普通前景 CGColor，简单设置 CGContext.fillColor 不会可靠覆盖。按下前景必须做真实像素验收，不能只验证背景或事件计数。

## 1. 最小公开 API

新建 `Sources/LYGlyphText/Document/LYGlyphTextActionEvent.swift`：

```swift
@MainActor
public struct LYGlyphTextActionEvent {
    public enum Kind: Equatable {
        case tap
        case longPress
    }

    public let actionID: String
    public let range: NSRange
    public let visibleRects: [CGRect]
    public let kind: Kind
}
```

所有成员补简体中文 DocC。event 是输出值，首版不增加宿主构造 event 的 public initializer；内部构造即可。不额外声明 Sendable。`range` 永远是完整动作的原文 UTF-16 范围，即使只显示其中一部分；`visibleRects` 是发送当时该动作实际可交互片段在 Label 本地坐标的数组，已应用 bounds.origin／垂直对齐／inset 裁切。跨行保留多个矩形，不以总包围框替代，不暴露 CTLine／CTRun。

Label 追加：

```swift
public var onAction: (@MainActor (LYGlyphTextActionEvent) -> Void)?
```

SwiftUI 追加同名可变属性，并在现有初始化参数末尾追加默认 nil，保持 V1 调用兼容：

```swift
public init(
    document: LYGlyphTextDocument?,
    configuration: LYGlyphTextConfiguration = .init(),
    viewProvider: LYGlyphTextAttachmentViewProvider? = nil,
    displayHeight: CGFloat? = nil,
    onAction: (@MainActor (LYGlyphTextActionEvent) -> Void)? = nil
)
```

- 全部触摸状态、计时、绘制覆盖和业务回调均在 MainActor。
- Document/Layout 不持有回调。Label 正常持有 onAction；宿主如闭包捕获自身，使用弱捕获。组件内部不使用对 Label 的强捕获形成 timer／recognizer／scroll observer 循环。
- document 替换／置 nil 取消当前序列，但保留宿主 onAction 和 provider；下一次绑定可继续使用。
- onAction 置 nil 立即取消按下和计时。替换成另一个非 nil 闭包不保留旧闭包；发送时读取最新 onAction，因此相同文档的 SwiftUI 更新也不会发给旧捕获值。每次普通 apply 不因非 nil 回调重新赋值而无条件取消。
- SwiftUI apply 先更新 onAction，再更新 configuration/document/provider。dismantle 清 onAction、交互及附件，清理回调重入后仍为空；不把 `isTearingDown` 期间赋入的回调留存到事务结束。

## 2. 唯一命中几何与空白政策

内部在 Label 当前展示布局上查询动作，不缓存独立的字符布局。动作身份是文档 revision＋`document.actions` 的输入数组下标；绝不用 actionID 作为唯一字典键。同 ID 的两个相邻范围独立命中、按下与发送。合法负 kern、baseline 或重叠行高可能造成不同动作的可见矩形相交；多个动作同时命中时，按 document.actions 原输入顺序取首个命中者。此规则不扩大或缩小矩形，不改变 shaping；连字相邻半开边界仍唯一归属。

处理顺序：

1. 验证 window、有效 bounds／contentClip、当前 document、onAction、非拆卸状态。
2. 从 M1b 最终 CTLine 的共享片段取得该范围的视觉区间，排除隐藏源、生成 token、换行和零 advance 控制字符。不能对 `CTLineGetStringIndexForPosition` 的最近字符结果直接发动作。
3. I1 在共享源簇几何上应用点击政策：内部空格可属于动作；每条最终可见行末连续 whitespace 的片段不参与点击。不能直接 trim 整个动作或整段文档；不能因为末尾是生成 token 就把被截断处的源 whitespace 当作内部空白。
4. 对所有片段使用 M1b 同一个展示变换（已含 inset 的布局只变换一次），与固定 contentClip 和 bounds 相交，丢弃空或非有限矩形。短高度只留下实际可见部分。
5. 仅在触点落入上述矩形时定位源簇／确定动作。使用共享的相邻 ligature 半开区间，不各自再向内扩大或 round，保证边界只归属一个动作。没有命中就是 nil。

事件 visibleRects、高亮与命中消费同一份动作可见片段。行间／段间空白、行尾 whitespace、边距、对齐留白、token 和被裁掉的区域都不是动作命中；不默认扩大点击范围。图片及装饰 view 的 U+FFFC 可参与动作，并按附件 placement rect 裁切；若当前触摸实际落到挂载的 interactive view 子树，交给子视图且父动作不识别、不高亮。provider 返回 nil 时没有原生接收者，其占位矩形仍遵从动作几何，不能凭 descriptor 猜测存在子视图。

## 3. 状态机与一次事件

交互状态本体只有 `idle` 和 `pressed`；terminal 后立即回 idle，识别器自己的终态负责消费该手势剩余触摸。

```swift
struct PressSession {
    let actionIndex: Int
    let documentRevision: UInt64
    let geometryRevision: UInt64
    let origin: CGPoint
    var latestPoint: CGPoint
    let sequenceID: UInt64
}
```

origin 是 Label 本地坐标的开始触点。revision 使用已有项目同类的递增标识，不用 actionID 或文本相等替代。geometryRevision 对实际展示几何失效递增，纯按下颜色更新不递增。一次 touch sequence 最多跟踪一个主触点；Label 子树内可观察的第二触点到来即取消，不转移到另一个动作；Label 子树外的触点属于宿主，不声称局部识别器可观察，也不使用全局监听。

| 输入 | 前提／处理 | 事件 |
|---|---|---|
| down | 只在精确命中且可处理动作时 idle→pressed；保存下标／revision／origin，显示颜色，启动一次 0.5s 计时 | 无 |
| move | `hypot(dx,dy) > 10`（等于 10 不超阈值），或离开此动作任一可见片段，或命中已不是同一个动作实例，立即取消；不允许离开后滑回恢复 | 无 |
| timer 0.5s | 重新验证 revision、同一实例、最新触点仍命中、未被滚动接管；先保存 event 和最新回调，再清状态／计时／高亮并标记已识别，最后调用业务 | longPress 一次 |
| up before longPress | 同一实例／revision／几何且仍精确命中；先保存 event／最新回调，再清状态和高亮并识别，最后业务回调 | tap 一次 |
| up after longPress | session 已清空，识别器已结束／消费此序列 | 无 |
| cancel | 清 session、计时、颜色；使可能中的识别器失败／取消，旧 timer token 失效 | 无 |

取消输入必须接全：系统 touchesCancelled、祖先滚动 pan began／changed、document 对象替换／nil、布局输入变化、bounds size 或 origin 变化、inset／wrapping／numberOfLines／verticalAlignment 变化、trait 引起的布局或颜色刷新、window 移除、SwiftUI dismantle、onAction=nil、Label 子树内可观察的第二触点。更换 provider、reload 或可见附件接收者集合变化也取消当前序列，避免 nil 占位在按下后变成真实原生控件却继续发送旧动作。相同文档／相同配置重复赋值及无几何变化的 layoutSubviews 不应凭空取消。父层已经开始拖动／减速期间的触点不启动文字长按，以 scrollView.isDragging/isDecelerating 或 pan 状态防守。

定时器捕获弱接收者与 sequenceID，不捕获事件、Document、宿主闭包。内部可用可控时钟接口测试，不公开 timer API。0.5s 到期与 up 同一 runloop 时，以先处理且通过检查的 terminal 为唯一结果；清状态在回调之前，保证同步 document=nil、换回调、removeFromSuperview、拆卸和再次 clear 都不会再发一次。

## 4. UIKit 输入机制与父容器协作

选择 internal `ActionGestureRecognizer: UIGestureRecognizer`（discrete，自定义 touchesBegan／Moved／Ended／Cancelled／reset），不用覆盖 Label touches，也不叠加全域 tap＋longPress 两个彼此竞争的识别器。

理由：识别器可在 `.possible` 阶段显示按下并计时，只有 tap／longPress 成功才认定手势；滚动可以在此之前接管。单独的 touches 覆盖需要接管 responder 转发／手工计时，并很难保证表格选择和滚动不受影响。两个系统识别器则需要额外同步高亮和一次性结果，且 UITapGestureRecognizer 本身没有 down 高亮阶段。

实现约束：

- 识别器仅附在该 Label。已有 session 时，delegate 的接收入口先观察并取消来自 Label 子树内的新增第二触点，再按新触点的实际目标决定是否拒收；第二指落在空白或原生 UIButton 也应取消第一指，且不能阻止 UIButton 接收自己的触摸。没有 session 时，接收策略直接拒绝 onAction=nil、未命中、普通文字／空白和实际交互附件子树；拒绝发生在接收序列前，不先吞掉再用最近字符判断。Label 子树外触点不在观察范围。
- `delaysTouchesBegan = false`、`delaysTouchesEnded = true`、`cancelsTouchesInView = true`。`.possible` 可显示高亮；成功时取消宿主触摸结束，避免一次动作同时选择 cell。普通区域因未接收识别器序列，继续普通选择／滚动。取消后恢复是否选择由 UIKit 宿主决定，组件不补发 tap。
- 对自身祖先 `UIScrollView.panGestureRecognizer` 明确不防止其识别，并允许 pan 防止当前动作。不能把整个树统一设成 simultaneous=true；不要更换 scrollView／tableView 的 delegate 或 recognizer.delegate。
- 为及时清理高亮，对当前祖先 scroll pan 追加局部 addTarget 观察，在 `.began/.changed` 取消；不依赖被系统防止后何时 reset。观察器弱引用 Label；在离开 hierarchy/window、取消或拆卸时对原有 pan 成对 removeTarget，不改宿主其余 targets。嵌套 scroll 观察全部祖先 pan；滚动开始就取消，不等待 10pt。
- 不对所有宿主 recognizer 安装 failure requirement；尤其不能要求祖先 pan 失败后才发 longPress，否则 0.5s 长按被延到抬起。只对确定的祖先 scroll pan 做局部优先级处理。
- recognizer 内不得强持 Label。reset/touchesCancelled 和 Label 生命周期取消走同一个幂等收尾；内部取消重入不递归发事件。

上述选择是最小实现方向，真实 UITableView selection／scroll 是门槛。若自定义识别器与 UIKit 内部选择顺序冲突，应针对局部 recognizer 调整并保留测试；不能通过关闭 cell selection／scroll、全域同时识别、改宿主代理或测试直接调用回调绕过。

## 5. 按下绘制、动态颜色与恢复

- 使用既有 `LYGlyphTextPressedStyle`，foreground nil 继承普通前景，background 默认 tertiarySystemFill，显式 background nil 继承普通背景；非 nil background 替换该片段的普通背景，按最终有效背景只绘制一次，不叠加在原背景上；不增加字体／圆角／padding API。
- 按下只调用 setNeedsDisplay。不得创建新业务 Document、改变字体／kern／baseline／段落／附件尺寸，不触发测量缓存失效或重新取得可见几何。
- 最终 Layout 的 lines、截断源映射及两类附件 placement 确定后，一次准备并保存不可变 source cells／pieces、glyph shaping group 归属及装饰 Prepared；动作索引消费同一快照。draw 不再查询可见几何、查样式或分组。该准备函数只消费最终数据，不创建第二套 CTLine／framesetter／layout。无装饰但有动作的文档同样准备源 cells。
- internal 元数据保留 cluster sourceRange、line index、rect／baseline、稳定 run ordinal、实际 glyph indices（仅连续时可用单一 glyphRange）、完整 source coverage；背景／stroke primitive 保留 style ordinal、源成员归属及显式或继承色。Stroke batch 保留原合成顺序、merged intervals 与成员引用，不能仅保存 group 级颜色继承标志。普通同色的显式／继承装饰在按下时可能不同。
- 按下绘制引用完整原 stroke 路径和各不连续 interval 的原 phase 起点，以源成员 clip 改色；不截成从动作边界重新起相位的短路径。装饰 clip 竖向范围覆盖实际厚线／双线 stroke bands。若按下有效颜色需要按成员重组，在 Layout 一次准备阶段生成动作选择表，不在 draw 重组；仅索引受影响成员并共享原路径，不为每个动作复制完整装饰。不得全局按颜色重排或破坏既有重叠 barrier。
- 动作索引按原输入下标保存 cell／glyph group／装饰成员关联，不合并同 ID。按下只存动作下标。新 Layout 替换缓存；trait 刷新取消序列并建立新颜色环境。确定性观察测试断言 Layout 仅准备一次，普通→按下→取消→恢复多次 draw 后几何查询／样式检索／stroke 分组次数不增长；CTLine identity、glyph signature、cells、路径及 phase 不变。
- 准备成本同时覆盖多个短动作与单个长动作。后者以 40→160 个 byWord 不连续 interval 检查 barrier 成员访问、活跃矩形判断及实际 stroke interval 绘制次数；不能只计外层 region／树查询而遗漏内层全量扫描。按压绘制不能为每个字符分区重复描画整组 interval，修正仍保留完整原路径、源顺序及 dash phase。
- 优先选择在 ResolvedText 的全部原始字符样式统一加入 `kCTForegroundColorFromContextAttributeName=true`，普通与按下均以同一最终 CTLine 的原始 CTRun 配合 CGContext fillColor 绘制；不能仅在动作范围加入属性导致连字分裂，也不在按下时创建新 CTLine。每个 run 普通色保留为解析值。保持原 glyph 绘制顺序，先按原 glyph shaping group 的 source coverage 判断是否与动作相交；不相交的源组及生成 token 完整按普通色绘制。有交集的组仅以本行／本组被选共享 caret cells 的联合区域做普通／按下内外互斥 clip；跨动作 fi 保持原共享 glyph，用既有 caret 分区分色。可为 internal RunPiece 增加原 glyphRange 等元数据，不新增排版或公开 API。背景和字形透明度均只合成一次。内／外 clip 必须先求选中矩形的联合区域；不能直接把重叠矩形附到 even-odd 反向路径，否则交叠区会错误露回普通色。
- SDK 明确 `CTRunDraw` 不绘制 underline，因此该方案在 I1 将所有已支持 underline base（含普通 solid）统一交给 TextDecorations；在原 shaping 属性中保留既有实际 CT underline style／color（含 M1b modifier fallback 已置为 none 的值，不把 Document 原值重新灌入），避免为绘制移除属性造成 run 合并／shaping 改变。存储显式装饰色与继承前景的区别；装饰同样先限定源归属，保持整段既有 stroke 路径与 dash phase，只以对应源片段互斥 clip 改色，不能在动作边界重启虚线相位。原生独立像素探针仍保留为诊断，不再宣称组件 ordinary 绘制走 CTLineDraw。token 可继续使用原显式普通色，不能携带动作或按下属性。
- 必须以实际像素和 glyph 签名验证上述路径：所有原字形 IDs、positions、advances、矩阵、基线、typographic metrics、源映射及附件 placement 不变；同一 final CTLine 在普通／按下／恢复不替换。CTRunDraw 的 textPosition／textMatrix 在每个 run 恢复，不能依赖上一个 draw 留下的状态。彩色 emoji 内建颜色应保留，不通过灰度 mask 或统一 tint 覆盖。
- 若 fromContext 路径实测无法保留字形或彩色 emoji，保留失败证据并选择更小的可证替代方案；任何显示副本也必须满足完全相同的 glyph 签名，不进入 framesetter／换行／截断／测量管线，不替代权威几何。不要静态宣称这一方案已经工作。
- 颜色造成 run 分裂时，仍必须维持 fi 连字和相邻动作共享边界；不得禁用 ligature 或改变 shaped glyph 解决。若显示副本的 glyph／位置不变测试失败，改用不改变原 shaping 的绘制覆盖方法。
- 所有颜色按当前 trait 解析；按下背景不重复透明混色，普通与按下装饰遵守 M1b 顺序。前景变化需要验证 native underline／显式 underlineColor、彩色 emoji 和图片不被错误染色。显式装饰色仍显式；缺省继承 foreground 的装饰跟随有效颜色。
- 局部裁切只覆盖被按动作的可见片段；同 ID 其他动作、相邻动作、行间空白、生成 token 和隐藏源保持普通显示。按下态取消／释放后恢复普通颜色，无旧覆盖残留。
- trait 刷新采用取消当前序列并恢复普通显示的明确策略；下一次按下使用新 trait 的普通／pressed 动态色。Document 不因明暗变化替换。

## 6. 文件职责与实施顺序

预计新增：

- `Sources/LYGlyphText/Document/LYGlyphTextActionEvent.swift`：公开事件值；与动作输入值同属文档契约层，不持有宿主或回调。
- `Sources/LYGlyphText/UIKit/ActionGestureRecognizer.swift`：局部触摸输入、计时及 scroll 观察；若状态逻辑独立足够清楚，同文件 internal PressSession 即可，不为了测试拆万能抽象。
- `Tests/LYGlyphTextTests/InteractionTests.swift`：状态、revision、重入、生命周期、回调更新。
- `Tests/LYGlyphTextTests/ActionGeometryTests.swift`：实际 M1b 片段到动作命中的政策。
- `Tests/LYGlyphTextTests/PressedDrawingTests.swift`：颜色、恢复与几何不变的像素测试。
- Demo 可新增 `Examples/LYGlyphTextDemo/LYGlyphTextDemo/InteractionDemoController.swift`：最小可选中 UITableView 手势夹具与可观察事件状态，不污染组件公开 API。

修改现有 Label、SwiftUI View、必要的 M1b `Layout/LYGlyphTextLayout.swift`、`Layout/VisibleTextFragments.swift`、`Layout/TextDecorations.swift` 和 `UIKit/DisplayGeometry.swift`，以及 DemoSamples、UIKitDemoController／SwiftUIDemoView、DemoAppDelegate 入口和 DemoUITests。保留已交付的 SwiftUI displayHeight 参数及自然高度契约，新增 onAction 放在其后。只在实际需要时修改 Layout 私有绘制输入，不为 I1 重构附件工厂。

### 内部串行执行顺序

1. C1：事件值、最终不可变源几何／glyph 归属与按原输入下标的动作可见矩形索引；缓存全局 cell／glyph group／装饰成员及原批次，将装饰准备移到 Layout 构造，不改原 glyph 绘制或引入手势。
2. C2：基于 C1 的原 CTRun 普通／按下／恢复颜色绘制；在 Layout 准备阶段为各动作组装第 5 节要求的 cell／glyph group／装饰成员关联和稀疏选择表，不在 draw 查询／重组，也不为 C1 单独制造过渡渲染索引。迁移前后完整 glyph 签名先留证，装饰路径／相位及源归属满足第 5 节。
3. C3：局部识别器、取消和发送状态、Label／SwiftUI 最新回调及幂等清理，消费 C1／C2。
4. C4：真实两端手势及可选择列表夹具，完整交互 UI 与截图。
5. C5：根代理正式回归、记录、提交、集成和普通推送，成功后自动进入 H1。

上述顺序对应以下 I1.1 → I1.3 绘制 → I1.2／I1.3 宿主 → I1.4 → I1.5；不是并行改同一内核。每块由新实施者实现，修复回同一实施者，再串行复审。本阶段整体交付前不把部分输入／绘制写成业务交互已支持。

2026-10-21 恢复预检：C1 保留验收；C2 继续现有工作区，先补真实合成／源归属失败测试。C3 接入时分别维护文档与几何版本，不将服务工厂重入的 attachmentRevision 直接当作文档版本；祖先变化按原 pan 对象解绑，再绑定新祖先。受控时钟只提供 internal 测试接点；真实手势结论仍必须来自 C4。附件接收者新增／移除／替换前取消旧序列，同实例移动和相同输入重复布局不取消。SwiftUI 拆卸前后清空 callback、document 和 provider，覆盖 onUnmount 同步恢复三种输入的重入场景。

2026-10-21 执行状态：C1—C4 已完成并分别通过规格与质量审查。C3 最终定向 22／22、完整宿主 272／272；C4 完整宿主 274／274、真实 UI 9／9。绘制 run 批处理质量修复后的 C5 正式 docs／format／build／全量 test 已通过，最终为 276 宿主＋18 UI = 294／294；当前只剩 Git 交付。提交、集成和普通推送完成前，I1 仍标记进行中。

### Task I1.1：事件与精确动作几何

- [x] 在 ActionGeometryTests 先写会因真实行为缺口失败的测试；event API 不存在时先补最小声明，再运行直到失败原因是命中行为，不能把“类型不存在”作为最终红证据。
- [x] 用固定系统字体／scale／宽度构造：跨两行一个动作、两个相邻同 ID 动作、RTL/LTR 混排、`fi` 两个动作、emoji ZWJ 与 combining character、部分截断和 U+FFFC。取得真实片段后测片段中心、相邻半开边界、片段外 1pt、行间与行末空白，检查唯一动作下标／range。
- [x] 同一文档在 inset、非零 bounds.origin、top/center/bottom、短 bounds.height 下，断言事件矩形等于共享片段的统一变换与交集；裁掉／token 区域一律 nil。
- [x] 加入实际使两个合法动作视觉矩形相交的行高压缩 fixture，确认交集中选择原输入顺序的首个动作，不改变合法样式；不把系统已钳制的负 kern 探针当作真实相交证据。
- [x] 实现 Label 的单个动作查询入口与 event 输出；C1 不启用业务手势，C3 已接入消费该入口。
- [x] 运行 iOS 宿主中的目标几何测试，保留红／绿证据。C1 规格及质量审查批准，220 项宿主回归通过；Label 查询入口在 C3 接入。

### Task I1.2：按下状态、取消与 UIKit 接入

- [x] 用可控时间推进到 0.499s（无事件）及 0.5s（longPress 一次）；随后 up 事件数不变。tap up 时 actionID／完整原范围／visibleRects 正确。
- [x] 分别测试移动正好 10pt、超过 10pt、移出后移回、相邻同 ID、第二触点、系统取消、scroll began、document 中途替换／nil、bounds／配置／trait 改变、window 移除、provider 更换／reload／原生接收者变化，均取消后无 tap，颜色状态清空。第一指按动作、第二指落空白或 UIButton 的受控输入覆盖第一指取消及按钮优先。
- [x] 测试 callback 同步替换 Document、置 nil、移除 Label、调用 clearForDismantle，事件始终最多一次；回调在状态清理后执行。
- [x] 实现 custom recognizer 及局部 scroll 观察；覆盖无 callback 和实际 interactive 附件子树拒收。
- [x] 测试 timers／scroll targets 不保活 Label、旧序列 timer 不作用到新序列；dismantle 重入后 onAction=nil，弱宿主释放。
- [x] 运行目标状态／生命周期宿主测试；C3 最终定向 22／22、完整宿主 272／272，系统事件另由 C4 真实 UI 补证。

### Task I1.3：颜色绘制与 SwiftUI 最新回调

- [x] 先写像素测试：普通→按下→释放／取消→普通；foreground 与 background 各有独立采样断言。明／暗模式动态颜色分开测，默认 tertiarySystemFill 与显式 nil 语义分开测；相邻片段的半透明合成与 nil 保留均已覆盖。
- [x] 在 glyph 实体内部采样或比较 mask 的颜色，覆盖 fi、emoji、跨行动作、生成 token、邻接同 ID、显式与继承装饰色；图片和 interactive UIView 不被前景 tint。
- [x] 比较真实 `6dbeaee` renderer 与当前普通 renderer 的完整签名，并覆盖普通／按下／恢复；measured size、权威 CTLine、可见源映射及附件 placement 保持不变。
- [x] 覆盖真实重叠、相邻无关源、其他行、token ink、半透明联合区域、非整数边界及所有支持的下划线样式；完整 stroke path 与虚线相位保持。
- [x] 实现最小颜色绘制覆盖；只触发展示失效，不创建新 Document 或使布局几何失效。
- [x] 更新 SwiftUI 属性、默认初始化参数、apply 与 dismantle；同文档回调 A→B、nil→恢复及 provider 生命周期均已覆盖。
- [x] 运行直接 UIKit／SwiftUI 消费者与 pressed 绘制宿主测试；C2 最终定向 30／30、完整宿主 250／250并完成复审，C3/C4 回归继续保留。

### Task I1.4：真实 UI 手势与父容器

- [x] DemoSamples 提供 UIKit／SwiftUI 共用的 I1 文档：单行动作、跨行动作、相邻重复 ID、RTL、emoji、fi、可截断动作、装饰附件、interactive UIButton；事件与按钮分别显示状态。
- [x] 新增允许 didSelect 的最小 UITableView 夹具，并提供可观察的 selectionCount 与最后选择行。
- [x] XCUITest 使用真实布局坐标点击动作，覆盖重复 ID 不同范围、native UIButton 优先及装饰附件父动作。
- [x] XCUITest 使用 `coordinate.press(forDuration: 0.65)` 验证真实 longPress 至多一次，完成后不补发 tap。
- [x] XCUITest 使用 `press(forDuration: 0.05, thenDragTo:)` 验证动作拖出取消和列表真实滚动。
- [x] 真实点击普通文字、行尾／行间空白、inset／对齐留白与 onAction=nil 场景，验证父列表选择和动作互斥。
- [x] 以 Debug `@testable import` 的统一内部几何驱动 clipped action、token、RTL、emoji 和 fi 目标点；未新增 public／SPI 几何 API。
- [x] UIKit 与 SwiftUI 均覆盖 tap、长按、scroll 取消和 callback A→B；最终 UI 9／9。
- [x] 保存并检查 8 张仓库截图、最终 xcresult 导出的 6 张截图和 UIKit 跨行按下视频；真实触摸断言是结论。

### Task I1.5：验收、文档与自动交付

- [x] 在绘制 run 批处理质量修复后重新执行 `scripts/verify.sh docs`、固定 SwiftFormat 0.59.1 的 `scripts/verify.sh format`、`scripts/verify.sh build` 和 `scripts/verify.sh test 5260ADE6-ADC2-44AA-9EEB-CDEC90196D08`；最终 276 宿主＋18 UI = 294／294，0 failed／skipped／expected failures，`runtimeWarnings` 为空。
- [x] 更新 README、总计划 I1 状态与 `docs/verification/2026-10-20-interaction.md`，记录 Xcode／Swift／runtime／设备、红／绿、真正 XCUITest 行为和数量。
- [x] 明确 Swift 6.0 编译器、iOS 16 实际运行、真机与人工 VoiceOver 均未验证；当前新 SDK／Simulator 成功未替代这些结论。
- [ ] 验证通过后只提交本任务文件，中文 Conventional Commit；按 CONTRIBUTING 独占集成锁和候选验证流程合入本地 main，再普通 push 一次。push 失败保留本地成果与证据，不强推、不 pull/rebase，能独立继续的 H1 按连续队列继续。

## 7. 交付门槛与自审

I1 完成必须同时满足：精确可见片段命中、正确完整 UTF-16 range、同 ID 实例独立、一次 tap／longPress、所有取消零事件、foreground/background 真实颜色与恢复、无几何变化、interactive 附件只收自身、装饰附件可动作、普通区域不阻断列表选择／滚动、SwiftUI 同文档更新无旧回调、清理可重入且无组件持有循环。

自审映射：总计划 3 的 event/onAction 对应第 1 节；4.3 的 Unicode／双向／截断／无最近字符对应第 2 节和 I1.1；4.5 全部取消／长按／附件优先级对应第 3～4 节和 I1.2/I1.4；4.6 callback 刷新／拆卸／动态颜色对应第 1、5 节和 I1.3。A1 的动作无障碍与 H1 完整宿主矩阵明确未在本稿提前报告完成。
