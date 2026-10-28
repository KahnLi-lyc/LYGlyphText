# LYGlyphText

面向 UIKit 与 SwiftUI 的只读富文本 Swift Package，使用纯 Swift 和 Core Text，零第三方运行依赖。最低部署目标 iOS 16，Swift tools 6.0／Swift 6 language mode。

当前提供富文本样式、段落度量、分段／动作描述、自动撑高、**行数限制与可点击截断 token、行内图片、网络图片及 UIView 附件、文字点击／长按／按下反馈、长按选择拷贝、后台预排版与文本解析**，支持单词／字符换行和垂直对齐：文档 → Core Text 排版与绘制 → UIKit／SwiftUI 展示。尚未发布版本；验证环境和边界见各专项验证记录。Swift 6.0 编译器兼容和 iOS 16 实际运行仍未验证。

## 已实现

- MainActor 不可变 `LYGlyphTextDocument`：隔离复制输入字符串及段落样式。
- `init(segments:)` 自动累计 UTF-16 附件和动作范围；`actions` 输入校验非空 ID、完整字符边界及范围重叠。
- 字体、前景／背景色、字距、基线偏移、连字、下划线／删除线及段落度量；缺省动态 body 字体和 label 颜色。显式字号保持固定。
- 多行单词／字符换行、显式换行、中英文与 emoji、内边距及三种垂直对齐；证据见 [M1b 记录](docs/verification/2026-10-20-m1b-styles.md)。
- `configuration.numberOfLines`：0 或负值为无限行，正值限制显示行数；溢出时末行尾部显示 `…`。
- `LYGlyphTextAttachment`：UIImage 按明确的 point 尺寸参与换行，可相对占位字体区域顶部／居中／底部对齐；超宽部分裁切，不自动缩小。
- `LYGlyphTextViewAttachment` 与 MainActor provider：根据最终可见几何挂载宿主独占的 UIView，支持附件自身按钮；测量不调用工厂，隐藏后卸载释放。
- Core Text 统一测量、截断和绘制，内部保留可见原文 UTF-16 区间并单独标记生成的省略号；每个 Label 最多缓存两份布局。
- `intrinsicContentSize`、`sizeThatFits`、`preferredMaxLayoutWidth`、required 横向宽度的 `systemLayoutSizeFitting`。
- 标准 Content Hugging／Compression Resistance，内容更新不会重置宿主设置；外部限制高度时裁切。
- `LYGlyphTextLabel.onAction` 和 SwiftUI `onAction` 返回 tap／longPress、动作 ID、完整原文 UTF-16 范围及最终可见矩形；取消不发送事件。
- `LYGlyphTextView` 通过 UIViewRepresentable 复用 UIKit；直接使用 SwiftUI 宽度提议并在更新时使用最新动作回调。
- UIKit 横／纵向 StackView、UITableView 自动行高、UICollectionView self-sizing，以及 SwiftUI `.frame`／HStack／VStack／List／LazyVStack 的宿主矩阵；完整宿主／UI 验收见 [H1 记录](docs/verification/2026-10-21-host-matrix.md)。
- 最终可见内容的自动无障碍容器、动作激活及原生交互附件子树；人工 VoiceOver 尚未验收。
- UIKit／SwiftUI 可操作示例、组件行为测试、宿主测试和 UI 测试。

## 本地接入

在 Xcode 的 Add Local Package 中选择本仓库目录，将 **LYGlyphText** product 加到 iOS target。也可以在宿主 Package 中添加 `.package(path: "../LYGlyphText")`，并为宿主 target 添加 `.product(name: "LYGlyphText", package: "LYGlyphText")`。尚无可用的版本 Tag；不要使用版本号安装示例。

UIKit 示例，在主线程调用可抛错的文档构造方法：

