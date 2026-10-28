import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class EdgeTruncationTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)
    private let longText = "Start of the article " + String(repeating: "middle words ", count: 12) + "final END"

    private func layout(
        _ document: LYGlyphTextDocument, mode: LYGlyphTextConfiguration.TruncationMode, lines: Int = 1,
        width: CGFloat = 260, token: LYGlyphTextTruncationToken? = nil
    ) -> LYGlyphTextLayout {
        ResolvedText(document: document, traits: UITraitCollection(displayScale: 2)).layout(
            width: width, insets: .zero, scale: 2, numberOfLines: lines, truncationToken: token, truncationMode: mode
        )
    }

    private func document(
        _ string: String,
        actions: [LYGlyphTextAction] = [],
        attachments: [Int: LYGlyphTextAttachment] = [:]
    )
        throws -> LYGlyphTextDocument
    {
        try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: string, attributes: [.font: font]), attachments: attachments,
            actions: actions
        )
    }

    func testHeadShowsTokenThenDocumentEnd() throws {
        let doc = try document(longText)
        let value = layout(doc, mode: .head)
        let line = try XCTUnwrap(value.lines.last)
        XCTAssertEqual(line.truncationTokenRange?.location, 0)
        let visible = try XCTUnwrap(line.visibleSourceRanges.last)
        XCTAssertEqual(line.visibleSourceRanges.count, 1)
        XCTAssertEqual(NSMaxRange(visible), (longText as NSString).length)
        XCTAssertTrue((longText as NSString).substring(with: visible).hasSuffix("final END"))
        XCTAssertLessThanOrEqual(CGFloat(CTLineGetTypographicBounds(line.text, nil, nil, nil)), 260.5)
        let token = try XCTUnwrap(value.truncationToken?.rects.first)
        let end = try XCTUnwrap(value.visibleTextFragments(
            in: NSRange(location: (longText as NSString).length - 3, length: 3), source: longText
        ).first).rect
        XCTAssertLessThan(token.maxX, end.minX)
    }

    func testMiddleKeepsLineStartTokenAndDocumentEnd() throws {
        let doc = try document(longText)
        let value = layout(doc, mode: .middle)
        let line = try XCTUnwrap(value.lines.last)
        XCTAssertEqual(line.visibleSourceRanges.count, 2)
        XCTAssertEqual(line.visibleSourceRanges.first?.location, 0)
        XCTAssertEqual(line.visibleSourceRanges.last.map(NSMaxRange), (longText as NSString).length)
        let tokenLocation = try XCTUnwrap(line.truncationTokenRange?.location)
        XCTAssertEqual(tokenLocation, line.visibleSourceRanges[0].length)
        XCTAssertNotNil(line.suffixSegment)
        let start = try XCTUnwrap(value.visibleTextFragments(in: NSRange(location: 0, length: 5), source: longText)
            .first)
            .rect
        let token = try XCTUnwrap(value.truncationToken?.rects.first)
        let end = try XCTUnwrap(value.visibleTextFragments(
            in: NSRange(location: (longText as NSString).length - 3, length: 3), source: longText
        ).first).rect
        XCTAssertLessThan(start.maxX, token.minX + 0.5)
        XCTAssertLessThan(token.maxX, end.minX + 0.5)
        // 被省略的中间原文没有任何片段。
        XCTAssertTrue(value.visibleTextFragments(in: NSRange(location: 40, length: 10), source: longText).isEmpty)
    }

    func testActionsAndAttachmentsAfterTokenMapToSource() throws {
        let string = longText + " \u{FFFC} tail link"
        let ns = string as NSString
        let link = ns.range(of: "link")
        let image = try LYGlyphTextAttachment(
            id: "img", image: XCTUnwrap(UIImage(systemName: "star")), size: CGSize(width: 16, height: 16)
        )
        let doc = try document(
            string, actions: [.init(actionID: "link", range: link)],
            attachments: [ns.range(of: "\u{FFFC}").location: image]
        )
        for mode in [LYGlyphTextConfiguration.TruncationMode.head, .middle] {
            let value = layout(doc, mode: mode, width: 300)
            XCTAssertEqual(value.attachments.map(\.attachment.id), ["img"], "\(mode)")
            let entry = try XCTUnwrap(value.actionIndex.first)
            XCTAssertFalse(entry.rects.isEmpty, "\(mode)")
            let token = try XCTUnwrap(value.truncationToken?.rects.first)
            XCTAssertGreaterThan(try XCTUnwrap(entry.rects.first).minX, token.maxX - 0.5)
            let geometry = ActionGeometry(
                layout: value, bounds: CGRect(x: 0, y: 0, width: 300, height: value.size.height), configuration: .init()
            )
            let hit = try XCTUnwrap(geometry.entries.first)
            XCTAssertEqual(hit.event(kind: .tap).range, link)
            let selection = SelectionGeometry(layout: value, source: string)
            let rect = try XCTUnwrap(entry.rects.first)
            XCTAssertEqual(selection.closestBoundary(to: CGPoint(x: rect.minX + 1, y: rect.midY)), link.location)
        }
    }

    func testSuffixStaysInLastParagraphAndIgnoresTrailingBlankParagraphs() throws {
        let multi =
            try document("First paragraph is long enough to wrap\n" + String(repeating: "more ", count: 10) + "\nLast")
        let value = layout(multi, mode: .head)
        let visible = try XCTUnwrap(value.lines.last?.visibleSourceRanges.last)
        let source = multi.string as NSString
        XCTAssertEqual(source.substring(with: visible), "Last")
        // 末尾的空白段落先去掉，末尾文字取自最后一个有内容的段落。
        let blankTail = try document(longText + "\n   \n")
        let trimmed = layout(blankTail, mode: .head)
        let end = try XCTUnwrap(trimmed.lines.last?.visibleSourceRanges.last)
        XCTAssertEqual(NSMaxRange(end), (longText as NSString).length)
        XCTAssertEqual(trimmed.lines.last?.truncationTokenRange?.location, 0)
    }

    func testRightToLeftHeadAndOversizedTokenStayValid() throws {
        let arabic = String(repeating: "مرحبا بالعالم ", count: 10) + "النهاية"
        let value = try layout(document(arabic), mode: .head, width: 220)
        let line = try XCTUnwrap(value.lines.last)
        XCTAssertNotNil(line.truncationTokenRange)
        XCTAssertEqual(line.visibleSourceRanges.last.map(NSMaxRange), (arabic as NSString).length)
        XCTAssertFalse(value.visibleTextFragments(
            in: NSRange(location: (arabic as NSString).length - 3, length: 3), source: arabic
        ).isEmpty)
        let huge = LYGlyphTextTruncationToken(text: String(repeating: "W", count: 40))
        for mode in [LYGlyphTextConfiguration.TruncationMode.head, .middle] {
            let empty = try layout(document(longText), mode: mode, width: 120, token: huge)
            XCTAssertNil(empty.truncationToken)
            XCTAssertEqual(empty.lines.last?.visibleSourceRanges, [])
        }
    }

    func testLabelInvalidatesWhenModeChanges() throws {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document(longText)
        label.configuration.numberOfLines = 1
        let tail = try XCTUnwrap(label.measuredLayout(width: 260).lines.last?.truncationTokenRange?.location)
        label.configuration.truncationMode = .head
        XCTAssertEqual(label.measuredLayout(width: 260).lines.last?.truncationTokenRange?.location, 0)
        XCTAssertGreaterThan(tail, 0)
    }
}
