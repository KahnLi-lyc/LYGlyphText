# LYGlyphText

面向 UIKit 与 SwiftUI 的只读富文本 Swift Package，使用纯 Swift 和 Core Text，零第三方运行依赖。最低部署目标 iOS 16，Swift tools 6.0／Swift 6 language mode。

当前提供富文本显示、自动撑高、**行数限制／尾部省略、行内图片及 UIView 附件**：文档 → Core Text 排版与绘制 → UIKit／SwiftUI 展示。尚未发布版本；验证环境和边界见各专项验证记录。Swift 6.0 编译器兼容和 iOS 16 实际运行仍未验证。

## 已实现

- MainActor 不可变 `LYGlyphTextDocument`：隔离复制输入字符串及段落样式。
- 字体、前景色、段落对齐和基本书写方向；缺省动态 body 字体和 label 颜色。显式字号保持固定。
- 多行单词换行、显式换行、中英文与 emoji、顶部对齐、内边距。
- `configuration.numberOfLines`：0 或负值为无限行，正值限制显示行数；溢出时末行尾部显示 `…`。
- `LYGlyphTextAttachment`：UIImage 按明确的 point 尺寸参与换行，可相对占位字体区域顶部／居中／底部对齐；超宽部分裁切，不自动缩小。
- `LYGlyphTextViewAttachment` 与 MainActor provider：根据最终可见几何挂载宿主独占的 UIView，支持附件自身按钮；测量不调用工厂，隐藏后卸载释放。
- Core Text 统一测量、截断和绘制，内部保留可见原文 UTF-16 区间并单独标记生成的省略号；每个 Label 最多缓存两份布局。
- `intrinsicContentSize`、`sizeThatFits`、`preferredMaxLayoutWidth`、required 横向宽度的 `systemLayoutSizeFitting`。
- 标准 Content Hugging／Compression Resistance，内容更新不会重置宿主设置；外部限制高度时裁切。
- `LYGlyphTextView` 通过 UIViewRepresentable 复用 UIKit；直接使用 SwiftUI 宽度提议。
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
    label.document = try LYGlyphTextDocument(attributedText: input)
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
        LYGlyphTextView(document: document, configuration: .init(numberOfLines: 2))
            .frame(width: 240, alignment: .leading)
    }
}
```

`preferredMaxLayoutWidth` 包含内边距，仅影响固有高度估算；正值优先，其次正 bounds 宽度，最后使用保留显式换行的内容理想宽度。实际绘制总按 bounds。首次离屏测量应传入 required 横向宽度，避免依赖尚未确定的 frame。`sizeThatFits` 的高度遵守行数限制，忽略传入的高度上限。固有宽度仍来自完整内容的理想宽度。

显式换行（含末尾空行）计入行数；刚好容纳时不省略。生成的省略号继承最后可见行起点的字体和前景色。正宽度仅够省略号时只显示省略号，连省略号也放不下时保留该行高度但不绘制文字。外部高度裁切不触发额外省略号。

SwiftUI nil／无限宽度使用理想尺寸，有限宽度用于排版，0 返回安全的零宽结果。SwiftUI `layoutPriority` 由宿主管理，不映射为 UIKit 优先级。当前不保证与 UILabel 首／末文字基线对齐等价。

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

文档拒绝未描述的 U+FFFC、越界或不匹配的位置、非独立占位字符、重复 ID 和非有限／非正尺寸；标准 `NSTextAttachment` 仍明确拒绝。未传附件字典的旧调用保持兼容。被省略的图片不绘制、不增加最终行高；生成省略号不继承附件属性。替换图片或声明尺寸时创建新文档，两端使用同一入口。`alternativeText` 当前只保存描述数据，完整 VoiceOver 行内语义尚未验收。

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

SwiftUI 使用 `LYGlyphTextView(document: document, viewProvider: provider)`，将 provider 保存在稳定的宿主状态中，避免在 body 每次求值时创建新工厂对象。两个 Label 使用同一文档时，工厂必须分别返回独立视图。默认 isInteractive 为 false；true 仅允许附件自身控件／手势响应，文字动作仍待后续实现。

## 运行 Demo 和检查

需要 Xcode（含 iOS Simulator）、**XcodeGen 2.46.0**、Python 3；SwiftFormat 固定 **0.59.1**，安装或指定已有工具的方法见 [参与开发](CONTRIBUTING.md)。

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test <可用的独立模拟器UDID>
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

build 会生成 `Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj`，构建 Package 和 Simulator 应用。打开该工程，选择 shared scheme **LYGlyphTextDemo**，运行后进入 UIKit 或 SwiftUI，切换短文／多行／混合样式／显式换行、文字／图片混排／UIView、三种附件对齐、展示宽度及无限行／1 行／2 行／3 行。UIView 模式包含 UIImageView、原生按钮、自定义徽章和 nil 工厂占位，提供清空／重载；首页另有 UITableView 复用示例。两端共用本地生成的方向箭头图片与文档，无网络依赖；UIKit 另含富文本与按钮并排场景。工程生成物、构建日志和 xcresult 留在忽略目录内。

test 使用指定设备运行同一 scheme 的宿主单测和 UI 测试，零测试视为失败。Package 单测源码也由 Demo 宿主执行，避免用 macOS `swift test` 代替 UIKit 验证。

## 后续能力

尚未实现：文字局部点击、长按、高亮和装饰属性。编辑、选择复制、HTML／Markdown 解析及异步渲染不属于首版范围。标准 `.attachment` 仍明确抛错；其他未支持的装饰属性不参与绘制。

当前已处理默认字体和语义颜色的 trait 更新；完整 Dynamic Type、RTL、VoiceOver、列表复用和最低系统验收继续按阶段推进。原生约束与 SwiftUI 基础尺寸适配已实现，不等于所有宿主组合均已验证。

## 文档与许可

- [总实施计划与阶段验收](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md)
- [连续开发规则与执行契约](docs/superpowers/plans/2026-10-20-continuous-development.md)
- [UIView 附件与生命周期验证记录](docs/verification/2026-10-20-view-attachments.md)
- [行内图片附件验证记录](docs/verification/2026-10-20-image-attachments.md)
- [行数限制与尾部省略验证记录](docs/verification/2026-10-20-line-limits.md)
- [基础显示闭环与验证记录](docs/verification/2026-10-20-basic-display.md)
- [开发规则](AGENTS.md)、[编码规范](CODING_STYLE.md)、[贡献指南](CONTRIBUTING.md)
- [参考库来源、校验与借鉴边界](docs/REFERENCES.md)

技术路线采用 Core Text，首版不使用 TextKit 2。研究参考 [YYText](https://github.com/ibireme/YYText)、[BSText](https://github.com/nova286/BSText) 等；第三方源码留在仓库外，不作为运行依赖。本轮实现未移植第三方代码。原创内容采用 [MIT License](LICENSE)。