```swift
import LYGlyphText
import UIKit

@MainActor
func installText(in container: UIView) throws {
    let input = NSAttributedString(
        string: "你好，GlyphText 👋\n这一段会根据可用宽度自动换行。",
        attributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.label]
    )
    let label = LYGlyphTextLabel(frame: .zero)
    label.onAction = { event in
        print(event.kind, event.actionID, event.range, event.visibleRects)
    }
    label.document = try LYGlyphTextDocument(
        attributedText: input,
        actions: [
            LYGlyphTextAction(
                actionID: "glyphtext",
                range: (input.string as NSString).range(of: "GlyphText")
            )
        ]
    )
    label.configuration = .init(
        textContainerInset: .init(top: 8, left: 12, bottom: 8, right: 12),
        numberOfLines: 3
    )
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        label.topAnchor.constraint(equalTo: container.topAnchor)
    ])
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
}
```

SwiftUI 接收同一份已构造文档：

```swift
import LYGlyphText
import SwiftUI

@MainActor
struct Example: View {
    let document: LYGlyphTextDocument

    var body: some View {
        LYGlyphTextView(
            document: document,
            configuration: .init(numberOfLines: 2),
            onAction: { event in print(event.kind, event.actionID) }
        )
            .frame(width: 240, alignment: .leading)
    }
}
```

`preferredMaxLayoutWidth` 包含内边距，仅影响固有高度估算；正值优先，其次正 bounds 宽度，最后使用保留显式换行的内容理想宽度。实际绘制总按 bounds。首次离屏测量应传入 required 横向宽度，避免依赖尚未确定的 frame。`sizeThatFits` 的高度遵守行数限制，忽略传入的高度上限。固有宽度仍来自完整内容的理想宽度。

显式换行（含末尾空行）计入行数；刚好容纳时不省略。生成的省略号继承最后可见行起点的字体和前景色。正宽度仅够省略号时只显示省略号，连省略号也放不下时保留该行高度但不绘制文字。外部高度裁切不触发额外省略号。

SwiftUI nil／无限宽度使用理想尺寸，有限非负宽度决定底层 Label 的实际宽度，0 返回安全的零宽结果。默认忽略高度提议并按内容撑高。SwiftUI `layoutPriority` 由宿主管理，不映射为 UIKit 优先级。当前不保证与 UILabel 首／末文字基线对齐等价；StackView 的 `.firstBaseline`／`.lastBaseline` 不在已验收矩阵内。

`configuration.verticalAlignment` 默认为 `.top`，可设 `.center`／`.bottom`。宿主外框比自然内容高时，文字、装饰及附件共用偏移；高度受压时偏移为 0，超出部分裁切。自然尺寸测量保持不变。

SwiftUI 需要额外高度或压缩展示时，使用显式的 `displayHeight`；单独给外层 `.frame(height:)` 不保证扩大底层 Label：

```swift
LYGlyphTextView(
    document: document,
    configuration: .init(verticalAlignment: .center),
    displayHeight: 160
)
.frame(width: 240)
```

`displayHeight` 单位为 point；nil／非有限／负值回退自然高度，有限非负值（含 0）指定展示高度。它不改变文本或附件的排版尺寸。

列表宿主应给出明确测量宽度和 cell `contentView` 的完整四边约束：UITableView 使用 `automaticDimension`，UICollectionView 使用 estimated size 并按 layout attributes 宽度进行 required 横向 fitting。宽度变化由宿主正常通知列表失效；组件不接管列表 delegate 或 layout。重绑先清旧回调、文档和 provider，再安装当前行输入。

H1 宿主测试覆盖 0→320→600→240→320 宽度往返、稳定布局收敛和最多两份布局缓存。两端使用相同文档、配置、有效宽度及 display scale 时，自然高度差不超过一个物理像素。此结论来自宿主行为测试，不代表首／末基线等价或所有系统版本均已验收。

## 显示环境与无障碍

缺省 `.font` 使用当前环境的动态 body；显式 UIFont（包括已创建的 preferredFont／UIFontMetrics 快照）保持固定。字号变化重新测量并重算附件对齐，图片与 UIView 声明尺寸不额外缩放。语义前景、背景、线色和按下色按当前 trait 解析；RTL 保留原文逻辑映射，图片不额外镜像。

Label 默认以容器提供最终可见内容的自动无障碍元素：按 UTF-16 逻辑顺序保留完整 grapheme，排除截断源与生成 token。图片／非交互 UIView 读取非空 alternativeText，nil／空白作装饰；已挂载的交互 UIView 保持原生子树及原有 AX 属性，不重复拼入文字动作。失败工厂可回退替代文本。

