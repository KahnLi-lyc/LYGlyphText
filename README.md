# LYGlyphText

面向 UIKit 与 SwiftUI 的只读富文本 Swift Package，使用纯 Swift 和 Core Text，零第三方运行依赖。最低部署目标 iOS 16，Swift tools 6.0／Swift 6 language mode。

当前提供基础显示闭环：**富文本文档 → Core Text 排版与绘制 → UIKit 自动撑高 → SwiftUI 展示**。尚未发布版本；本地构建与运行环境见 [验证记录](docs/verification/2026-10-20-basic-display.md)。Swift 6.0 编译器兼容和 iOS 16 实际运行仍未验证。

## 已实现

- MainActor 不可变 `LYGlyphTextDocument`：隔离复制输入字符串及段落样式。
- 字体、前景色、段落对齐和基本书写方向；缺省动态 body 字体和 label 颜色。显式字号保持固定。
- 多行单词换行、显式换行、中英文与 emoji、顶部对齐、内边距。
- Core Text 统一测量和绘制，每个 Label 最多缓存两份布局。
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
    label.configuration = .init(textContainerInset: .init(top: 8, left: 12, bottom: 8, right: 12))
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
        LYGlyphTextView(document: document)
            .frame(width: 240)
    }
}
```

`preferredMaxLayoutWidth` 包含内边距，仅影响固有高度估算；正值优先，其次正 bounds 宽度，最后使用保留显式换行的内容理想宽度。实际绘制总按 bounds。首次离屏测量应传入 required 横向宽度，避免依赖尚未确定的 frame。`sizeThatFits` 的高度参数不裁减完整内容的测量结果。

SwiftUI nil／无限宽度使用理想尺寸，有限宽度用于排版，0 返回安全的零宽结果。SwiftUI `layoutPriority` 由宿主管理，不映射为 UIKit 优先级。当前不保证与 UILabel 首／末文字基线对齐等价。

## 运行 Demo 和检查

需要 Xcode（含 iOS Simulator）、**XcodeGen 2.46.0**、Python 3；SwiftFormat 固定 **0.59.1**，安装或指定已有工具的方法见 [参与开发](CONTRIBUTING.md)。

```sh
scripts/verify.sh docs
scripts/verify.sh format
scripts/verify.sh build
scripts/verify.sh test <可用的独立模拟器UDID>
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

build 会生成 `Examples/LYGlyphTextDemo/LYGlyphTextDemo.xcodeproj`，构建 Package 和 Simulator 应用。打开该工程，选择 shared scheme **LYGlyphTextDemo**，运行后进入 UIKit 或 SwiftUI，切换短文／多行／混合样式和展示宽度。UIKit 另含富文本与按钮并排场景。工程生成物、构建日志和 xcresult 留在忽略目录内。

test 使用指定设备运行同一 scheme 的宿主单测和 UI 测试，零测试视为失败。Package 单测源码也由 Demo 宿主执行，避免用 macOS `swift test` 代替 UIKit 验证。

## 后续能力

尚未实现：图片／UIView 附件、局部点击、长按、高亮、行数限制和尾部省略、装饰属性、编辑、选择复制、HTML／Markdown 解析、异步渲染。标准 `.attachment` 和 U+FFFC 输入明确抛错；其他未支持的装饰属性不参与绘制。

当前已处理默认字体和语义颜色的 trait 更新；完整 Dynamic Type、RTL、VoiceOver、列表复用和最低系统验收继续按阶段推进。原生约束与 SwiftUI 基础尺寸适配已实现，不等于所有宿主组合均已验证。

## 文档与许可

- [总实施计划与阶段验收](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md)
- [本轮显示闭环与验证记录](docs/verification/2026-10-20-basic-display.md)
- [开发规则](AGENTS.md)、[编码规范](CODING_STYLE.md)、[贡献指南](CONTRIBUTING.md)
- [参考库来源、校验与借鉴边界](docs/REFERENCES.md)

技术路线采用 Core Text，首版不使用 TextKit 2。研究参考 [YYText](https://github.com/ibireme/YYText)、[BSText](https://github.com/nova286/BSText) 等；第三方源码留在仓库外，不作为运行依赖。本轮实现未移植第三方代码。原创内容采用 [MIT License](LICENSE)。
