import LYGlyphText
import SwiftUI
import UIKit

@MainActor
enum StyleSample: Int, CaseIterable {
    case decorations, paragraphs

    var title: String {
        self == .decorations ? "装饰混排" : "混合段落"
    }
}

@MainActor
enum StyleWrapping: Int, CaseIterable {
    case word, character

    var title: String {
        self == .word ? "单词" : "字符"
    }

    var wrapping: LYGlyphTextConfiguration.Wrapping {
        self == .word ? .word : .character
    }
}

@MainActor
enum StyleVerticalAlignment: Int, CaseIterable {
    case top, center, bottom

    var title: String {
        switch self {
        case .top: "顶部"
        case .center: "居中"
        case .bottom: "底部"
        }
    }

    var alignment: LYGlyphTextConfiguration.VerticalAlignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

/// 两端持有相同文档实例；自然高度预览与加高预览仅有展示高度的差别。
@MainActor
final class StyleDemoSamples {
    let documents: [StyleSample: LYGlyphTextDocument]

    init() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 22, height: 22))
            UIColor.white.setFill()
            context.fill(CGRect(x: 4, y: 4, width: 5, height: 5))
        }
        var documents: [StyleSample: LYGlyphTextDocument] = [:]
        for kind in StyleSample.allCases {
            let text = NSMutableAttributedString(string: "\u{FFFC} \u{FFFC} ", attributes: [
                .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label
            ])
            if kind == .decorations {
                text.append(NSAttributedString(string: "Colorful words 中文\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 19, weight: .semibold),
                    .foregroundColor: UIColor.systemIndigo,
                    .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3), .kern: 0.5,
                    .underlineStyle: NSUnderlineStyle.single.union(.patternDash).rawValue,
                    .underlineColor: UIColor.systemTeal
                ]))
                text.append(NSAttributedString(string: "删除线与抬升 baseline，longwordabcdefgh 中文换行。", attributes: [
                    .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.label,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: UIColor.systemPink, .baselineOffset: 2
                ]))
            } else {
                let first = NSMutableParagraphStyle()
                first.firstLineHeadIndent = 4
                first.headIndent = 12
                first.tailIndent = -4
                first.lineSpacing = 3
                first.paragraphSpacing = 8
                text.append(NSAttributedString(string: "First paragraph wordsabcdefgh 中文段落。\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.systemIndigo,
                    .paragraphStyle: first
                ]))
                text.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: 4))
                let second = NSMutableParagraphStyle()
                second.alignment = .right
                second.baseWritingDirection = .rightToLeft
                second.lineSpacing = 2
                text.append(NSAttributedString(string: "مرحبا بالعالم · 第二段 English", attributes: [
                    .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.systemTeal,
                    .paragraphStyle: second, .backgroundColor: UIColor.systemTeal.withAlphaComponent(0.12)
                ]))
            }
            documents[kind] = try LYGlyphTextDocument(
                attributedText: text,
                attachments: [2: .init(id: "style-image", image: image, size: CGSize(width: 22, height: 22))],
                viewAttachments: [0: .init(
                    id: "style-button", viewID: "button", size: CGSize(width: 78, height: 30), isInteractive: true
                )]
            )
        }
        self.documents = documents
    }
}

@MainActor
final class StyleDemoModel: ObservableObject {
    let samples: StyleDemoSamples
    @Published var sample = StyleSample.decorations
    @Published var wrapping = StyleWrapping.word
    @Published var verticalAlignment = StyleVerticalAlignment.top
    @Published var width = 240
    @Published var lineLimit = LineLimit.two
    @Published var isCleared = false
    private let measureLabel = LYGlyphTextLabel(frame: .zero)

    init(samples: StyleDemoSamples) {
        self.samples = samples
    }

    var document: LYGlyphTextDocument? {
        isCleared ? nil : samples.documents[sample]
    }

    var configuration: LYGlyphTextConfiguration {
        .init(
            textContainerInset: UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8),
            numberOfLines: lineLimit.rawValue, wrapping: wrapping.wrapping,
            verticalAlignment: verticalAlignment.alignment
        )
    }

    var naturalHeight: CGFloat {
        measureLabel.document = document
        measureLabel.configuration = configuration
        return measureLabel.sizeThatFits(CGSize(width: CGFloat(width), height: .infinity)).height
    }

    var status: String {
        "\(sample.title) · \(wrapping.title) · \(verticalAlignment.title) · 宽度 \(width) · \(lineLimit.title)"
    }
}