有 onAction 且存在可见内容的动作元素提供 button trait，accessibilityActivate 发送现有 tap 事件、完整原文范围及当前可见矩形；读取最新回调，先清按压，同步重入不重复发送。布局／文档／附件生命周期变化使旧元素失效，元素不保活宿主。宿主显式 accessibilityElements 数组（包括 []）优先，置 nil 恢复自动；组件不覆盖宿主自行设置的 AX 属性。

自动查询／激活与真实触摸均有测试，人工 VoiceOver 的朗读、停顿、重复朗读和焦点体验仍未验收。部分可见的原生附件保留 UIKit 子树；不保证任意原生后代 AX frame 按附件裁切。环境与截图证据见 [A1 专项记录](docs/verification/2026-10-21-environment-accessibility.md)。

## 字符样式与段落

支持的 NSAttributedString 属性在文档构造时保存为独立的类型化快照：

| 属性 | 行为 |
|---|---|
| `.font`、`.foregroundColor`、`.backgroundColor` | 字体、前景与背景；语义颜色按当前 traits 解析，背景不填满行距／段距 |
| `.kern`、`.baselineOffset` | point 字距及基线偏移；缺省 kern 不写入 Core Text key，显式 0 保留；普通有限负值允许 |
| `.ligature` | 接受 0／1／2，其余归默认 1；实际连字取决于字体 |
| `.underlineStyle`／`.underlineColor`、`.strikethroughStyle`／`.strikethroughColor` | none／single／thick／double，solid／dot／dash／dashDot／dashDotDot 及 byWord；缺省线色继承前景 |
| `.paragraphStyle` | 对齐、基本方向、行距、段前后距、首行／续行 headIndent、tailIndent、最小／最大行高及倍数 |

完整逻辑段落以第一个 UTF-16 字符的段落样式为准；段内后续冲突值不覆盖它。`configuration.wrapping` 默认为 `.word`，可设 `.character`，覆盖输入段落的 lineBreakMode。未列出的制表位、断词和其他属性不构成支持承诺。

非有限度量归缺省；有限负 minimum／maximum／multiple 归 0，非零 max 小于 min 时忽略 max。极端有限值若使内部坐标或像素精度失效，解析时归缺省；系统返回无效帧时最多以缺省可选度量重试一次。原文档快照不变，不保证任意负间距都能由系统原样显示。

背景、删除线及必要的下划线回退消费最终可见源片段，生成省略号不继承装饰。当前系统的原生 byWord 和 pattern 间隔未满足契约，因此由内部绘制；普通实线下划线保留 Core Text 路径。图片与 UIView 绘制在装饰上方。

内部片段保留实际 shaping。连字内部优先使用系统 caret；没有可用边界时按完整字符簇等分 advance，RTL 反向。此规则用于统一动作几何，不拆字形或禁用连字。按下绘制复用同一最终 CTLine 和预计算几何，图片与 UIView 附件不染色。

## 行内图片

以原文 UTF-16 位置将图片描述关联到单个 U+FFFC。尺寸由调用方明确提供，不从 UIImage 分辨率推导；默认 `.bottom`，对齐基于占位字符样式的字体 ascender／descender 区域。图片填充声明矩形，保留 UIImage 方向。

```swift
@MainActor
func imageDocument(image: UIImage) throws -> LYGlyphTextDocument {
    let text = NSAttributedString(string: "状态 \u{FFFC} 已完成", attributes: [.font: UIFont.systemFont(ofSize: 20)])
    return try LYGlyphTextDocument(attributedText: text, attachments: [
        3: LYGlyphTextAttachment(
            id: "status", image: image, size: CGSize(width: 24, height: 24),
            alignment: .center, alternativeText: "状态图标"
        )
    ])
}
```

