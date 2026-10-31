@testable import LYGlyphText
import UIKit
import XCTest

/// 理想宽度尺寸路径：结果必须与完整布局逐像素一致，且预排版采用后固有尺寸查询不在主线程排版。
@MainActor
final class IdealSizeTests: XCTestCase {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    private func fixtures() throws -> [(String, LYGlyphTextDocument, LYGlyphTextConfiguration)] {
        let font = UIFont.systemFont(ofSize: 17)
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.lineSpacing = 4
        let long = String(repeating: "图文混排 mixed text 😀 مرحبا ", count: 12)
        var middleTruncated = LYGlyphTextConfiguration(numberOfLines: 3)
        middleTruncated.truncationMode = .middle
        let attachmentText = NSMutableAttributedString(string: "头像 \u{FFFC} 和文字\n第二段", attributes: [.font: font])
        return try [
            ("plain", LYGlyphTextDocument(text: "Hello, GlyphText"), .init()),
            ("multilingual-wrapped", LYGlyphTextDocument(text: long, font: font), .init()),
            (
                "truncated-token",
                LYGlyphTextDocument(text: long, font: font),
                .init(
                    textContainerInset: UIEdgeInsets(top: 3, left: 5, bottom: 7, right: 9), numberOfLines: 2,
                    truncationToken: .init(pieces: [.text("…全文"), .image(image(), size: CGSize(width: 12, height: 8))])
                )
            ),
            (
                "attachment-paragraph",
                LYGlyphTextDocument(
                    attributedText: attachmentText,
                    attachments: [3: .init(id: "a", image: image(), size: CGSize(width: 30, height: 30))]
                ),
                .init()
            ),
            (
                "paragraph-style",
                LYGlyphTextDocument(attributedText: NSAttributedString(
                    string: long, attributes: [.font: font, .paragraphStyle: paragraph]
                )),
                middleTruncated
            ),
            ("trailing-newline", LYGlyphTextDocument(text: "末尾换行\n"), .init()),
            ("empty", LYGlyphTextDocument(text: ""), .init(textContainerInset: UIEdgeInsets(
                top: 2, left: 2, bottom: 2, right: 2
            )))
        ]
    }

    func testSizeOnlyLayoutMatchesFullLayoutAtEveryWidth() throws {
        for (name, document, configuration) in try fixtures() {
            for scale: CGFloat in [1, 3] {
                let text = ResolvedText(
                    document: document, traits: UITraitCollection(displayScale: scale),
                    wrapping: configuration.wrapping
                )
                for width: CGFloat? in [nil, 80, 200, 375] {
                    func size(_ displayData: Bool) -> CGSize {
                        text.layout(
                            width: width, insets: configuration.insets, scale: scale,
                            numberOfLines: configuration.numberOfLines,
                            truncationToken: configuration.truncationToken,
                            truncationMode: configuration.truncationMode, displayData: displayData
                        ).size
                    }
                    XCTAssertEqual(size(false), size(true), "\(name) scale=\(scale) width=\(String(describing: width))")
                }
            }
        }
    }

    func testIntrinsicSizeIsUnchangedAndSkipsFullLayoutForIdealWidth() throws {
        for (name, document, configuration) in try fixtures() {
            let label = LYGlyphTextLabel(frame: .zero)
            label.document = document
            label.configuration = configuration
            let reference = ResolvedText(
                document: document, traits: label.traitCollection, wrapping: configuration.wrapping
            ).layout(
                width: nil, insets: configuration.insets,
                scale: label.traitCollection.displayScale > 0 ? label.traitCollection.displayScale : 1,
                numberOfLines: configuration.numberOfLines, truncationToken: configuration.truncationToken,
                truncationMode: configuration.truncationMode
            ).size
            label.resetLayoutMeasurementCounts()
            XCTAssertEqual(label.intrinsicContentSize, reference, name)
            XCTAssertEqual(label.sizeThatFits(CGSize(width: CGFloat.infinity, height: .infinity)), reference, name)
            XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0, "\(name) 理想宽度不构建完整布局")
            XCTAssertEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, 0, name)
        }
    }

    func testPreparedLayoutAnswersIdealSizeWithoutMainThreadWork() async throws {
        let document = try LYGlyphTextDocument(text: String(repeating: "预排版后的固有尺寸查询 ", count: 20))
        let configuration = LYGlyphTextConfiguration(numberOfLines: 4)
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: document, configuration: configuration, width: 300, traitCollection: label.traitCollection
        )
        label.apply(prepared)
        label.resetLayoutMeasurementCounts()
        MeasurementCounters.reset()
        // 列表自适应行高的典型顺序：固有尺寸（理想宽度＋实际宽度），随后绘制与重复查询。
        let first = label.intrinsicContentSize
        XCTAssertEqual(first.height, prepared.size.height)
        XCTAssertEqual(first.width, prepared.idealSize.width)
        _ = label.measuredLayout(width: 300)
        _ = label.intrinsicContentSize
        _ = label.sizeThatFits(CGSize(width: CGFloat.infinity, height: .infinity))
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        XCTAssertEqual(MeasurementCounters.sizeMeasurements, 0)
        XCTAssertEqual(MeasurementCounters.fullLayoutBuilds, 0)
    }

    func testIdealSizeIsDroppedWhenInputsChange() throws {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try LYGlyphTextDocument(text: "短")
        let short = label.intrinsicContentSize
        label.document = try LYGlyphTextDocument(text: "明显更长的一段文字")
        XCTAssertGreaterThan(label.intrinsicContentSize.width, short.width)
        label.configuration.textContainerInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        XCTAssertEqual(
            label.intrinsicContentSize.width,
            label.sizeThatFits(.init(width: CGFloat.infinity, height: 0)).width
        )
    }
}
