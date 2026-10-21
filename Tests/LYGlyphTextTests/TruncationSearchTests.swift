import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class TruncationSearchTests: XCTestCase {
    private struct Case {
        let resolved: ResolvedText
        let range: NSRange
        let width: CGFloat
    }

    private func cases(_ text: NSAttributedString, widths: [CGFloat]) throws -> [Case] {
        let resolved = try ResolvedText(
            document: LYGlyphTextDocument(attributedText: text),
            traits: UITraitCollection(displayScale: 3)
        )
        return widths.flatMap { width -> [Case] in
            let frame = TextFrame(framesetter: resolved.framesetter, width: width, scale: 3)
            return frame.lines.map { line in
                let range = CTLineGetStringRange(line)
                let end = min(resolved.sourceLength, range.location + range.length)
                return Case(
                    resolved: resolved,
                    range: NSRange(location: range.location, length: end - range.location),
                    width: width
                )
            }
        }
    }

    private func fixtures() -> [NSAttributedString] {
        let font = UIFont.systemFont(ofSize: 20)
        let kerned = NSMutableAttributedString(
            string: String(repeating: "Kerning applies to every glyph ", count: 5), attributes: [.font: font]
        )
        kerned.addAttribute(.kern, value: 3, range: NSRange(location: 0, length: kerned.length))
        let sizes = NSMutableAttributedString(
            string: String(repeating: "Mixed SIZE text runs ", count: 6), attributes: [.font: font]
        )
        sizes.addAttribute(.font, value: UIFont.systemFont(ofSize: 34), range: NSRange(location: 6, length: 4))
        return [
            String(repeating: "The quick brown fox jumps over the lazy dog ", count: 6),
            String(repeating: "中文排版测试，包含标点与全角符号。", count: 8),
            String(repeating: "👨‍👩‍👧‍👦e\u{301}x\u{302}\u{303} emoji 😀🇨🇳 ", count: 6),
            String(repeating: "مرحبا بالعالم هذا نص عربي ", count: 6),
            String(repeating: "Hello مرحبا world 123 ", count: 6),
            String(repeating: "iiiiiiiiii WWWWW ", count: 12)
        ].map { NSAttributedString(string: $0, attributes: [.font: font]) } + [kerned, sizes]
    }

    /// 位置估算只能减少候选数量，不能改变既有逐个回退得到的文本、方向偏移和可见原文映射。
    func testEstimatedSearchMatchesLinearSearch() throws {
        var compared = 0
        var estimated = 0
        var linear = 0
        for text in fixtures() {
            for item in try cases(text, widths: Array(stride(from: 40, through: 320, by: 23))) {
                for token in ["…", "…展开全文", "… more", String(repeating: "…", count: 8)] {
                    let fast = TailTruncation(
                        text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token
                    )
                    let reference = TailTruncation(
                        text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token,
                        usesEstimate: false
                    )
                    let source = item.resolved.attributedText.string as NSString
                    let message = "\(source.substring(with: item.range)) width=\(item.width) token=\(token)"
                    XCTAssertEqual(fast.text.string, reference.text.string, message)
                    XCTAssertEqual(fast.drawsToken, reference.drawsToken, message)
                    XCTAssertEqual(fast.tokenRange, reference.tokenRange, message)
                    XCTAssertEqual(fast.alignmentOffset, reference.alignmentOffset, accuracy: 0.0001, message)
                    XCTAssertEqual(
                        fast.visibleSourceRanges(in: fast.line, source: source),
                        reference.visibleSourceRanges(in: reference.line, source: source),
                        message
                    )
                    XCTAssertLessThanOrEqual(fast.candidateCount, reference.candidateCount + 1, message)
                    compared += 1
                    estimated += fast.candidateCount
                    linear += reference.candidateCount
                }
            }
        }
        XCTAssertGreaterThan(compared, 500)
        XCTAssertLessThan(estimated, linear)
    }

    func testWideTokenOnLongLeftToRightLineUsesFewCandidates() throws {
        let text = NSAttributedString(
            string: String(repeating: "i", count: 400), attributes: [.font: UIFont.systemFont(ofSize: 20)]
        )
        let item = try XCTUnwrap(cases(text, widths: [320]).first)
        let token = String(repeating: "…", count: 12)
        let fast = TailTruncation(
            text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token
        )
        let reference = TailTruncation(
            text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token,
            usesEstimate: false
        )
        XCTAssertTrue(fast.drawsToken)
        XCTAssertEqual(fast.text.string, reference.text.string)
        XCTAssertGreaterThanOrEqual(reference.candidateCount, 30)
        XCTAssertLessThanOrEqual(fast.candidateCount, 4)
        XCTAssertLessThanOrEqual(CGFloat(CTLineGetTypographicBounds(fast.line, nil, nil, nil)), item.width)
    }

    func testRightToLeftLineKeepsLinearSearch() throws {
        let text = NSAttributedString(
            string: String(repeating: "مرحبا بالعالم ", count: 12), attributes: [.font: UIFont.systemFont(ofSize: 20)]
        )
        let item = try XCTUnwrap(cases(text, widths: [200]).first)
        let token = "…展开全文"
        let fast = TailTruncation(
            text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token
        )
        let reference = TailTruncation(
            text: item.resolved.attributedText, range: item.range, width: item.width, tokenString: token,
            usesEstimate: false
        )
        XCTAssertEqual(fast.candidateCount, reference.candidateCount)
        XCTAssertEqual(fast.text.string, reference.text.string)
    }
}