文档拒绝未描述的 U+FFFC、越界或不匹配的位置、非独立占位字符、重复 ID 和非有限／非正尺寸；标准 `NSTextAttachment` 仍明确拒绝。未传附件字典的旧调用保持兼容。被省略的图片不绘制、不增加最终行高；生成省略号不继承附件属性。替换图片或声明尺寸时创建新文档，两端使用同一入口。非空 `alternativeText` 用于自动可见语义；人工 VoiceOver 的完整朗读与焦点体验尚未验收。

## 分段与动作描述

分段入口自动插入附件占位符并累计 UTF-16 位置，支持 `.text`、`.image` 和 `.view`；在 Document 初始化时建立快照。示例：

```swift
@MainActor
func segmentedDocument(image: UIImage) throws -> LYGlyphTextDocument {
    try LYGlyphTextDocument(segments: [
        .text(NSAttributedString(string: "😀 查看 ")),
        .image(
            LYGlyphTextAttachment(id: "detail-icon", image: image, size: CGSize(width: 20, height: 20)),
            actionID: "details"
        ),
        .text(NSAttributedString(string: "详情"), actionID: "details")
    ])
}
```

每个带 actionID 的片段产生独立动作，相邻同 ID 不合并；需要跨片段的单个动作时，使用 `init(attributedText:attachments:viewAttachments:actions:)` 并显式传入 `LYGlyphTextAction`。范围使用原文 UTF-16；从 Swift 范围转换应使用 `NSRange(swiftRange, in: originalText)`，文档仍会统一校验。

拒绝空 ID、空／负／越界／溢出范围、切开的组合字符（含 emoji、重音和 CRLF）及重叠动作；相邻范围和重复 ID 允许，ID 不裁剪或改变大小写。按下样式只保存可选前景／背景色，默认背景为 tertiarySystemFill，不改变字体或附件尺寸。

Label 仅在最终可见动作矩形内开始手势：抬起发送一次 tap，持续 0.5 秒发送一次 longPress；移动超过 10pt、滚动接管、第二触点、输入或显示几何变化、层级移除及 SwiftUI 拆卸都会取消并立即恢复普通绘制。事件范围始终是完整原文范围，`visibleRects` 只包含当前真实可见部分，不包含生成的省略号。交互 UIView 子树优先处理自身触摸；普通文字、行尾／行间空白和内边距仍交给宿主选择与滚动。

## 截断 token、圆角高亮与文字特效

```swift
label.configuration.numberOfLines = 3
label.configuration.truncationToken = LYGlyphTextTruncationToken(
    text: "…展开全文", foregroundColor: .systemBlue, actionID: "expand", pressedCornerRadius: 4
)
label.onAction = { event in
    if event.isTruncationToken { /* 展开 */ }
}
```

token 默认 nil 时仍为继承末行样式的 `…`；字体、颜色为 nil 时同样继承末行起点。token 是生成内容，事件 `range` 为 `NSRange(location: NSNotFound, length: 0)`；空间不足时整体省略。可交互 token 是最后一个无障碍按钮。`LYGlyphTextPressedStyle(cornerRadius:)` 让按下背景按行合并后绘制圆角。

文档额外读取 `.shadow`（NSShadow）、`.strokeWidth`／`.strokeColor`：阴影与描边只影响绘制，不改变测量；按下局部着色的字形部分不绘制阴影。`LYGlyphTextDocument(attributedText:..., linkPressedStyle:)` 可把 `.link` 范围转为动作，actionID 为 URL 字符串；默认 nil 时仍忽略 `.link`。未支持：头部／中间截断、整段点击回调（宿主可自行添加手势）。

## 整段点击

```swift
cell.label.onTap = { _ in openDetail() }
```

点按普通文字、行间空白或内边距时回调；点在动作、可点击截断 token、交互附件或已有选区上时不回调。未设置时不安装识别器，列表 cell 的选中行为不变；设置后单击由 Label 处理。

## 圆角背景与边框

```swift
let capsule = LYGlyphTextBackgroundStyle(
    fillColor: .systemBlue.withAlphaComponent(0.12), strokeColor: .systemBlue, strokeWidth: 1,
    cornerRadius: 4, padding: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
)
text.addAttribute(.lyGlyphTextBackground, value: capsule, range: topicRange)
// 或者交给解析器：LYGlyphTextParser(rules: [.topics(attributes: [.lyGlyphTextBackground: capsule])])
```

