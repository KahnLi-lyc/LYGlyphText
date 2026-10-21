import Combine
import LYGlyphText
import SwiftUI
import UIKit

/// 两端共享同一个不可变文档，不为字号、颜色或方向重新构造输入。
@MainActor
final class EnvironmentSamples {
    let document: LYGlyphTextDocument
    static let actionTitle = "执行文字动作"
    static let hiddenText = "末尾可见性标记"

    init() throws {
        let source = "环境 中文 😀 مرحبا\n执行文字动作\n附件操作 \u{FFFC} 继续\n方向图片 \u{FFFC}\n混合内容随系统字号换行，保持语义颜色与原生附件。\n末尾可见性标记"
        let text = NSMutableAttributedString(string: source, attributes: [
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.secondarySystemBackground
        ])
        let actionRange = (source as NSString).range(of: Self.actionTitle)
        text.addAttributes([
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: UIColor.systemTeal
        ], range: actionRange)
        let buttonRange = (source as NSString).range(of: "附件操作 \u{FFFC} 继续")
        let buttonLocation = (source as NSString).range(of: "\u{FFFC}").location
        let imageLocation = (source as NSString).range(of: "\u{FFFC}", options: .backwards).location
        let image = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 26)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 36, height: 26))
            UIColor.systemBlue.setFill()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: 4, y: 5))
            arrow.addLine(to: CGPoint(x: 22, y: 5))
            arrow.addLine(to: CGPoint(x: 22, y: 1))
            arrow.addLine(to: CGPoint(x: 33, y: 13))
            arrow.addLine(to: CGPoint(x: 22, y: 25))
            arrow.addLine(to: CGPoint(x: 22, y: 20))
            arrow.addLine(to: CGPoint(x: 4, y: 20))
            arrow.close()
            arrow.fill()
            UIColor.white.setFill()
            context.fill(CGRect(x: 5, y: 6, width: 4, height: 4))
        }
        let pressed = LYGlyphTextPressedStyle(foregroundColor: .systemBackground, backgroundColor: .label)
        document = try LYGlyphTextDocument(
            attributedText: text,
            attachments: [imageLocation: .init(
                id: "environment-direction", image: image, size: CGSize(width: 36, height: 26),
                alternativeText: "向右箭头，左上白点"
            )],
            viewAttachments: [buttonLocation: .init(
                id: "environment-native", viewID: "button", size: CGSize(width: 90, height: 32),
                alternativeText: "原生按钮", isInteractive: true
            )],
            actions: [
                .init(actionID: "environment-text", range: actionRange, pressedStyle: pressed),
                .init(actionID: "environment-attachment", range: buttonRange, pressedStyle: pressed)
            ]
        )
    }
}

@MainActor
struct EnvironmentSelection {
    var sizeIndex = 0
    var isDark = false
    var isRTL = false
    var width = 320
    var isSingleLine = false
    var callback = "A"

    var category: UIContentSizeCategory {
        [.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge][sizeIndex]
    }

    var dynamicSize: DynamicTypeSize {
        [.large, .xxxLarge, .accessibility5][sizeIndex]
    }

    var configuration: LYGlyphTextConfiguration {
        .init(textContainerInset: .init(top: 8, left: 8, bottom: 8, right: 8), numberOfLines: isSingleLine ? 1 : 0)
    }

    var status: String {
        "size=\(["L", "XXXL", "AX5"][sizeIndex]);\(isDark ? "Dark" : "Light");\(isRTL ? "RTL" : "LTR");width=\(width);lines=\(isSingleLine ? "1" : "all");callback=\(callback)"
    }
}

@MainActor
final class EnvironmentEventState: ObservableObject {
    @Published private(set) var actionCount = 0
    @Published private(set) var buttonCount = 0
    @Published private(set) var handled = "none"
    @Published private(set) var actionID = "none"
    var onChange: (() -> Void)?
    lazy var provider = LYGlyphTextAttachmentViewProvider { [weak self] _ in
        guard let self else { return nil }
        let button = UIButton(type: .system)
        button.setTitle("原生按钮", for: .normal)
        button.accessibilityIdentifier = "environmentNativeButton"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            buttonCount += 1
            onChange?()
        }, for: .touchUpInside)
        return button
    }

    var status: String {
        "event=\(actionCount);button=\(buttonCount);handled=\(handled);id=\(actionID)"
    }

    func receive(_ event: LYGlyphTextActionEvent, callback: String) {
        actionCount += 1
        handled = callback
        actionID = event.actionID
        onChange?()
    }
}
