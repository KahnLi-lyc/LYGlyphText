import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class TextGeometryTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 24)

    private func layout(
        _ source: String, width: CGFloat = 400, limit: Int = 0,
        attributes: [NSAttributedString.Key: Any] = [:]
    ) throws -> LYGlyphTextLayout {
        var attributes = attributes
        attributes[.font] = attributes[.font] ?? font
        return try layout(LYGlyphTextDocument(attributedText: NSAttributedString(
            string: source, attributes: attributes
        )), width: width, limit: limit)
    }

    private func layout(
        _ document: LYGlyphTextDocument, width: CGFloat = 400, limit: Int = 0
    ) -> LYGlyphTextLayout {
        ResolvedText(document: document, traits: UITraitCollection()).layout(
            width: width, insets: .zero, scale: 2, numberOfLines: limit
        )
    }

    func testCrossLineQueryKeepsSeparateVisualFragments() throws {
        let source = "alpha beta gamma delta epsilon zeta"
        let action = LYGlyphTextAction(actionID: "cross-line", range: NSRange(location: 0, length: source.utf16.count))
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: source, attributes: [.font: font]),
            actions: [action]
        )
        let result = layout(document, width: 100)
        let fragments = result.visibleTextFragments(
            in: NSRange(location: 0, length: source.utf16.count),
            source: source
        )
        XCTAssertGreaterThan(result.lines.count, 2)
        XCTAssertEqual(Set(fragments.map(\.lineIndex)).count, result.lines.count)
        XCTAssertTrue(fragments.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    }

    func testMixedBidiLogicalSelectionDoesNotFillVisualGap() throws {
        for source in ["abc אבג def", "abc مرحبا def"] {
            let result = try layout(source)
            let fragments = result.visibleTextFragments(in: NSRange(location: 0, length: 5), source: source)
            XCTAssertEqual(fragments.count, 2, source)
            let sorted = fragments.sorted { $0.rect.minX < $1.rect.minX }
            if sorted.count == 2 { XCTAssertLessThan(sorted[0].rect.maxX, sorted[1].rect.minX, source) }
        }
    }

    func testComposedClusterAcrossAttributeRunsKeepsCompleteSourceRange() throws {
        for source in ["e\u{301}", "x\u{301}", "👩🏽‍💻"] {
            let text = NSMutableAttributedString(string: source, attributes: [.font: font])
            text.addAttributes(
                [.foregroundColor: UIColor.red, .font: UIFont.systemFont(ofSize: 32)],
                range: NSRange(location: 1, length: 1)
            )
            let result = try layout(LYGlyphTextDocument(attributedText: text))
            let fragments = result.visibleTextFragments(
                in: NSRange(location: 0, length: source.utf16.count),
                source: source
            )
            // e + acute 可以被 Core Text 合成为一个 run；另两份 fixture 必须真实拆成多个 run。
            if source != "e\u{301}" {
                XCTAssertGreaterThan(
                    try XCTUnwrap((CTLineGetGlyphRuns(result.lines[0].text) as? [CTRun])?.count),
                    1,
                    source
                )
            }
            XCTAssertEqual(fragments.count, 1, source)
            XCTAssertEqual(fragments.first?.sourceRange, NSRange(location: 0, length: source.utf16.count))
        }
    }

    func testRealEllipsisHasGeometryButGeneratedTokenDoesNot() throws {
        let source = "… abc def ghi jkl mno pqr"
        let result = try layout(source, width: 90, limit: 1)
        XCTAssertNotNil(result.lines.first?.truncationTokenRange)
        XCTAssertFalse(result.visibleTextFragments(in: NSRange(location: 0, length: 1), source: source).isEmpty)
        let fragments = result.visibleTextFragments(
            in: NSRange(location: 0, length: source.utf16.count),
            source: source
        )
        XCTAssertFalse(fragments.isEmpty)
        for fragment in fragments {
            XCTAssertTrue(result.lines[fragment.lineIndex].visibleSourceRanges.contains {
                NSIntersectionRange($0, fragment.sourceRange) == fragment.sourceRange
            })
        }
        XCTAssertTrue(result.visibleTextFragments(
            in: NSRange(location: source.utf16.count - 1, length: 1),
            source: source
        ).isEmpty)
    }

    func testTruncatedPrefixMapsLocalIndicesAndArtificialSeparatorsAreExcluded() throws {
        let source = "one two three four five six seven eight nine ten\n"
        let result = try layout(source, width: 100, limit: 2)
        let line = try XCTUnwrap(result.lines.last)
        XCTAssertGreaterThan(line.sourceOffset, 0)
        let visible = try XCTUnwrap(line.visibleSourceRanges.first)
        let fragments = result.visibleTextFragments(in: visible, source: source)
        XCTAssertFalse(fragments.isEmpty)
        XCTAssertTrue(fragments.allSatisfy { $0.lineIndex == 1 && $0.sourceRange.location >= line.sourceOffset })
        let all = result.visibleTextFragments(in: NSRange(location: 0, length: source.utf16.count), source: source)
        XCTAssertTrue(all.allSatisfy { NSMaxRange($0.sourceRange) <= source.utf16.count })
    }

    func testSpacesHaveAdvanceAndNewlinesAndSentinelHaveNoGeometry() throws {
        let source = "a  \n"
        let result = try layout(source)
        XCTAssertFalse(result.visibleTextFragments(in: NSRange(location: 1, length: 2), source: source).isEmpty)
        XCTAssertTrue(result.visibleTextFragments(in: NSRange(location: 3, length: 1), source: source).isEmpty)
        XCTAssertTrue(result.visibleTextFragments(in: NSRange(location: 4, length: 1), source: source).isEmpty)
        let zero = try layout("\u{200B}")
        XCTAssertTrue(zero.visibleTextFragments(in: NSRange(location: 0, length: 1), source: "\u{200B}").isEmpty)
    }

    func testImageAndViewFragmentsUseExactPlacementRectangles() throws {
        let source = "a\u{FFFC}b\u{FFFC}"
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: source, attributes: [.font: font]),
            attachments: [1: .init(id: "image", image: UIImage(), size: CGSize(width: 13, height: 37))],
            viewAttachments: [3: .init(id: "view", viewID: "badge", size: CGSize(width: 29, height: 11))]
        )
        let result = layout(document)
        XCTAssertEqual(
            result.visibleTextFragments(in: NSRange(location: 1, length: 1), source: source).first?.rect,
            result.attachments.first?.rect
        )
        XCTAssertEqual(
            result.visibleTextFragments(in: NSRange(location: 3, length: 1), source: source).first?.rect,
            result.viewAttachments.first?.rect
        )
    }

    func testRunFontsAndActualBaselineOffsetExcludeParagraphSpacing() throws {
        let source = "abc"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 70
        paragraph.paragraphSpacing = 80
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .paragraphStyle: paragraph])
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 40), .baselineOffset: 9],
            range: NSRange(location: 1, length: 1)
        )
        text.addAttribute(.baselineOffset, value: -7, range: NSRange(location: 2, length: 1))
        let result = try layout(LYGlyphTextDocument(attributedText: text))
        for location in 0 ..< 3 {
            let piece = try XCTUnwrap(result.visibleTextFragments(
                in: NSRange(location: location, length: 1),
                source: source
            ).first?.runs.first)
            let shift: CGFloat = location == 1 ? 9 : location == 2 ? -7 : 0
            XCTAssertEqual(CTFontGetSize(piece.font), location == 1 ? 40 : 24, accuracy: 0.001)
            XCTAssertEqual(piece.baseline.y, result.lines[0].baseline.y - shift, accuracy: 0.001)
            XCTAssertEqual(
                piece.rect.height,
                CTFontGetAscent(piece.font) + CTFontGetDescent(piece.font),
                accuracy: 0.001
            )
            XCTAssertEqual(piece.rect.minY, piece.baseline.y - CTFontGetAscent(piece.font), accuracy: 0.001)
        }
    }

    func testAdjacentActionsPreserveNativeLigatureAndPartitionItsAdvance() throws {
        let fixtureFont = try XCTUnwrap(UIFont(name: "Baskerville", size: 36))
        let text = NSAttributedString(string: "fi", attributes: [.font: fixtureFont, .ligature: 1])
        let plain = try layout(LYGlyphTextDocument(attributedText: text))
        let actions = [0, 1].map { LYGlyphTextAction(actionID: "same", range: NSRange(location: $0, length: 1)) }
        let acted = try layout(LYGlyphTextDocument(attributedText: text, actions: actions))
        XCTAssertLessThan(CTLineGetGlyphCount(plain.lines[0].text), 2, "Fixture must really ligate")
        XCTAssertEqual(shaping(plain), shaping(acted))
        let left = try XCTUnwrap(acted.visibleTextFragments(in: actions[0].range, source: "fi").first)
        let right = try XCTUnwrap(acted.visibleTextFragments(in: actions[1].range, source: "fi").first)
        XCTAssertGreaterThan(left.rect.width, 0)
        XCTAssertGreaterThan(right.rect.width, 0)
        XCTAssertEqual(left.rect.maxX, right.rect.minX)
        XCTAssertEqual(left.rect.intersection(right.rect).width, 0)
        XCTAssertEqual(left.rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(
            right.rect.maxX,
            CGFloat(CTLineGetTypographicBounds(acted.lines[0].text, nil, nil, nil)),
            accuracy: 0.001
        )
    }

    func testDeterministicFallbackUsesWholeGraphemesAndReversesRTL() {
        XCTAssertEqual(LigatureCells.boundaries(minX: 3, maxX: 15, count: 3, rightToLeft: false), [3, 7, 11, 15])
        XCTAssertEqual(LigatureCells.boundaries(minX: 3, maxX: 15, count: 3, rightToLeft: true), [15, 11, 7, 3])
        XCTAssertTrue(LigatureCells.boundaries(minX: 0, maxX: .infinity, count: 2, rightToLeft: false).isEmpty)
    }

    func testInvalidRangesAndNonfiniteCoordinatesReturnNoFragments() throws {
        let result = try layout("abc")
        for range in [
            NSRange(location: Int.max, length: Int.max),
            NSRange(location: -1, length: 2),
            NSRange(location: 0, length: 0)
        ] {
            XCTAssertTrue(result.visibleTextFragments(in: range, source: "abc").isEmpty)
        }
        let line = result.lines[0]
        let invalid = LYGlyphTextLayout(
            size: .zero,
            lines: [.init(
                text: line.text,
                baseline: CGPoint(x: CGFloat.infinity, y: 0),
                visibleSourceRanges: line.visibleSourceRanges,
                sourceOffset: 0,
                truncationTokenRange: nil
            )]
        )
        XCTAssertTrue(invalid.visibleTextFragments(in: NSRange(location: 0, length: 3), source: "abc").isEmpty)
        let negative = LYGlyphTextLayout(
            size: .zero,
            lines: [.init(
                text: line.text,
                baseline: CGPoint(x: -30, y: -20),
                visibleSourceRanges: line.visibleSourceRanges,
                sourceOffset: 0,
                truncationTokenRange: nil
            )]
        )
        XCTAssertLessThan(
            try XCTUnwrap(negative.visibleTextFragments(in: NSRange(location: 0, length: 1), source: "abc").first).rect
                .minX,
            0
        )
    }

    func testLocalRunMetadataAndShiftedPositionsComeFromFinalTruncatedLine() throws {
        let source = "first line second line third line fourth line fifth line"
        let result = try layout(source, width: 100, limit: 2)
        let line = try XCTUnwrap(result.lines.last)
        let range = try XCTUnwrap(line.visibleSourceRanges.first)
        let fragments = result.visibleTextFragments(in: range, source: source)
        let runs = try XCTUnwrap(CTLineGetGlyphRuns(line.text) as? [CTRun])
        for piece in fragments.flatMap(\.runs) {
            XCTAssertEqual(piece.lineRange.location, CTLineGetStringRange(line.text).location)
            XCTAssertTrue(runs.contains {
                let range = CTRunGetStringRange($0)
                return range.location == piece.runRange.location && range.length == piece.runRange.length
            })
            XCTAssertGreaterThanOrEqual(piece.sourceRange.location, line.sourceOffset)
            XCTAssertFalse(piece.glyphBaselines.isEmpty)
            XCTAssertTrue(piece.glyphBaselines.allSatisfy { $0.y == piece.baseline.y })
        }
        XCTAssertFalse(fragments.isEmpty)
        let firstLocal = range.location - line.sourceOffset
        let expected = CTLineGetOffsetForStringIndex(line.text, firstLocal, nil) + line.baseline.x
        XCTAssertEqual(try XCTUnwrap(fragments.first).rect.minX, expected, accuracy: 0.001)
    }

    func testAdjacentDifferentFontsAndBaselinesKeepExactVerticalRectangles() throws {
        let source = "ABC"
        let text = NSMutableAttributedString(string: source, attributes: [.font: font])
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 40), .baselineOffset: 9],
            range: NSRange(location: 1, length: 1)
        )
        text.addAttribute(.baselineOffset, value: -7, range: NSRange(location: 2, length: 1))
        let result = try layout(LYGlyphTextDocument(attributedText: text))
        let fragments = result.visibleTextFragments(in: NSRange(location: 0, length: 3), source: source)
        XCTAssertEqual(fragments.count, 3)
        for fragment in fragments {
            let piece = try XCTUnwrap(fragment.runs.first)
            XCTAssertEqual(fragment.rect.minY, piece.rect.minY)
            XCTAssertEqual(fragment.rect.maxY, piece.rect.maxY)
        }
    }

    func testVisuallyTouchingFragmentsDoNotBridgeUnrepresentedSourceGap() throws {
        let source = "a\u{200B}c"
        let result = try layout(source)
        let fragments = result.visibleTextFragments(in: NSRange(location: 0, length: 3), source: source)
        XCTAssertTrue(result.visibleTextFragments(in: NSRange(location: 1, length: 1), source: source).isEmpty)
        XCTAssertEqual(fragments.map(\.sourceRange), [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
    }

    func testClusterLookupHasLogarithmicBoundaryVisitsAndEnumeratesOnlyCoverage() {
        let count = 5000
        let index = SourceClusterIndex(source: String(repeating: "a", count: count) as NSString)
        for range in [
            NSRange(location: 0, length: 1),
            NSRange(location: 2500, length: 1),
            NSRange(location: 4999, length: 1),
            NSRange(location: 0, length: count)
        ] {
            var comparisons = 0
            let covered = index.overlapping(range) { _ in comparisons += 1 }
            XCTAssertLessThanOrEqual(comparisons, 26, "Only the two boundary searches are logarithmic")
            XCTAssertEqual(covered.count, range.length, "Full coverage still enumerates all N clusters")
            XCTAssertEqual(covered.first?.location, range.location)
            XCTAssertEqual(covered.last.map(NSMaxRange), NSMaxRange(range))
        }
    }

    func testClusterIndexExpandsUTF16InteriorToWholeGraphemes() {
        let source = "ae\u{301}👩🏽‍💻b"
        let index = SourceClusterIndex(source: source as NSString)
        XCTAssertEqual(Array(index.overlapping(NSRange(location: 2, length: 1))), [NSRange(location: 1, length: 2)])
        XCTAssertEqual(Array(index.overlapping(NSRange(location: 4, length: 1))), [NSRange(location: 3, length: 7)])
        XCTAssertTrue(index.overlapping(NSRange(location: 11, length: 1)).isEmpty)
        XCTAssertTrue(index.overlapping(NSRange(location: Int.max, length: Int.max)).isEmpty)
    }

    func testFiveThousandCharacterQueriesMatchFullGeometryAtBeginningMiddleAndEnd() throws {
        let source = String(repeating: "a", count: 5000)
        for width: CGFloat in [240, 100_000] {
            let result = try layout(source, width: width)
            let whole = result.visibleTextFragments(in: NSRange(location: 0, length: 5000), source: source)
            let allPieces = whole.flatMap(\.runs)
            XCTAssertEqual(Set(allPieces.map(\.sourceRange)).count, 5000)
            for location in [0, 2500, 4999] {
                let range = NSRange(location: location, length: 1)
                let fragment = try XCTUnwrap(result.visibleTextFragments(in: range, source: source).first)
                let expected = try XCTUnwrap(allPieces.first { $0.sourceRange == range })
                XCTAssertEqual(fragment.sourceRange, range)
                XCTAssertEqual(fragment.rect, expected.rect)
                XCTAssertEqual(fragment.runs.first?.baseline, expected.baseline)
                XCTAssertEqual(fragment.runs.first?.runRange, expected.runRange)
                XCTAssertEqual(fragment.runs.first?.lineRange, expected.lineRange)
            }
        }
    }

    private func shaping(_ layout: LYGlyphTextLayout) -> [String] {
        layout.lines.flatMap { line in
            (CTLineGetGlyphRuns(line.text) as! [CTRun]).map { run in
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                return "\(glyphs) \(positions) \(advances) \(line.baseline)"
            }
        }
    }
}