同一行内相邻且样式相等的片段合并成一个形状，跨行时每行各一段；绘制在普通背景之上、文字之下，不改变测量。外扩 `padding` 可能超出行高，必要时用行距或内边距留出空间。

## 行内 UIView

视图描述与 UIImage 描述分开；两类附件共享 UTF-16 占位、文档内唯一 ID 和明确尺寸校验。同一位置不能同时提供两种描述。工厂按 viewID 创建新的、尚未挂载的 UIView；不要在工厂闭包中强持有 Label。

```swift
@MainActor
func installButtonAttachment(on label: LYGlyphTextLabel) throws {
    label.viewProvider = LYGlyphTextAttachmentViewProvider(makeView: { description in
        guard description.viewID == "button" else { return nil }
        let button = UIButton(type: .system)
        button.setTitle("详情", for: .normal)
        button.addAction(UIAction { _ in print("打开详情") }, for: .touchUpInside)
        return button
    }, onUnmount: { _, view in
        // 已解除父子关系；按需停止由宿主管理的动画或任务。
        view.layer.removeAllAnimations()
    })
    label.document = try LYGlyphTextDocument(
        attributedText: NSAttributedString(string: "查看 \u{FFFC}"),
        viewAttachments: [
            3: LYGlyphTextViewAttachment(
                id: "detail", viewID: "button", size: CGSize(width: 64, height: 32),
                alignment: .center, alternativeText: "查看详情", isInteractive: true
            )
        ]
    )
}
```

工厂只在 Label 已进入 window 的展示布局中调用；所有尺寸测量与离屏布局不创建视图。附件外框由声明尺寸决定，不读取工厂视图的 intrinsicContentSize 反向排版。持续可见时复用，完全被裁切／省略后卸载，恢复时重新创建；部分可见时仅显示和响应裁切内区域。父列表的屏幕可见性由宿主的复用生命周期管理。

相同 provider 对象重赋值不重建；替换 provider 或调用 `reloadAttachments()` 显式刷新。nil／被拒绝的工厂结果在本次持续可见期间不重试。每次成功挂载对应一次原 provider 的 onUnmount，未挂载的失败结果没有卸载回调。文档清空保留 provider，移出 window 卸载，SwiftUI dismantle 同时清空文档和 provider。

SwiftUI 使用 `LYGlyphTextView(document: document, viewProvider: provider)`，将 provider 保存在稳定的宿主状态中，避免在 body 每次求值时创建新工厂对象。两个 Label 使用同一文档时，工厂必须分别返回独立视图。默认 isInteractive 为 false；true 允许附件自身控件／手势优先响应，父文字动作不重复发送。

## 网络图片

`LYGlyphTextRemoteImageAttachment` 以声明尺寸参与排版，附件可见并挂载后才通过 `imageLoader` 请求；离屏、复用、替换文档或移出 window 时取消。加载结果不改变排版，需要按真实宽高排版时用获得的尺寸重建文档。组件没有全局加载器实例，宿主创建并共享：

```swift
let loader = LYGlyphTextURLSessionImageLoader() // URLSession＋NSCache＋ImageIO，支持 GIF

@MainActor
func showAuthor(on label: LYGlyphTextLabel, avatar: URL) throws {
    label.imageLoader = loader
    label.document = try LYGlyphTextDocument(segments: [
        .remoteImage(.init(
            id: "avatar", url: avatar, size: CGSize(width: 20, height: 20),
            alignment: .center, placeholder: UIImage(systemName: "person.circle"), alternativeText: "作者头像"
        )),
        .text(NSAttributedString(string: " 作者名"))
    ])
}
```

已经使用 Kingfisher 的项目可以把下面的桥接复制到自己的工程，复用 Kingfisher 的磁盘／内存缓存（组件本身不依赖 Kingfisher）：

