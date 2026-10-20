import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class ActionGeometryTests: XCTestCase {
    func testRealLigatureKeepsSeparateSameIDActionsAndHalfOpenBoundary() throws {
        let font = try XCTUnwrap(UIFont(name: "Baskerville", size: 36))
        let actions = [0, 1].map { LYGlyphTextAction(actionID: "same", range: NSRange(location: $0, length: 1)) }
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "fi", attributes: [.font: font, .ligature: 1]), actions: actions
        )
        let layout = ResolvedText(document: document, traits: .init()).layout(width: 200, insets: .zero, scale: 2)
        XCTAssertLessThan(CTLineGetGlyphCount(layout.lines[0].text), 2)
        let geometry = ActionGeometry(
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            configuration: .init()
        )
        XCTAssertEqual(geometry.entries.count, 2)
        let first = try XCTUnwrap(geometry.entries.first?.rects.first)
        let second = try XCTUnwrap(geometry.entries.last?.rects.first)
        XCTAssertEqual(first.maxX, second.minX)
        XCTAssertEqual(geometry.hit(at: CGPoint(x: first.midX, y: first.midY))?.actionIndex, 0)
        XCTAssertEqual(geometry.hit(at: CGPoint(x: first.maxX, y: first.midY))?.actionIndex, 1)
        XCTAssertNil(geometry.hit(at: CGPoint(x: second.maxX, y: second.midY)))
    }

    private func layout(
        _ source: String, width: CGFloat = 110, configuration: LYGlyphTextConfiguration = .init(),
        actions: [LYGlyphTextAction]? = nil, attributes: [NSAttributedString.Key: Any] = [:],
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) throws -> LYGlyphTextLayout {
        var attributes = attributes
        attributes[.font] = attributes[.font] ?? UIFont.systemFont(ofSize: 24)
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: source, attributes: attributes),
            actions: actions ?? [.init(actionID: "whole", range: NSRange(location: 0, length: source.utf16.count))]
        )
        return ResolvedText(document: document, traits: .init()).layout(
            width: width, insets: configuration.insets, scale: 2,
            numberOfLines: configuration.numberOfLines, observe: observe
        )
    }

    private func geometry(_ layout: LYGlyphTextLayout) -> ActionGeometry {
        ActionGeometry(layout: layout, bounds: CGRect(x: 0, y: 0, width: 400, height: 500), configuration: .init())
    }

    func testCrossLineFragmentsPreserveFullEventRangeAndRejectGapsAndOutside() throws {
        let source = "alpha beta gamma delta epsilon zeta"
        let layout = try layout(source)
        let geometry = geometry(layout)
        let entry = try XCTUnwrap(geometry.entries.first)
        XCTAssertGreaterThan(layout.lines.count, 2)
        XCTAssertEqual(entry.event(kind: .longPress).range, NSRange(location: 0, length: source.utf16.count))
        XCTAssertEqual(entry.event(kind: .longPress).kind, .longPress)
        for rect in entry.rects {
            XCTAssertEqual(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY))?.actionIndex, 0)
        }
        let union = entry.rects.reduce(CGRect.null) { $0.union($1) }
        XCTAssertNil(geometry.hit(at: CGPoint(x: union.minX - 1, y: union.midY)))
        XCTAssertNil(geometry.hit(at: CGPoint(x: union.maxX + 1, y: union.midY)))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 40
        let spaced = try self.layout("a\nb", attributes: [.paragraphStyle: paragraph])
        let spacedGeometry = self.geometry(spaced)
        let rects = try XCTUnwrap(spacedGeometry.entries.first?.rects)
        XCTAssertLessThan(rects[0].maxY, rects[1].minY)
        XCTAssertNil(spacedGeometry.hit(at: CGPoint(x: rects[0].midX, y: (rects[0].maxY + rects[1].minY) / 2)))
    }

    func testBidiAndUnicodeCellsUseOnlyVisibleSourcePieces() throws {
        for source in ["abc אבג def", "abc مرحبا def", "e\u{301} 👩🏽‍💻 fin"] {
            let layout = try layout(source, width: 400)
            let geometry = geometry(layout)
            let cells = try XCTUnwrap(layout.sourceGeometry?.cells)
            for cell in cells where !cell.isWhitespace {
                XCTAssertEqual(
                    cell.range,
                    (source as NSString).rangeOfComposedCharacterSequence(at: cell.range.location)
                )
                for piece in cell.pieces where piece.rect.width > 0 {
                    XCTAssertNotNil(geometry.hit(at: CGPoint(x: piece.rect.midX, y: piece.rect.midY)), source)
                }
            }
        }
    }

    func testEachLineTrailingWhitespaceIsExcludedButInternalWhitespaceRemains() throws {
        let source = "a b  \nc d  "
        let layout = try layout(source, width: 400)
        let geometry = geometry(layout)
        for index in [1, 7] {
            let rect = try XCTUnwrap(layout
                .visibleTextFragments(in: NSRange(location: index, length: 1), source: source).first?.rect)
            XCTAssertNotNil(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
        }
        for index in [3, 4, 9, 10] {
            let rect = try XCTUnwrap(layout
                .visibleTextFragments(in: NSRange(location: index, length: 1), source: source).first?.rect)
            XCTAssertNil(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
        }
    }

    func testTruncationTokenAndHiddenSourceHaveNoActionAndKeepFullRange() throws {
        let source = "one two three four five six seven eight nine ten"
        let config = LYGlyphTextConfiguration(numberOfLines: 2)
        let layout = try layout(source, configuration: config)
        let geometry = geometry(layout)
        let last = try XCTUnwrap(layout.lines.last)
        XCTAssertGreaterThan(last.sourceOffset, 0)
        let token = try XCTUnwrap(last.truncationTokenRange)
        let tokenGroups = try XCTUnwrap(layout.sourceGeometry?.glyphGroups.filter { $0.origin == .generatedToken })
        XCTAssertFalse(tokenGroups.isEmpty)
        XCTAssertTrue(tokenGroups.allSatisfy(\.sourceCells.isEmpty))
        var secondary: CGFloat = 0
        let x = CTLineGetOffsetForStringIndex(last.text, token.location, &secondary) + last.baseline.x
        let width = CGFloat(CTLineGetTypographicBounds(last.text, nil, nil, nil)) - (x - last.baseline.x)
        XCTAssertGreaterThan(width, 0)
        XCTAssertNil(geometry.hit(at: CGPoint(x: x + width / 2, y: last.baseline.y - 5)))
        XCTAssertTrue(layout.visibleTextFragments(
            in: NSRange(location: source.utf16.count - 1, length: 1),
            source: source
        ).isEmpty)
        XCTAssertEqual(geometry.entries.first?.event(kind: .tap).range.length, source.utf16.count)
        for group in layout.sourceGeometry?.glyphGroups ?? [] {
            guard case let .source(range) = group.origin else { continue }
            XCTAssertEqual(range.location - layout.lines[group.lineIndex].sourceOffset, group.localRange.location)
        }
    }

    func testDisplayTranslationInsetsAlignmentAndShortHeightClipMatchSharedGeometry() throws {
        for alignment in [LYGlyphTextConfiguration.VerticalAlignment.top, .center, .bottom] {
            let config = LYGlyphTextConfiguration(
                textContainerInset: UIEdgeInsets(top: 3, left: 7, bottom: 5, right: 11), verticalAlignment: alignment
            )
            let layout = try layout("abc", width: 180, configuration: config)
            for height in [CGFloat(15), 140] {
                let bounds = CGRect(x: 19, y: 23, width: 180, height: height)
                let display = try XCTUnwrap(DisplayGeometry(
                    bounds: bounds,
                    layoutSize: layout.size,
                    configuration: config
                ))
                let expected = try layout.actionIndex[0].rects.compactMap { rect -> CGRect? in
                    let translated = try XCTUnwrap(display.displayRect(rect))
                    let clipped = translated.intersection(bounds).intersection(display.contentClip)
                    return clipped.isEmpty || clipped.isNull ? nil : clipped
                }
                let geometry = ActionGeometry(layout: layout, bounds: bounds, configuration: config)
                XCTAssertEqual(geometry.entries.first?.rects ?? [], expected)
                XCTAssertNil(geometry.hit(at: CGPoint(x: bounds.minX, y: bounds.minY)))
                for rect in expected {
                    XCTAssertNotNil(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
                }
            }
        }
    }

    func testAttachmentActionsUsePlacementRectanglesRegardlessDescriptorInteractivity() throws {
        let source = "a\u{FFFC}b\u{FFFC}"
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: source, attributes: [.font: UIFont.systemFont(ofSize: 24)]),
            attachments: [1: .init(id: "image", image: UIImage(), size: CGSize(width: 13, height: 37))],
            viewAttachments: [3: .init(
                id: "view",
                viewID: "badge",
                size: CGSize(width: 29, height: 11),
                isInteractive: true
            )],
            actions: [1, 3].map { .init(actionID: "same", range: NSRange(location: $0, length: 1)) }
        )
        let layout = ResolvedText(document: document, traits: .init()).layout(width: 300, insets: .zero, scale: 2)
        let geometry = geometry(layout)
        XCTAssertEqual(layout.actionIndex[0].rects, layout.attachments.map(\.rect))
        XCTAssertEqual(
            geometry.entries[0].rects,
            layout.attachments.map { $0.rect.intersection(CGRect(x: 0, y: 0, width: 400, height: 500)) }
        )
        XCTAssertEqual(geometry.entries[1].rects, layout.viewAttachments.map(\.rect))
        for entry in geometry.entries {
            let rect = try XCTUnwrap(entry.rects.first)
            XCTAssertEqual(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY))?.actionIndex, entry.actionIndex)
        }
    }

    func testActualOverlappingLineBoxesUseOriginalActionOrder() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        let actions = [2, 0].map { LYGlyphTextAction(actionID: "same", range: NSRange(location: $0, length: 1)) }
        let layout = try layout("a\nb", actions: actions, attributes: [.paragraphStyle: paragraph])
        let geometry = geometry(layout)
        let a = try XCTUnwrap(geometry.entries.first?.rects.first)
        let b = try XCTUnwrap(geometry.entries.last?.rects.first)
        let intersection = a.intersection(b)
        XCTAssertGreaterThan(intersection.width, 0)
        XCTAssertGreaterThan(intersection.height, 0)
        XCTAssertEqual(geometry.hit(at: CGPoint(x: intersection.midX, y: intersection.midY))?.actionIndex, 0)
    }

    func testSourceSnapshotAndDecorationPreparationDoNotRepeatDuringDrawing() throws {
        var events: [TextDecorations.PreparationEvent: Int] = [:]
        let layout = try layout(
            "abc def", attributes: [
                .backgroundColor: UIColor.yellow,
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash
                    .rawValue,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ],
            observe: { events[$0, default: 0] += 1 }
        )
        XCTAssertEqual(events[.sourceSnapshot], 1)
        XCTAssertEqual(events[.geometryQuery], 1)
        XCTAssertGreaterThan(events[.styleComparison] ?? 0, 0)
        XCTAssertGreaterThan(events[.groupComparison] ?? 0, 0)
        let before = events
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        for _ in 0 ..< 4 {
            _ = renderer.image { layout.draw(in: $0.cgContext, observe: { events[$0, default: 0] += 1 }) }
        }
        XCTAssertEqual(events[.drawCachedContent], 4)
        XCTAssertGreaterThan(events[.strokeIntervalDraw] ?? 0, 0)
        events.removeValue(forKey: .drawCachedContent)
        events.removeValue(forKey: .strokeIntervalDraw)
        XCTAssertEqual(events, before)
        XCTAssertNotNil(layout.sourceGeometry)
        let plain = try self.layout("plain action")
        XCTAssertFalse(try XCTUnwrap(plain.sourceGeometry?.cells).isEmpty)
        XCTAssertFalse(plain.actionIndex[0].rects.isEmpty)
    }

    func testGlyphGroupCoverageKeepsLigatureCellsAndActualNoncontiguousGlyphIndices() throws {
        let font = try XCTUnwrap(UIFont(name: "Baskerville", size: 36))
        let layout = try layout("fi", width: 200, attributes: [.font: font, .ligature: 1])
        XCTAssertLessThan(CTLineGetGlyphCount(layout.lines[0].text), 2)
        let cells = try XCTUnwrap(layout.sourceGeometry?.cells)
        XCTAssertEqual(cells.count, 2)
        for cell in cells {
            let piece = try XCTUnwrap(cell.pieces.first)
            XCTAssertEqual(piece.glyphIndices, [0])
            XCTAssertEqual(piece.glyphRange, 0 ..< 1)
            XCTAssertEqual(piece.groupSourceRange, NSRange(location: 0, length: 2))
            XCTAssertEqual(piece.groupSourceCells, cells.map(\.range))
            XCTAssertEqual(piece.lineIndex, 0)
            XCTAssertEqual(piece.runIndex, 0)
        }
        let original = try XCTUnwrap(cells.first?.pieces.first)
        let noncontiguous = VisibleTextFragment.RunPiece(
            sourceRange: original.sourceRange, lineIndex: original.lineIndex, runIndex: original.runIndex,
            glyphIndices: [0, 2], groupSourceRange: original.groupSourceRange,
            groupSourceCells: original.groupSourceCells, lineRange: original.lineRange, runRange: original.runRange,
            font: original.font, baseline: original.baseline, glyphBaselines: original.glyphBaselines,
            rect: original.rect
        )
        XCTAssertNil(noncontiguous.glyphRange)
        let groups = GlyphShapingGroups.members(indices: [3, 1, 3, 0, 1])
        XCTAssertEqual(groups[3], [0, 2])
        XCTAssertEqual(groups[1], [1, 4])
        XCTAssertEqual(groups[0], [3])
    }

    func testDecorationMetadataRetainsExplicitAndInheritedSameColorAndBatchMembers() throws {
        let text = NSMutableAttributedString(string: "abcd", attributes: [
            .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.red, .backgroundColor: UIColor.yellow,
            .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ])
        text.addAttributes(
            [.underlineColor: UIColor.red, .strikethroughColor: UIColor.red],
            range: NSRange(location: 2, length: 2)
        )
        let document = try LYGlyphTextDocument(attributedText: text)
        let layout = ResolvedText(document: document, traits: .init()).layout(width: 300, insets: .zero, scale: 2)
        let prepared = try XCTUnwrap(layout.preparedDecorations)
        XCTAssertEqual(prepared.fills.flatMap(\.members).map(\.styleIndex), [0, 0, 1, 1])
        XCTAssertEqual(Set(prepared.strokes.filter(\.colorIsInherited).map(\.member.styleIndex)), [0])
        XCTAssertEqual(Set(prepared.strokes.filter { !$0.colorIsInherited }.map(\.member.styleIndex)), [1])
        XCTAssertTrue(prepared.groups.allSatisfy { !$0.mergedIntervals.isEmpty && !$0.members.isEmpty })
        XCTAssertEqual(prepared.groups.flatMap(\.members).count, prepared.strokes.count)
    }

    func testVisibleWhitespaceImmediatelyBeforeGeneratedTokenIsStillLineTrailing() throws {
        let source = "a  hidden"
        let text = NSAttributedString(string: "a  …", attributes: [.font: UIFont.systemFont(ofSize: 24)])
        let line = LYGlyphTextLayout.Line(
            text: CTLineCreateWithAttributedString(text), baseline: CGPoint(x: 0, y: 30),
            visibleSourceRanges: [NSRange(location: 0, length: 3)], sourceOffset: 0,
            truncationTokenRange: NSRange(location: 3, length: 1)
        )
        let layout = LYGlyphTextLayout(
            size: CGSize(width: 200, height: 40), lines: [line], source: source,
            actions: [.init(actionID: "whole", range: NSRange(location: 0, length: source.utf16.count))]
        )
        let geometry = geometry(layout)
        for location in [1, 2] {
            let rect = try XCTUnwrap(layout.visibleTextFragments(
                in: NSRange(location: location, length: 1),
                source: source
            ).first?.rect)
            XCTAssertNil(geometry.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
        }
        XCTAssertEqual(geometry.entries[0].event(kind: .tap).range, NSRange(location: 0, length: 9))
    }

    func testNativeSolidUnderlineCachesOwnershipWithoutAddingFallbackDrawing() throws {
        let layout = try layout("abc", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        let prepared = try XCTUnwrap(layout.preparedDecorations)
        XCTAssertTrue(prepared.groups.isEmpty)
        XCTAssertFalse(prepared.nativeUnderlineGroups.isEmpty)
        XCTAssertEqual(prepared.nativeUnderlineGroups.flatMap(\.members).count, prepared.strokes.count)
        XCTAssertTrue(prepared.nativeUnderlineGroups.allSatisfy { !$0.mergedIntervals.isEmpty })
    }

    func testActualZeroAdvanceGroupKeepsSourceOwnershipWithoutActionCell() throws {
        for source in ["a\u{200B}", "a\u{200B}c", "\u{200B}a", "אב\u{200B}", "a\u{200B}אב", "אב\u{200B}a"] {
            let location = (source as NSString).range(of: "\u{200B}").location
            let range = NSRange(location: location, length: 1)
            let layout = try layout(source)
            let snapshot = try XCTUnwrap(layout.sourceGeometry)
            XCTAssertFalse(snapshot.cells.contains { $0.range == range }, source)
            XCTAssertTrue(snapshot.glyphGroups.contains { group in
                guard case let .source(coverage) = group.origin else { return false }
                return NSLocationInRange(location, coverage) && group.sourceCells.contains(range)
            }, source)
            XCTAssertTrue(layout.visibleTextFragments(in: range, source: source).isEmpty, source)
        }
    }
}
