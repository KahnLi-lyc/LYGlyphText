import LYGlyphText
import UIKit

/// 固定负载输入，不缓存 Document；构造与排版可分别计时。
@MainActor
struct PerformanceSample {
    struct Metadata: Codable, Equatable {
        let id: String
        let utf16Length: Int
        let attachmentCount: Int
        let imageLocations: [Int]
        let viewLocations: [Int]
        let scripts: [String]
        let fontName: String
        let fontPointSize: Double
        let width: Double
        let attachmentSide: Double
        let numberOfLines: Int
        let wrapping: String
        let verticalAlignment: String
        let textContainerInsets: [Double]
    }

    let metadata: Metadata
    let attributedText: NSAttributedString
    let attachments: [Int: LYGlyphTextAttachment]
    let viewAttachments: [Int: LYGlyphTextViewAttachment]
    let actions: [LYGlyphTextAction]
    let configuration = LYGlyphTextConfiguration()

    func makeDocument() throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(
            attributedText: attributedText, attachments: attachments,
            viewAttachments: viewAttachments, actions: actions
        )
    }
}

/// 纯本地、完整组合字符的九组不可变输入；源位置均使用 UTF-16。
@MainActor
final class PerformanceSamples {
    let samples: [PerformanceSample]

    init() {
        let font = UIFont.systemFont(ofSize: 20)
        let image = Self.makeImage()
        samples = [100, 1000, 5000].flatMap { length in
            [0, 3, 10].map { count in
                Self.makeSample(length: length, count: count, font: font, image: image)
            }
        }
    }

    private static func makeSample(length: Int, count: Int, font: UIFont, image: UIImage) -> PerformanceSample {
        let id = "utf16-\(length)-attachments-\(count)"
        let size = CGSize(width: 24, height: 24)
        var source = "执行 "
        var attachments: [Int: LYGlyphTextAttachment] = [:]
        var views: [Int: LYGlyphTextViewAttachment] = [:]
        for index in 0 ..< count {
            let location = source.utf16.count
            source.append("\u{FFFC}")
            // 第一个附件始终是按钮，三行省略后仍可验证原生交互。
            let isView = count == 3 ? index == 0 : index.isMultiple(of: 2)
            if isView {
                views[location] = .init(
                    id: "\(id)-view-\(index)", viewID: "performance-button", size: size,
                    alternativeText: "性能按钮 \(index)", isInteractive: true
                )
            } else {
                attachments[location] = .init(
                    id: "\(id)-image-\(index)", image: image, size: size,
                    alternativeText: "本地性能图片 \(index)"
                )
            }
        }
        source += " 中文😀 مرحبا Latin "
        let characters = Array("中文 😀 مرحبا Latin · ")
        var units = source.utf16.count
        var cursor = 0
        while units < length {
            let character = characters[cursor % characters.count]
            let next = String(character)
            let nextUnits = next.utf16.count
            guard units + nextUnits <= length else { break }
            source.append(character)
            units += nextUnits
            cursor += 1
        }
        source += String(repeating: "x", count: length - units)
        let input = NSAttributedString(string: source, attributes: [
            .font: font, .foregroundColor: UIColor.label
        ])
        return PerformanceSample(
            metadata: .init(
                id: id, utf16Length: length, attachmentCount: count,
                imageLocations: attachments.keys.sorted(), viewLocations: views.keys.sorted(),
                scripts: ["Chinese", "emoji", "Arabic", "Latin"], fontName: font.fontName,
                fontPointSize: 20, width: 320, attachmentSide: 24,
                numberOfLines: 0, wrapping: "word", verticalAlignment: "top",
                textContainerInsets: [0, 0, 0, 0]
            ),
            attributedText: input, attachments: attachments, viewAttachments: views,
            actions: [.init(actionID: "\(id)-action", range: NSRange(location: 0, length: 2))]
        )
    }

    private static func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { context in
            UIColor(red: 0.16, green: 0.43, blue: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            UIColor.white.setFill()
            context.fill(CGRect(x: 4, y: 4, width: 6, height: 6))
        }
    }
}