```swift
import Kingfisher
import LYGlyphText

@MainActor
final class KingfisherImageLoader: LYGlyphTextImageLoading {
    private final class Task: LYGlyphTextImageLoadingTask {
        let task: DownloadTask?
        init(_ task: DownloadTask?) { self.task = task }
        func cancel() { task?.cancel() }
    }

    func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask {
        let options: KingfisherOptionsInfo = [
            .processor(DownsamplingImageProcessor(size: targetSize)),
            .scaleFactor(scale),
            .callbackQueue(.mainCurrentOrAsync)
        ]
        let task = KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            MainActor.assumeIsolated {
                completion(result.map(\.image).mapError { $0 as any Error })
            }
        }
        return Task(task)
    }
}
```

需要按图片真实宽高排版时：

```swift
label.onRemoteImageLoad = { [weak self] id, imageSize in
    guard let self, let document = label.document else { return }
    let width = min(imageSize.width, maxWidth)
    let size = CGSize(width: width, height: width * imageSize.height / imageSize.width)
    model.document = try? document.replacingRemoteImageSize(id: id, size: size)
    // 刷新对应列表行高
}
```

组件不会在加载后自行改变排版，保持测量稳定。取消后组件会忽略迟到的回调。内置加载器没有磁盘缓存；动图最多保留 300 帧。本仓不依赖 Kingfisher，上述桥接示例按其公开 API 编写，没有在本仓编译；协议本身由测试中的模拟加载器完整覆盖。

## 列表预排版

长文本首次测量的主要成本在 Core Text 排版。数据到达时可在后台预排版，拿到行高后再交给 cell：

```swift
let prepared = await LYGlyphTextPreparedLayout.prepare(
    document: document, configuration: configuration, width: tableWidth,
    traitCollection: tableView.traitCollection
)
rowHeights[id] = prepared.size.height   // 文字部分高度，含内边距

// cellForRow 中
cell.label.apply(prepared)               // 环境一致时主线程不再排版
```

结果只对相同文档对象、配置、宽度和显示环境有效；字号类别、明暗或显示比例变化后 Label 自动按普通路径重新排版。预排版不创建附件视图、不调用工厂或图片加载器。

## 选择与拷贝

```swift
label.isSelectable = true
label.onSelectionChange = { range in print(range as Any) }
```

SwiftUI 使用 `LYGlyphTextView(document:configuration:viewProvider:imageLoader:displayHeight:isSelectable:onAction:onSelectionChange:)`，新增参数均有默认值；截断 token 通过 `configuration` 传入。

长按非动作文字选中所在单词并显示系统编辑菜单（拷贝、全选），拖动两端拖柄调整范围；动作与可点击截断 token 优先响应。拷贝写入纯文本，附件输出替代文本。`selectedRange` 使用原文 UTF-16 并扩展到完整组合字符；全选只包含可见原文。拷贝同时写入纯文本与 RTF 富文本；iOS 17+ 拖动拖柄时显示系统放大镜（iOS 16 没有）；有选区时文字无障碍元素提供“拷贝”自定义动作，名称可用 `selectionCopyAccessibilityName` 替换。不支持编辑。

## 文本解析

```swift
let parser = LYGlyphTextParser(rules: [
    .emoticons(["[微笑]": smileImage], size: CGSize(width: 18, height: 18)),
    .links(), .mentions(), .topics()
])
label.document = try parser.document(from: NSAttributedString(string: "[微笑] @小明 #春天# https://example.com"))
label.onAction = { event in
    // event.actionID: "mention:小明"、"topic:春天" 或 URL 字符串
}
```

先替换表情短码为图片附件，再按规则顺序识别；重叠时前面的规则优先。`.pattern(_:actionID:)` 支持自定义正则。

## 运行 Demo 和检查

需要 Xcode（含 iOS Simulator）、**XcodeGen 2.46.0**、Python 3；SwiftFormat 固定 **0.59.1**，安装或指定已有工具的方法见 [参与开发](CONTRIBUTING.md)。

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test <可用的独立模拟器UDID>
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

