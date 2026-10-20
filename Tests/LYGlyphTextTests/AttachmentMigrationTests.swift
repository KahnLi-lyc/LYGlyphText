import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

/// 与 6dbeaee 的旧 renderer 共用此夹具和签名代码；基线来自该提交的真实 Simulator 执行。
@MainActor
final class AttachmentMigrationTests: XCTestCase {
    private func fixtures() throws -> [(String, LYGlyphTextLayout)] {
        let font = try XCTUnwrap(UIFont(name: "Baskerville", size: 42))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 7, height: 11)).image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 7, height: 11))
        }
        return try [
            ("top", LYGlyphTextAttachmentAlignment.top),
            ("center", .center),
            ("bottom", .bottom),
            ("truncated", .center)
        ].map { name, alignment in
            let source = name == "truncated" ? "head\n\u{FFFC}fi\u{FFFC} abcdefghijklmnopqrstuvwxyz" : "fi \u{FFFC} \u{FFFC} العربية"
            let string = source as NSString
            let imagePosition = string.range(of: "\u{FFFC}").location
            let viewPosition = string.range(of: "\u{FFFC}", options: .backwards).location
            let document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: source, attributes: [
                .font: font, .foregroundColor: UIColor.green,
                .kern: 0.35, .baselineOffset: 1.25
            ]), attachments: [
                imagePosition: .init(
                    id: "image",
                    image: image,
                    size: CGSize(width: 24.5, height: 31.25),
                    alignment: alignment
                )
            ], viewAttachments: [
                viewPosition: .init(
                    id: "view",
                    viewID: "badge",
                    size: CGSize(width: 33.25, height: 55.5),
                    alignment: alignment
                )
            ])
            let value = ResolvedText(document: document, traits: .init(userInterfaceStyle: .light)).layout(
                width: name == "truncated" ? 230 : 330,
                insets: .init(top: 12, left: 12, bottom: 8, right: 8), scale: 2,
                numberOfLines: name == "truncated" ? 2 : 0
            )
            return (name, value)
        }
    }

    private func signature(_ value: LYGlyphTextLayout) throws -> String {
        func numbers(_ values: [CGFloat]) -> [Double] {
            values.map { (Double($0) * 1_000_000).rounded() / 1_000_000 }
        }
        func range(_ value: NSRange) -> [Int] {
            [value.location, value.length]
        }
        var lines: [[String: Any]] = []
        for line in value.lines {
            var runs: [[String: Any]] = []
            for run in CTLineGetGlyphRuns(line.text) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, .init(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, .init(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, .init(location: 0, length: 0), &advances)
                CTRunGetStringIndices(run, .init(location: 0, length: 0), &indices)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let font = attributes[kCTFontAttributeName] as! CTFont
                let matrix = CTRunGetTextMatrix(run)
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                let width = CTRunGetTypographicBounds(run, .init(location: 0, length: 0), &ascent, &descent, &leading)
                runs.append([
                    "range": range(NSRange(
                        location: CTRunGetStringRange(run).location,
                        length: CTRunGetStringRange(run).length
                    )),
                    "status": CTRunGetStatus(run).rawValue,
                    "glyphs": glyphs.map(Int.init), "positions": positions.map { numbers([$0.x, $0.y]) },
                    "advances": advances.map { numbers([$0.width, $0.height]) }, "indices": indices,
                    "matrix": numbers([matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]),
                    "font": CTFontCopyPostScriptName(font) as String, "fontSize": numbers([CTFontGetSize(font)]),
                    "traits": CTFontGetSymbolicTraits(font).rawValue,
                    "metrics": numbers([CGFloat(width), ascent, descent, leading])
                ])
            }
            var lineAscent: CGFloat = 0, lineDescent: CGFloat = 0, lineLeading: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line.text, &lineAscent, &lineDescent, &lineLeading)
            let lineRange = CTLineGetStringRange(line.text)
            lines.append([
                "range": range(NSRange(location: lineRange.location, length: lineRange.length)),
                "metrics": numbers([CGFloat(lineWidth), lineAscent, lineDescent, lineLeading]),
                "baseline": numbers([line.baseline.x, line.baseline.y]), "runs": runs,
                "sourceRanges": line.visibleSourceRanges.map(range), "sourceOffset": line.sourceOffset,
                "tokenRange": line.truncationTokenRange.map(range) ?? []
            ])
        }
        func placement(_ id: String, source: Int, rect: CGRect) -> [String: Any] {
            ["id": id, "source": source, "rect": numbers([rect.minX, rect.minY, rect.width, rect.height])]
        }
        let object: [String: Any] = [
            "size": numbers([value.size.width, value.size.height]), "lines": lines,
            "images": value.attachments.map { placement($0.attachment.id, source: $0.sourceLocation, rect: $0.rect) },
            "views": value.viewAttachments.map { placement($0.attachment.id, source: $0.sourceLocation, rect: $0.rect) }
        ]
        return try String(
            decoding: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            as: UTF8.self
        )
    }

    func testBothAttachmentKindsMatchOriginalRendererSignatures() throws {
        for (name, value) in try fixtures() {
            XCTAssertEqual(value.attachments.count, 1, name)
            XCTAssertEqual(value.viewAttachments.count, 1, name)
            XCTAssertGreaterThan(value.lines.reduce(0) { $0 + CTLineGetGlyphCount($1.text) }, 2)
            if name == "truncated" {
                XCTAssertGreaterThan(try XCTUnwrap(value.lines.last).sourceOffset, 0)
                XCTAssertNotNil(value.lines.last?.truncationTokenRange)
            }
            XCTAssertEqual(try signature(value), AttachmentMigrationBaseline.signatures[name], name)
        }
    }
}
