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

@MainActor
enum ImageAlignment: Int, CaseIterable {
    case top, center, bottom

    var title: String {
        switch self {
        case .top: "顶部"
        case .center: "居中"
        case .bottom: "底部"
        }
    }

    var attachmentAlignment: LYGlyphTextAttachmentAlignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

/// UIKit 与 SwiftUI 共用输入；显式字体固定字号，颜色使用系统语义颜色。
@MainActor
final class DemoSamples {
    private enum SampleError: Error {
        case missingGeneratedImage
    }

    let reuseDocuments: [LYGlyphTextDocument]
    let documents: [SampleKind: LYGlyphTextDocument]
    private let viewDocuments: [SampleKind: [ImageAlignment: LYGlyphTextDocument]]
    private let imageDocuments: [SampleKind: [ImageAlignment: LYGlyphTextDocument]]

    init() throws {
        reuseDocuments = try (0 ..< 80).map { row in
            try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: "\u{FFFC} 第 \(row) 行：滚动离屏后由列表宿主清理，再绑定新文档。\n同一 Cell 的按钮与文字必须属于当前行。",
                attributes: [.font: UIFont.systemFont(ofSize: 18)]
            ), viewAttachments: [0: LYGlyphTextViewAttachment(
                id: "row-\(row)", viewID: "button", size: CGSize(width: 100, height: 36), isInteractive: true
            )])
        }
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
        let texts: [SampleKind: NSAttributedString] = [
            .short: short, .multiline: multiline, .mixed: mixed, .newlines: newlines
        ]
        documents = try texts.mapValues { try LYGlyphTextDocument(attributedText: $0) }
        let image = Self.makeDirectionImage()
        guard let cgImage = image.cgImage else { throw SampleError.missingGeneratedImage }
        let rotatedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .right)
        imageDocuments = try texts.mapValues { text in
            let prefix = NSMutableAttributedString(
                string: "上 \u{FFFC} 右 \u{FFFC} ",
                attributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.label]
            )
            prefix.append(text)
            return try Dictionary(uniqueKeysWithValues: ImageAlignment.allCases.map { alignment in
                let attachments = [
                    2: LYGlyphTextAttachment(
                        id: "up", image: image, size: CGSize(width: 32, height: 44),
                        alignment: alignment.attachmentAlignment, alternativeText: "箭头朝上，橙色标记在左上"
                    ),
                    6: LYGlyphTextAttachment(
                        id: "right", image: rotatedImage, size: CGSize(width: 44, height: 32),
                        alignment: alignment.attachmentAlignment, alternativeText: "箭头朝右，橙色标记在右上"
                    )
                ]
                return try (alignment, LYGlyphTextDocument(attributedText: prefix, attachments: attachments))
            })
        }
        viewDocuments = try texts.mapValues { text in
            let prefix = NSMutableAttributedString(
                string: "\u{FFFC} \u{FFFC} \u{FFFC} \u{FFFC}\n",
                attributes: [.font: UIFont.systemFont(ofSize: 20)]
            )
            prefix.append(text)
            return try Dictionary(uniqueKeysWithValues: ImageAlignment.allCases.map { alignment in
                let attachments = [
                    0: LYGlyphTextViewAttachment(
                        id: "avatar", viewID: "image", size: CGSize(width: 28, height: 36),
                        alignment: alignment.attachmentAlignment, alternativeText: "本地星星"
                    ),
                    2: LYGlyphTextViewAttachment(
                        id: "button", viewID: "button", size: CGSize(width: 76, height: 36),
                        alignment: alignment.attachmentAlignment, alternativeText: "计数按钮", isInteractive: true
                    ),
                    4: LYGlyphTextViewAttachment(
                        id: "badge", viewID: "badge", size: CGSize(width: 52, height: 24),
                        alignment: alignment.attachmentAlignment, alternativeText: "徽章"
                    ),
                    6: LYGlyphTextViewAttachment(
                        id: "missing", viewID: "missing", size: CGSize(width: 20, height: 20),
                        alignment: alignment.attachmentAlignment, alternativeText: "空工厂保留空间"
                    )
                ]
                return try (alignment, LYGlyphTextDocument(attributedText: prefix, viewAttachments: attachments))
            })
        }
    }

    func document(for kind: SampleKind, includesImages: Bool, alignment: ImageAlignment) -> LYGlyphTextDocument? {
        includesImages ? imageDocuments[kind]?[alignment] : documents[kind]
    }

    func viewDocument(for kind: SampleKind, alignment: ImageAlignment) -> LYGlyphTextDocument? {
        viewDocuments[kind]?[alignment]
    }

    /// 本地绘制的非对称图片；右向版本仅改变 UIImage 方向，便于检查方向和基线。
    private static func makeDirectionImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 44), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 44))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 9, height: 9))
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: 16, y: 8))
            arrow.addLine(to: CGPoint(x: 27, y: 21))
            arrow.addLine(to: CGPoint(x: 20, y: 21))
            arrow.addLine(to: CGPoint(x: 20, y: 37))
            arrow.addLine(to: CGPoint(x: 12, y: 37))
            arrow.addLine(to: CGPoint(x: 12, y: 21))
            arrow.addLine(to: CGPoint(x: 5, y: 21))
            arrow.close()
            UIColor.black.setFill()
            arrow.fill()
        }
    }
}
