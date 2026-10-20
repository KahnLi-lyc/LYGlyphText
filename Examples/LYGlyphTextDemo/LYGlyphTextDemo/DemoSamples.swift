import LYGlyphText
import UIKit

@MainActor
enum SampleKind: Int, CaseIterable {
    case short, multiline, mixed, newlines

    var title: String {
        switch self {
        case .short: "短文"
        case .multiline: "多行"
        case .mixed: "混合样式"
        case .newlines: "显式换行"
        }
    }
}

@MainActor
enum LineLimit: Int, CaseIterable {
    case unlimited = 0, one, two, three

    var title: String {
        self == .unlimited ? "无限行" : "\(rawValue) 行"
    }
}

/// UIKit 与 SwiftUI 共用输入；显式字体固定字号，颜色使用系统语义颜色。
@MainActor
final class DemoSamples {
    let documents: [SampleKind: LYGlyphTextDocument]

    init() throws {
        let short = NSAttributedString(string: "你好，GlyphText 👋")
        let multiline = NSAttributedString(
            string: "Core Text 负责统一排版和绘制。调整宽度，观察中英文换行与内容自动撑高。\n第二段保留显式换行：Swift 6 · UIKit · SwiftUI，家庭 👨‍👩‍👧‍👦，组合字符 e\u{301}。"
        )
        let mixed = NSMutableAttributedString(
            string: "混合样式 / Rich Text\n",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.systemIndigo]
        )
        mixed.append(NSAttributedString(
            string: "这里使用较小的字体和语义颜色。宽度变化后，测量和绘制共享同一份布局。\n",
            attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.secondaryLabel]
        ))
        mixed.append(NSAttributedString(
            string: "重点文字 · 中文 English 😀",
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.systemOrange
            ]
        ))
        let newlines = NSAttributedString(
            string: "第一行保留显式换行。\n\n第三行之前是空行。\n第四行：中英文 English 👨‍👩‍👧‍👦。\n"
        )
        documents = try [
            .short: LYGlyphTextDocument(attributedText: short),
            .multiline: LYGlyphTextDocument(attributedText: multiline),
            .mixed: LYGlyphTextDocument(attributedText: mixed),
            .newlines: LYGlyphTextDocument(attributedText: newlines)
        ]
    }
}
