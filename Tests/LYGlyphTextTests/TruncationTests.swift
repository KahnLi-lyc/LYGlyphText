import CoreText
@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class TruncationTests: XCTestCase {
    private func label(_ text: String, limit: Int = 0) throws -> LYGlyphTextLabel {
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: text, attributes: [.font: UIFont.systemFont(ofSize: 20)]
        ))
        view.configuration.numberOfLines = limit
        return view
    }

    func testSingleAndMultipleLineLimitsReduceHeight() throws {
        let view = try label(String(repeating: "你好 Hello world ", count: 12))
        let unlimited = view.measuredLayout(width: 120)
        XCTAssertGreaterThan(unlimited.lines.count, 3)
        for count in [1, 2, 3] {
            view.configuration.numberOfLines = count
            let limited = view.measuredLayout(width: 120)
            XCTAssertEqual(limited.lines.count, count)
            XCTAssertLessThan(limited.size.height, unlimited.size.height)
        }
    }

    func testExplicitAndTrailingNewlinesCountTowardLimit() throws {
        for string in ["one\ntwo\nthree", "one\ntwo\n", "\n\n"] {
            let view = try label(string, limit: 2)
            XCTAssertEqual(view.measuredLayout(width: 200).lines.count, 2)
        }
    }

    func testNegativeLimitBehavesAsUnlimited() throws {
        let view = try label("one\ntwo\nthree")
        let original = view.measuredLayout(width: 100)
        view.configuration.numberOfLines = -1
        XCTAssertEqual(view.measuredLayout(width: 100).size, original.size)
        XCTAssertEqual(view.measuredLayout(width: 100).lines.count, original.lines.count)
    }

    func testExactFitHasNoTokenAndPreservesGeometry() throws {
        for string in ["", "短文", "one\ntwo", "one\n", "\n", "\n\n", "   "] {
            let view = try label(string)
            let original = view.measuredLayout(width: 200)
            view.configuration.numberOfLines = max(1, original.lines.count)
            let fitted = view.measuredLayout(width: 200)
            XCTAssertEqual(fitted.size, original.size, string)
            XCTAssertEqual(fitted.lines.map(\.baseline), original.lines.map(\.baseline), string)
            XCTAssertTrue(fitted.lines.allSatisfy { $0.truncationTokenRange == nil })
        }
    }

    func testOnlyLastVisibleLineHasOneGeneratedToken() throws {
        for text in ["one\ntwo\nthree", "one\ntwo\n", "\n\n", String(repeating: "中英文 words ", count: 20)] {
            let view = try label(text, limit: 2)
            let layout = view.measuredLayout(width: 120)
            XCTAssertEqual(layout.lines.count, 2)
            XCTAssertNil(layout.lines.first?.truncationTokenRange)
            let last = try XCTUnwrap(layout.lines.last)
            let token = try XCTUnwrap(last.truncationTokenRange)
            XCTAssertEqual(token.length, 1)
            XCTAssertEqual(glyphCount(in: token, line: last.text), 1)
            for range in last.visibleSourceRanges {
                XCTAssertLessThanOrEqual(NSMaxRange(range), last.sourceOffset + token.location)
            }
        }
    }

    func testTokenOnlyAndInsufficientWidthKeepLineHeight() throws {
        let font = UIFont.systemFont(ofSize: 20)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: font]))
        let tokenWidth = CGFloat(CTLineGetTypographicBounds(token, nil, nil, nil))
        let view = try label("MMMMMMMMMMMM", limit: 1)
        let exact = view.measuredLayout(width: tokenWidth)
        let tokenLine = try XCTUnwrap(exact.lines.first)
        XCTAssertEqual(tokenLine.truncationTokenRange, NSRange(location: 0, length: 1))
        XCTAssertTrue(tokenLine.visibleSourceRanges.isEmpty)
        XCTAssertEqual(CTLineGetGlyphCount(tokenLine.text), 1)
        let tooNarrow = view.measuredLayout(width: tokenWidth - 0.01)
        XCTAssertEqual(tooNarrow.lines.count, 1)
        XCTAssertEqual(try CTLineGetGlyphCount(XCTUnwrap(tooNarrow.lines.first).text), 0)
        XCTAssertTrue(tooNarrow.lines[0].visibleSourceRanges.isEmpty)
        XCTAssertNil(tooNarrow.lines[0].truncationTokenRange)
        XCTAssertEqual(tooNarrow.size.height, exact.size.height)
        XCTAssertEqual(view.measuredLayout(width: 0).size, .zero)
    }

    func testTokenInheritsLastLineStartFontAndColor() throws {
        let text = NSMutableAttributedString(
            string: "first\nMMMM mixed styles and more\nhidden", attributes: [.font: UIFont.systemFont(ofSize: 20)]
        )
        let start = (text.string as NSString).range(of: "MMMM").location
        let font = UIFont.systemFont(ofSize: 24, weight: .bold)
        text.addAttributes([.font: font, .foregroundColor: UIColor.red], range: NSRange(location: start, length: 4))
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.blue],
            range: NSRange(location: start + 4, length: 15)
        )
        let view = try label("", limit: 2)
        view.document = try LYGlyphTextDocument(attributedText: text)
        let last = try XCTUnwrap(view.measuredLayout(width: 220).lines.last)
        let token = try XCTUnwrap(last.truncationTokenRange)
        let runs = try XCTUnwrap(CTLineGetGlyphRuns(last.text) as? [CTRun])
        let run = try XCTUnwrap(runs.first { run in
            let range = CTRunGetStringRange(run)
            return token.location >= range.location && token.location < range.location + range.length
        })
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let resolvedFont = try XCTUnwrap(attributes[kCTFontAttributeName] as? UIFont)
        XCTAssertEqual(resolvedFont.pointSize, font.pointSize)
        let rawColor = try XCTUnwrap(attributes[kCTForegroundColorAttributeName])
        XCTAssertTrue(CFEqual(rawColor as CFTypeRef, UIColor.red.cgColor))
    }

    func testHiddenLargeFontDoesNotContributeHeightAndInsetsCountOnce() throws {
        let input = NSMutableAttributedString(
            string: "Visible\nhidden",
            attributes: [.font: UIFont.systemFont(ofSize: 20)]
        )
        input.addAttribute(.font, value: UIFont.systemFont(ofSize: 100), range: NSRange(location: 8, length: 6))
        let view = try label("Visible…", limit: 1)
        let reference = view.measuredLayout(width: 200).size.height
        view.document = try LYGlyphTextDocument(attributedText: input)
        let limited = view.measuredLayout(width: 200).size.height
        XCTAssertEqual(limited, reference, accuracy: 1)
        view.configuration.textContainerInset = UIEdgeInsets(top: 7, left: 9, bottom: 11, right: 13)
        XCTAssertEqual(view.measuredLayout(width: 222).size.height, limited + 18, accuracy: 0.5)
    }

    func testVisibleRangesPreserveGraphemesAndExcludeHiddenInput() throws {
        let inputs = [
            "👨‍👩‍👧‍👦👍🏽🇨🇳e\u{301}👨‍👩‍👧‍👦👍🏽🇺🇸a\u{301} hidden tail",
            "مرحبا Hello بالعالم أهلا text طويل مرحبا بالعالم",
            "supercalifragilisticexpialidociousLongUnbrokenWord"
        ]
        for text in inputs {
            var boundaries: Set<Int> = [0]
            var end = 0
            for character in text {
                end += String(character).utf16.count
                boundaries.insert(end)
            }
            let view = try label(text)
            for width: CGFloat in [1, 19.99, 20, 30, 45, 85, 130] {
                for limit in [1, 2, 3] {
                    view.configuration.numberOfLines = limit
                    let layout = view.measuredLayout(width: width)
                    XCTAssertLessThanOrEqual(
                        layout.lines.count,
                        limit,
                        "\(text) width=\(width) limit=\(limit) ranges=\(layout.lines.map { CTLineGetStringRange($0.text) })"
                    )
                    for line in layout.lines {
                        var previousEnd = 0
                        for range in line.visibleSourceRanges {
                            XCTAssertTrue(boundaries.contains(range.location), "\(text) width=\(width) range=\(range)")
                            XCTAssertTrue(
                                boundaries.contains(NSMaxRange(range)),
                                "\(text) width=\(width) range=\(range)"
                            )
                            XCTAssertGreaterThanOrEqual(range.location, previousEnd)
                            previousEnd = NSMaxRange(range)
                            XCTAssertLessThanOrEqual(NSMaxRange(range), text.utf16.count)
                        }
                        if let token = line.truncationTokenRange {
                            XCTAssertEqual(glyphCount(in: token, line: line.text), 1)
                            XCTAssertTrue(line.visibleSourceRanges.allSatisfy {
                                NSMaxRange($0) <= line.sourceOffset + token.location
                            })
                        }
                    }
                }
            }
        }
    }

    func testRTLAndExplicitAlignmentArePreservedAfterTruncation() throws {
        for alignment in [NSTextAlignment.natural, .right, .center, .left] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.baseWritingDirection = .rightToLeft
            let view = try label("", limit: 1)
            view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: "مرحبا بالعالم Hello مرحبا بالعالم", attributes: [
                    .font: UIFont.systemFont(ofSize: 20), .paragraphStyle: paragraph
                ]
            ))
            let line = try XCTUnwrap(view.measuredLayout(width: 180).lines.first)
            let token = try XCTUnwrap(line.truncationTokenRange)
            let width = CGFloat(CTLineGetTypographicBounds(line.text, nil, nil, nil))
            let expected: CGFloat = alignment == .left ? 0 : (180 - width) * (alignment == .center ? 0.5 : 1)
            XCTAssertEqual(line.baseline.x, expected, accuracy: 0.5)
            // RTL 逻辑尾部的省略号出现在文本左端。
            XCTAssertLessThan(CTLineGetOffsetForStringIndex(line.text, token.location, nil), width / 2)
        }
    }

    func testLineLimitUpdatesAutoLayoutIntrinsicWidthAndPriorities() throws {
        let view = try label(String(repeating: "自动撑高 with words ", count: 20))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(UILayoutPriority(260), for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 900))
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        for _ in 0 ..< 4 {
            host.layoutIfNeeded()
        }
        let unlimitedHeight = view.frame.height
        let idealWidth = view.intrinsicContentSize.width
        for limit in [1, 3, 2, 0, 1] {
            view.configuration.numberOfLines = limit
            host.setNeedsLayout()
            for _ in 0 ..< 4 {
                host.layoutIfNeeded()
            }
            let expected = view.measuredLayout(width: 160).size.height
            XCTAssertEqual(view.frame.height, expected, accuracy: 0.5)
            if limit > 0 { XCTAssertLessThan(view.frame.height, unlimitedHeight) }
            XCTAssertEqual(view.intrinsicContentSize.width, idealWidth)
            XCTAssertEqual(view.contentHuggingPriority(for: .vertical), UILayoutPriority(260))
            XCTAssertEqual(view.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
            let stable = view.frame
            host.layoutIfNeeded()
            XCTAssertEqual(view.frame, stable)
            let fitted = view.systemLayoutSizeFitting(
                CGSize(width: 90, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            XCTAssertEqual(fitted.height, view.measuredLayout(width: 90).size.height)
        }
    }

    func testSwiftUIAndUIKitAgreeWhileLimitsAndWidthsChange() throws {
        let view = try label(String(repeating: "你好 Hello 👨‍👩‍👧‍👦 mixed words ", count: 8))
        let controller = UIHostingController(rootView: LYGlyphTextView(document: view.document))
        controller.loadViewIfNeeded()
        for limit in [0, 1, 2, 3, 0] {
            view.configuration.numberOfLines = limit
            for width: CGFloat in [0, 90, 300, 90] {
                controller.rootView = LYGlyphTextView(document: view.document, configuration: view.configuration)
                let actual = controller.sizeThatFits(in: CGSize(width: width, height: 10000))
                let expected = view.sizeThatFits(CGSize(width: width, height: 1))
                XCTAssertEqual(
                    actual.height,
                    expected.height,
                    accuracy: 1 / max(controller.traitCollection.displayScale, 1)
                )
            }
        }
    }

    func testHeightCompressionDoesNotCreateAToken() throws {
        let view = try label("one\ntwo\nthree", limit: 3)
        view.bounds.size = CGSize(width: 120, height: 5)
        XCTAssertTrue(view.measuredLayout(width: 120).lines.allSatisfy { $0.truncationTokenRange == nil })
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 120, height: 5)).height, 5)
    }

    func testNaturalRTLContinuationKeepsParagraphDirection() throws {
        let text = "مرحبا abc def ghi jkl mno pqr stu vwx yz"
        let view = try label(text, limit: 2)
        let layout = view.measuredLayout(width: 95)
        let last = try XCTUnwrap(layout.lines.last)
        let token = try XCTUnwrap(last.truncationTokenRange)
        XCTAssertGreaterThan(last.baseline.x, 0)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(last.text, nil, nil, nil))
        XCTAssertLessThan(CTLineGetOffsetForStringIndex(last.text, token.location, nil), lineWidth / 2)
        XCTAssertTrue(last.visibleSourceRanges.allSatisfy { NSMaxRange($0) <= token.location + last.sourceOffset })
    }

    func testAttributesInsideEmojiDoNotSplitVisibleMapping() throws {
        let text = "👨‍👩‍👧‍👦X more words to hide"
        let input = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 20)])
        input.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 1, length: 1))
        let view = try label("", limit: 1)
        view.document = try LYGlyphTextDocument(attributedText: input)
        let last = try XCTUnwrap(view.measuredLayout(width: 100).lines.last)
        let emojiLength = "👨‍👩‍👧‍👦".utf16.count
        XCTAssertTrue(last.visibleSourceRanges.contains { $0.location == 0 && $0.length >= emojiLength })
        for range in last.visibleSourceRanges {
            XCTAssertFalse((1 ..< emojiLength).contains(range.location))
            XCTAssertFalse((1 ..< emojiLength).contains(NSMaxRange(range)))
        }
    }

    func testOverflowDoesNotChangeEarlierLineSpacing() throws {
        let view = try label("")
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "one\ntwo\nthree\nfour",
            attributes: [.font: UIFont(name: "Helvetica", size: 20) ?? .systemFont(ofSize: 20)]
        ))
        let unlimited = view.measuredLayout(width: 180)
        view.configuration.numberOfLines = 3
        let limited = view.measuredLayout(width: 180)
        XCTAssertEqual(limited.lines.count, 3)
        for index in 0 ..< 2 {
            XCTAssertEqual(limited.lines[index].baseline.y, unlimited.lines[index].baseline.y, accuracy: 0.5)
        }
    }

    func testNaturalRTLWithFirstStrongCharacterHiddenStillPlacesTokenOnLeft() throws {
        for alignment in [NSTextAlignment.natural, .left, .center, .right] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            let view = try label("", limit: 1)
            view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: "12345 67890 مرحبا بالعالم مرحبا", attributes: [
                    .font: UIFont.systemFont(ofSize: 20), .paragraphStyle: paragraph
                ]
            ))
            let line = try XCTUnwrap(view.measuredLayout(width: 80).lines.first)
            let token = try XCTUnwrap(line.truncationTokenRange)
            let width = CGFloat(CTLineGetTypographicBounds(line.text, nil, nil, nil))
            XCTAssertLessThan(CTLineGetOffsetForStringIndex(line.text, token.location, nil), width / 2)
        }
    }

    func testBidiFragmentsAndOriginalEllipsisRemainSeparateFromGeneratedToken() throws {
        let text = "مرحبا … Hello 中文 بالعالم more words\nhidden"
        let view = try label(text, limit: 1)
        let line = try XCTUnwrap(view.measuredLayout(width: 230).lines.first)
        let token = try XCTUnwrap(line.truncationTokenRange)
        XCTAssertGreaterThan(line.visibleSourceRanges.count, 1)
        let original = (text as NSString).range(of: "…")
        XCTAssertTrue(line.visibleSourceRanges.contains { NSLocationInRange(original.location, $0) })
        XCTAssertEqual(glyphCount(in: token, line: line.text), 1)
    }

    func testAdditionalLineSeparatorsAndPreferredWidth() throws {
        for separator in ["\r\n", "\u{2028}", "\u{2029}"] {
            let view = try label("one\(separator)two\(separator)three", limit: 2)
            let layout = view.measuredLayout(width: 200)
            XCTAssertEqual(layout.lines.count, 2)
            XCTAssertNotNil(layout.lines.last?.truncationTokenRange)
            view.preferredMaxLayoutWidth = 90
            view.bounds.size = CGSize(width: 300, height: 1)
            XCTAssertEqual(view.intrinsicContentSize.height, view.measuredLayout(width: 90).size.height)
        }
    }

    private func glyphCount(in range: NSRange, line: CTLine) -> Int {
        (CTLineGetGlyphRuns(line) as! [CTRun]).reduce(0) { count, run in
            let length = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: length)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            return count + indices.count(where: { NSLocationInRange($0, range) })
        }
    }
}