build 会生成 `Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj`，构建 Package 和 Simulator 应用。打开该工程，选择 shared scheme **LYGlyphTextDemo**，运行后进入 UIKit 或 SwiftUI，切换短文／多行／混合样式／显式换行、文字／图片混排／UIView、三种附件对齐、展示宽度及无限行／1 行／2 行／3 行。UIView 模式包含 UIImageView、原生按钮、自定义徽章和 nil 工厂占位，提供清空／重载；动作示例覆盖 tap、长按、滚动取消、回调替换、截断与短高度裁切；首页另有可选择的 UITableView 动作夹具和附件复用示例；UIKit／SwiftUI 宿主矩阵页提供 StackView／五种 SwiftUI 容器、Table／Collection、宽度往返、附件尺寸、按钮与回调切换。环境与无障碍页还提供三档真实字号、浅深、LTR／RTL、宽度、行数和回调控制；两端共用本地生成的方向箭头图片与文档，无网络依赖。工程生成物、构建日志和 xcresult 留在忽略目录内。

test 使用指定设备运行同一 scheme 的宿主单测和 UI 测试，零测试视为失败。Package 单测源码也由 Demo 宿主执行，避免用 macOS `swift test` 代替 UIKit 验证。

固定负载页面提供 180 行（九组输入各 20 行）的真实 UITableView，文字动作、原生附件按钮及停止清空控制用于观察复用；性能数据及其构建配置以 [P1 验证记录](docs/verification/2026-10-21-performance-readiness.md)为准。模拟器观测不代表真机性能，首版仍未发布。

## 后续能力

[2.x Label 路线图](docs/superpowers/plans/2026-10-21-label-roadmap.md) G1—G7 已交付可点击截断 token、按下圆角、阴影／描边、`.link` 转动作、网络图片、后台预排版、选择拷贝、文本解析与对应 SwiftUI 参数，结果见各阶段验证记录。尚未实现：编辑器、头部／中间截断、整段点击回调、异步绘制、放大镜、HTML／Markdown 解析。标准 `.attachment` 仍明确抛错；其他未支持的装饰属性不参与绘制。H1 宿主矩阵已通过 298 项宿主＋21 项 UI 的完整回归；A1 已补自动可见语义和动作激活，完整回归与人工状态见 A1 记录。

当前已处理动态 body、语义颜色与 RTL 的环境继承及自动 AX 语义；人工 VoiceOver 和最低系统验收继续独立留证。宿主适配范围和列表复用证据见 H1 记录，不推广为未测试容器或运行环境的保证。

## 文档与许可

- [总实施计划与阶段验收](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md)
- [连续开发规则与执行契约](docs/superpowers/plans/2026-10-20-continuous-development.md)
- [分段与动作描述验证记录](docs/verification/2026-10-20-m1a-document.md)
- [文字交互验证记录](docs/verification/2026-10-20-interaction.md)
- [宿主矩阵验证记录](docs/verification/2026-10-21-host-matrix.md)
- [显示环境与无障碍验证记录](docs/verification/2026-10-21-environment-accessibility.md)
- [固定负载与性能验证记录](docs/verification/2026-10-21-performance-readiness.md)
- [发布准备与未验证门槛](docs/RELEASE_READINESS.md)、[未发布变更草案](CHANGELOG.md)
- [UIView 附件与生命周期验证记录](docs/verification/2026-10-20-view-attachments.md)
- [行内图片附件验证记录](docs/verification/2026-10-20-image-attachments.md)
- [行数限制与尾部省略验证记录](docs/verification/2026-10-20-line-limits.md)
- [基础显示闭环与验证记录](docs/verification/2026-10-20-basic-display.md)
- [开发规则](AGENTS.md)、[编码规范](CODING_STYLE.md)、[贡献指南](CONTRIBUTING.md)
- [参考库来源、校验与借鉴边界](docs/REFERENCES.md)

技术路线采用 Core Text，首版不使用 TextKit 2。研究参考 [YYText](https://github.com/ibireme/YYText)、[BSText](https://github.com/nova286/BSText) 等；第三方源码留在仓库外，不作为运行依赖。本轮实现未移植第三方代码。原创内容采用 [MIT License](LICENSE)。

P1正式回归为368／368（344宿主＋24UI），保留全部既有覆盖；86个Swift文件前后冻结一致。发布环境与人工补证状态见[发布准备](docs/RELEASE_READINESS.md)，尚无版本Tag或Release。
