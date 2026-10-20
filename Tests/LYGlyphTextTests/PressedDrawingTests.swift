import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class PressedDrawingTests: XCTestCase {
    private let canvas = CGSize(width: 360, height: 240)
    private let font = UIFont(name: "Baskerville", size: 42)!

    private func document(
        _ string: String,
        attributes: [NSAttributedString.Key: Any] = [:],
        actions: [LYGlyphTextAction] = []
    ) throws -> LYGlyphTextDocument {
        var values: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.green]
        values.merge(attributes) { _, new in new }
        return try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: string, attributes: values),
            actions: actions
        )
    }

    private func layout(
        _ document: LYGlyphTextDocument,
        width: CGFloat = 330,
        lines: Int = 0,
        traits: UITraitCollection = .init(userInterfaceStyle: .light),
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) -> LYGlyphTextLayout {
        ResolvedText(document: document, traits: traits).layout(
            width: width,
            insets: .init(top: 12, left: 12, bottom: 8, right: 8),
            scale: 2,
            numberOfLines: lines,
            observe: observe
        )
    }

    private func signature(_ value: LYGlyphTextLayout) throws -> String {
        func numbers(_ values: [CGFloat]) -> [Double] {
            values.map { (Double($0) * 1_000_000).rounded() / 1_000_000 }
        }
        func range(_ value: NSRange) -> [Int] {
            [value.location, value.length]
        }
        var lineValues: [[String: Any]] = []
        for line in value.lines {
            var runValues: [[String: Any]] = []
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
                runValues.append([
                    "glyphs": glyphs.map(Int.init), "positions": positions.map { numbers([$0.x, $0.y]) },
                    "advances": advances.map { numbers([$0.width, $0.height]) }, "indices": indices,
                    "matrix": numbers([matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]),
                    "font": CTFontCopyPostScriptName(font) as String, "fontSize": numbers([CTFontGetSize(font)]),
                    "traits": CTFontGetSymbolicTraits(font).rawValue,
                    "metrics": numbers([CGFloat(width), ascent, descent, leading])
                ])
            }
            lineValues.append([
                "baseline": numbers([line.baseline.x, line.baseline.y]),
                "visible": line.visibleSourceRanges.map(range),
                "offset": line.sourceOffset,
                "token": line.truncationTokenRange.map(range) ?? [],
                "runs": runValues
            ])
        }
        let mapping = value.sourceGeometry?.cells.map { cell -> [String: Any] in
            ["range": range(cell.range), "line": cell.lineIndex, "pieces": cell.pieces.map { piece -> [String: Any] in
                [
                    "run": piece.runIndex,
                    "glyphs": piece.glyphIndices,
                    "group": range(piece.groupSourceRange),
                    "rect": numbers([piece.rect.minX, piece.rect.minY, piece.rect.width, piece.rect.height]),
                    "baseline": numbers([piece.baseline.x, piece.baseline.y])
                ]
            }]
        } ?? []
        let placements = value.attachments.map { [Double($0.sourceLocation)] + numbers([
            $0.rect.minX,
            $0.rect.minY,
            $0.rect.width,
            $0.rect.height
        ]) }
        let object: [String: Any] = [
            "size": numbers([value.size.width, value.size.height]),
            "lines": lineValues,
            "mapping": mapping,
            "placements": placements
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func baselineFixtures() throws -> [(String, LYGlyphTextLayout)] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 20
        paragraph.maximumLineHeight = 20
        return try [
            ("fi", layout(document("fi"))),
            ("mixed", layout(document("fi العربية 😀 A\u{301}"))),
            ("offset", layout(document("first\nsecond fi abcdefghijk"), width: 155, lines: 2)),
            (
                "styles",
                layout(document(
                    "fi AB\nCd",
                    attributes: [.underlineStyle: NSUnderlineStyle.double.rawValue, .kern: 1.25, .baselineOffset: 3.5]
                ))
            ),
            ("overlap", layout(document("Áj\nWÁ", attributes: [.paragraphStyle: paragraph])))
        ]
    }

    func testMigrationBaseline() throws {
        for (name, value) in try baselineFixtures() {
            if name == "fi" { XCTAssertLessThan(value.lines.reduce(0) { $0 + CTLineGetGlyphCount($1.text) }, 2) }
            XCTAssertEqual(try signature(value), PressedMigrationBaseline.signatures[name], name)
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func color(_ x: Int, _ y: Int) -> [UInt8] {
            guard x >= 0, x < width, y >= 0, y < 240 else { return [255, 255, 255] }
            return Array(bytes[(y * width + x) * 4 ..< (y * width + x) * 4 + 3])
        }

        func count(in rect: CGRect, matching: ([UInt8]) -> Bool) -> Int {
            let xs = max(0, Int(ceil(rect.minX))) ..< min(width, max(0, Int(floor(rect.maxX))))
            let ys = max(0, Int(ceil(rect.minY))) ..< min(240, max(0, Int(floor(rect.maxY))))
            return ys.reduce(0) { sum, y in sum + xs.count { matching(color($0, y)) } }
        }
    }

    private func render(
        _ value: LYGlyphTextLayout,
        pressed: Int? = nil,
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in },
        draw: ((CGContext) -> Void)? = nil
    ) throws -> Pixels {
        let width = Int(canvas.width), height = Int(canvas.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: canvas))
            context.translateBy(x: 0, y: canvas.height)
            context.scaleBy(x: 1, y: -1)
            if let draw { draw(context) }
            else { value.draw(in: context, pressedActionIndex: pressed, observe: observe) }
        }
        return Pixels(bytes: bytes, width: width)
    }

    private func red(_ c: [UInt8]) -> Bool {
        c[0] > 180 && c[1] < 100 && c[2] < 100
    }

    private func green(_ c: [UInt8]) -> Bool {
        c[1] > 180 && c[0] < 100 && c[2] < 100
    }

    func testPressedForegroundAndRestorationUseSameLayout() throws {
        let doc = try document(
            "fi XX",
            actions: [
                .init(actionID: "same", range: NSRange(location: 0, length: 1), pressedStyle: .init(
                    foregroundColor: .red,
                    backgroundColor: nil
                )),
                .init(
                    actionID: "same",
                    range: NSRange(location: 3, length: 2),
                    pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
                )
            ]
        )
        let value = layout(doc)
        let before = try signature(value)
        let normal = try render(value), pressed = try render(value, pressed: 0), restored = try render(value)
        let rect = try XCTUnwrap(value.actionIndex.first?.rects.first)
        XCTAssertGreaterThan(pressed.count(in: rect, matching: red), 15)
        XCTAssertGreaterThan(
            pressed.count(in: CGRect(x: rect.maxX, y: rect.minY, width: 100, height: rect.height), matching: green),
            15
        )
        XCTAssertTrue(normal.bytes == restored.bytes)
        XCTAssertFalse(normal.bytes == pressed.bytes)
        XCTAssertEqual(try signature(value), before)
    }

    func testPressedBackgroundReplacesHalfAlphaOnce() throws {
        let doc = try document(
            "A B",
            attributes: [.foregroundColor: UIColor.clear, .backgroundColor: UIColor.blue.withAlphaComponent(0.5)],
            actions: [.init(
                actionID: "tap",
                range: NSRange(location: 0, length: 1),
                pressedStyle: .init(backgroundColor: UIColor.red.withAlphaComponent(0.5))
            )]
        )
        let value = layout(doc)
        let rect = try XCTUnwrap(value.actionIndex.first?.rects.first)
        let normal = try render(value), pressed = try render(value, pressed: 0)
        let c = pressed.color(Int(rect.midX), Int(rect.midY))
        XCTAssertEqual(Int(c[0]), 255, accuracy: 2)
        XCTAssertEqual(Int(c[1]), 128, accuracy: 3)
        XCTAssertEqual(Int(c[2]), 128, accuracy: 3)
        XCTAssertFalse(normal.bytes == pressed.bytes)
    }

    func testPressedBackgroundAppearsWithoutOrdinaryBackground() throws {
        let value = try layout(document("A", attributes: [.foregroundColor: UIColor.clear], actions: [
            .init(actionID: "a", range: NSRange(location: 0, length: 1), pressedStyle: .init(
                backgroundColor: UIColor.red.withAlphaComponent(0.5)
            ))
        ]))
        let rect = try XCTUnwrap(value.actionIndex.first?.rects.first)
        let pixel = try render(value, pressed: 0).color(Int(rect.midX), Int(rect.midY))
        XCTAssertEqual(Int(pixel[0]), 255, accuracy: 2)
        XCTAssertEqual(Int(pixel[1]), 128, accuracy: 3)
        XCTAssertEqual(Int(pixel[2]), 128, accuracy: 3)
    }

    func testPressedCrossStyleBackgroundIsOneEffectiveUnion() throws {
        let text = NSMutableAttributedString(string: "x\u{301}\u{302}", attributes: [
            .font: font, .foregroundColor: UIColor.clear,
            .backgroundColor: UIColor.blue.withAlphaComponent(0.5)
        ])
        text.addAttributes([
            .font: UIFont.systemFont(ofSize: 44), .backgroundColor: UIColor.green.withAlphaComponent(0.5)
        ], range: NSRange(location: 1, length: 1))
        text.addAttribute(.font, value: UIFont.systemFont(ofSize: 46), range: NSRange(location: 2, length: 1))
        let value = try layout(LYGlyphTextDocument(attributedText: text, actions: [
            .init(actionID: "cluster", range: NSRange(location: 0, length: 3), pressedStyle: .init(
                backgroundColor: UIColor.red.withAlphaComponent(0.5)
            ))
        ]))
        let rects = try XCTUnwrap(value.sourceGeometry).cells.flatMap { $0.pieces.map(\.rect) }
        let intersection = try XCTUnwrap(rects.reduce(nil as CGRect?) { $0?.intersection($1) ?? $1 })
        XCTAssertGreaterThan(intersection.width, 2)
        XCTAssertGreaterThan(intersection.height, 2)
        let pixel = try render(value, pressed: 0).color(Int(intersection.midX), Int(intersection.midY))
        XCTAssertEqual(Int(pixel[0]), 255, accuracy: 2)
        XCTAssertEqual(Int(pixel[1]), 128, accuracy: 3)
        XCTAssertEqual(Int(pixel[2]), 128, accuracy: 3)
    }

    func testStrokeOwnershipHonorsEffectiveSourceOrderWithinSameOrdinaryColor() throws {
        let source = "\u{FFFC}\u{FFFC}"
        let rect = CGRect(x: 20.25, y: 14, width: 45.5, height: 55)
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.clear])
        for index in 0 ..< 2 {
            let metrics = AttachmentMetrics(
                size: rect.size,
                ascender: font.ascender,
                descender: font.descender,
                alignment: .bottom
            )
            text.addAttribute(
                .init(kCTRunDelegateAttributeName as String),
                value: metrics.makeDelegate(),
                range: NSRange(location: index, length: 1)
            )
        }
        for inheritedLast in [true, false] {
            let decorations = TextDecorations(source: source, styles: (0 ..< 2).map { index in
                .init(
                    range: NSRange(location: index, length: 1),
                    background: nil,
                    underlineStyle: 0,
                    underlineColor: UIColor.green.cgColor,
                    strikethroughStyle: 2,
                    strikethroughColor: UIColor.green.cgColor,
                    strikethroughColorIsInherited: (index == 1) == inheritedLast
                )
            }, scale: 2)
            let value = LYGlyphTextLayout(size: canvas, lines: [
                .init(
                    text: CTLineCreateWithAttributedString(text),
                    baseline: CGPoint(x: 20.25, y: 58),
                    visibleSourceRanges: [NSRange(location: 0, length: 2)],
                    sourceOffset: 0,
                    truncationTokenRange: nil
                )
            ], viewAttachments: (0 ..< 2).map {
                .init(attachment: .init(id: "v\($0)", viewID: "badge", size: rect.size), sourceLocation: $0, rect: rect)
            }, decorations: decorations, actions: [
                .init(
                    actionID: "a",
                    range: NSRange(location: 0, length: 2),
                    pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
                )
            ])
            let group = try XCTUnwrap(value.preparedDecorations?.allGroups.first)
            XCTAssertEqual(group.members.count, 2)
            let y = group.stroke.center
            let band = CGRect(x: rect.minX + 2, y: y - 3, width: rect.width - 4, height: 6)
            let pixels = try render(value, pressed: 0)
            XCTAssertGreaterThan(pixels.count(in: band, matching: inheritedLast ? red : green), 20)
            XCTAssertEqual(pixels.count(in: band, matching: inheritedLast ? green : red), 0)
        }
    }

    func testDrawingClipDifferenceSplitsAtExclusionHorizontalEdges() {
        let clip = DrawingClip([CGRect(x: 0.25, y: 1.5, width: 30, height: 20)], excluding: [
            CGRect(x: 10.75, y: 1.5, width: 5.25, height: 20)
        ])
        XCTAssertTrue(clip.inside.contains(CGPoint(x: 5, y: 8)))
        XCTAssertFalse(clip.inside.contains(CGPoint(x: 12, y: 8)))
        XCTAssertTrue(clip.inside.contains(CGPoint(x: 20, y: 8)))
    }

    func testOrdinaryCrossStyleSameColorBackgroundCompositesOnce() throws {
        let text = NSMutableAttributedString(string: "x\u{301}\u{302}", attributes: [
            .font: font, .foregroundColor: UIColor.clear,
            .backgroundColor: UIColor.blue.withAlphaComponent(0.5)
        ])
        text.addAttribute(.font, value: UIFont.systemFont(ofSize: 44), range: NSRange(location: 1, length: 1))
        text.addAttribute(.font, value: UIFont.systemFont(ofSize: 46), range: NSRange(location: 2, length: 1))
        let value = try layout(LYGlyphTextDocument(attributedText: text, actions: [
            .init(
                actionID: "cluster",
                range: NSRange(location: 0, length: 3),
                pressedStyle: .init(backgroundColor: nil)
            )
        ]))
        let rects = try XCTUnwrap(value.sourceGeometry).cells.flatMap { $0.pieces.map(\.rect) }
        XCTAssertGreaterThan(rects.count, 1)
        let intersection = try XCTUnwrap(rects.reduce(nil as CGRect?) { $0?.intersection($1) ?? $1 })
        XCTAssertGreaterThan(intersection.width, 2)
        let normal = try render(value), pressed = try render(value, pressed: 0)
        let pixel = normal.color(Int(intersection.midX), Int(intersection.midY))
        XCTAssertEqual(Int(pixel[0]), 128, accuracy: 3)
        XCTAssertEqual(Int(pixel[1]), 128, accuracy: 3)
        XCTAssertEqual(Int(pixel[2]), 255, accuracy: 2)
        XCTAssertTrue(normal.bytes == pressed.bytes, "nil pressed background must retain the original union")
    }

    func testDynamicForegroundAndBackgroundResolveForEachTrait() throws {
        let ordinary = UIColor { $0.userInterfaceStyle == .dark ? .cyan : .green }
        let foreground = UIColor { $0.userInterfaceStyle == .dark ? .yellow : .red }
        let background = UIColor { $0.userInterfaceStyle == .dark ? .blue : .magenta }
        let doc = try document("AA", attributes: [.foregroundColor: ordinary], actions: [
            .init(actionID: "a", range: NSRange(location: 0, length: 1), pressedStyle: .init(
                foregroundColor: foreground, backgroundColor: background
            ))
        ])
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let value = layout(doc, traits: traits)
            let action = try XCTUnwrap(value.actionIndex.first?.rects.first)
            let normal = try render(value), pressed = try render(value, pressed: 0)
            let fg = style == .dark ? [255, 255, 0] : [255, 0, 0]
            let bg = style == .dark ? [0, 0, 255] : [255, 0, 255]
            XCTAssertGreaterThan(pressed.count(in: action) { zip($0, fg).allSatisfy { abs(Int($0.0) - $0.1) < 4 } }, 15)
            XCTAssertGreaterThan(pressed.count(in: action) { zip($0, bg).allSatisfy { abs(Int($0.0) - $0.1) < 4 } }, 15)
            XCTAssertFalse(normal.bytes == pressed.bytes)
            XCTAssertTrue(try normal.bytes == render(value).bytes)
        }
    }

    func testDefaultPressedBackgroundAndExplicitNilHaveDifferentBehavior() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let base: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
            let defaultValue = try layout(document("A", attributes: base, actions: [
                .init(actionID: "a", range: NSRange(location: 0, length: 1))
            ]), traits: traits)
            let nilValue = try layout(document("A", attributes: base, actions: [
                .init(actionID: "a", range: NSRange(location: 0, length: 1), pressedStyle: .init(backgroundColor: nil))
            ]), traits: traits)
            let rect = try XCTUnwrap(defaultValue.actionIndex.first?.rects.first)
            let changed = try render(defaultValue, pressed: 0).color(Int(rect.midX), Int(rect.midY))
            let clear = try render(nilValue, pressed: 0).color(Int(rect.midX), Int(rect.midY))
            XCTAssertEqual(clear, [255, 255, 255])
            XCTAssertNotEqual(changed, clear)
            let reference = try render(defaultValue, draw: { context in
                context.setFillColor(UIColor.tertiarySystemFill.resolvedColor(with: traits).cgColor)
                context.fill(rect)
            }).color(Int(rect.midX), Int(rect.midY))
            XCTAssertEqual(changed, reference)
        }
    }

    func testColorEmojiKeepsItsActualMulticolorPixelsWhenPressed() throws {
        let value = try layout(document("😀", actions: [
            .init(actionID: "emoji", range: NSRange(location: 0, length: 2), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: nil
            ))
        ]))
        let rect = try XCTUnwrap(value.actionIndex.first?.rects.first)
        let normal = try render(value), pressed = try render(value, pressed: 0)
        XCTAssertGreaterThan(
            normal.count(in: rect) { $0[0] > 180 && $0[1] > 100 && $0[2] < 80 },
            30,
            "must contain actual yellow emoji pixels, not a monochrome font-trait assertion"
        )
        XCTAssertGreaterThan(normal.count(in: rect) { $0.max()! - $0.min()! > 60 }, 100)
        XCTAssertTrue(normal.bytes == pressed.bytes)
    }

    func testRTLAndTruncatedSourceOffsetKeepTokenOrdinary() throws {
        let source = "head\nالعربية MMMM MMMM MMMM MMMM"
        let value = try layout(document(source, actions: [
            .init(actionID: "rtl", range: NSRange(location: 5, length: source.utf16.count - 5), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: nil
            ))
        ]), width: 195, lines: 2)
        let line = try XCTUnwrap(value.lines.last), token = try XCTUnwrap(line.truncationTokenRange)
        XCTAssertGreaterThan(line.sourceOffset, 0)
        let normal = try render(value), pressed = try render(value, pressed: 0)
        let x1 = line.baseline.x + CTLineGetOffsetForStringIndex(line.text, token.location, nil)
        let x2 = line.baseline.x + CTLineGetOffsetForStringIndex(line.text, NSMaxRange(token), nil)
        let tokenRect = CGRect(
            x: min(x1, x2),
            y: line.baseline.y - font.ascender,
            width: abs(x2 - x1),
            height: font.lineHeight
        )
        XCTAssertGreaterThan(pressed.count(in: tokenRect, matching: green), 5)
        XCTAssertEqual(pressed.count(in: tokenRect, matching: red), 0)
        XCTAssertGreaterThan(value.actionIndex[0].rects.reduce(0) { $0 + pressed.count(in: $1, matching: red) }, 15)
        XCTAssertFalse(normal.bytes == pressed.bytes)
        XCTAssertTrue(value.sourceGeometry?.glyphGroups.contains { $0.origin == .generatedToken } == true)
    }

    func testRealCompressedLinesPreserveUnrelatedLaterInkInActionRect() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 12
        paragraph.maximumLineHeight = 12
        let value = try layout(document("MMMM\nMMMM", attributes: [.paragraphStyle: paragraph], actions: [
            .init(actionID: "first", range: NSRange(location: 0, length: 4), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: nil
            ))
        ]))
        XCTAssertEqual(value.lines.count, 2)
        let firstRect = try XCTUnwrap(value.actionIndex[0].rects.first)
        let lastRect = try XCTUnwrap(value.sourceGeometry?.cells.first { $0.lineIndex == 1 }?.pieces.first?.rect)
        XCTAssertGreaterThan(
            firstRect.intersection(lastRect).height,
            10,
            "the real Core Text paragraph must produce overlapping line cells"
        )
        let later = value.lines[1]
        let laterOnly = try render(value, draw: { context in
            context.setFillColor(UIColor.green.cgColor)
            context.textMatrix = .identity
            context.scaleBy(x: 1, y: -1)
            context.textPosition = CGPoint(x: later.baseline.x, y: -later.baseline.y)
            for run in CTLineGetGlyphRuns(later.text) as! [CTRun] {
                CTRunDraw(
                    run,
                    context,
                    .init(location: 0, length: 0)
                )
            }
        })
        let reference = try render(value, draw: { context in
            for (index, line) in value.lines.enumerated() {
                context.saveGState()
                context.setFillColor(index == 0 ? UIColor.red.cgColor : UIColor.green.cgColor)
                context.textMatrix = .identity
                context.scaleBy(x: 1, y: -1)
                context.textPosition = CGPoint(x: line.baseline.x, y: -line.baseline.y)
                for run in CTLineGetGlyphRuns(line.text) as! [CTRun] {
                    CTRunDraw(
                        run,
                        context,
                        .init(location: 0, length: 0)
                    )
                }
                context.restoreGState()
            }
        })
        let pressed = try render(value, pressed: 0)
        var overlapInk = 0
        for y in max(0, Int(ceil(firstRect.minY))) ..< min(240, Int(floor(firstRect.maxY))) {
            for x in Int(ceil(firstRect.minX)) ..< Int(floor(firstRect.maxX)) where green(laterOnly.color(x, y)) {
                overlapInk += 1
                XCTAssertEqual(
                    pressed.color(x, y),
                    reference.color(x, y),
                    "unrelated later-line ink must retain its own color at \(x),\(y)"
                )
            }
        }
        XCTAssertGreaterThan(overlapInk, 20)
    }

    func testSameHalfAlphaColorAcrossFractionalLigatureBoundaryHasNoSeam() throws {
        let color = UIColor.red.withAlphaComponent(0.5)
        for pressedColor in [color, UIColor.blue.withAlphaComponent(0.5)] {
            let value = try layout(document("fi", attributes: [.foregroundColor: color, .kern: 0.35], actions: [
                .init(actionID: "f", range: NSRange(location: 0, length: 1), pressedStyle: .init(
                    foregroundColor: pressedColor, backgroundColor: nil
                ))
            ]))
            XCTAssertEqual(CTLineGetGlyphCount(value.lines[0].text), 1)
            let rect = try XCTUnwrap(value.actionIndex[0].rects.first)
            XCTAssertNotEqual(rect.maxX, rect.maxX.rounded())
            let normal = try render(value), pressed = try render(value, pressed: 0)
            if pressedColor == color, normal.bytes != pressed.bytes {
                let differences = normal.bytes.indices.filter { normal.bytes[$0] != pressed.bytes[$0] }
                print(
                    "fractional split diff count=\(differences.count), first=\(differences.prefix(12).map { [Int($0), Int(normal.bytes[$0]), Int(pressed.bytes[$0])] })"
                )
            }
            if pressedColor == color {
                XCTAssertTrue(
                    normal.bytes == pressed.bytes,
                    "mutually exclusive clips must neither double alpha nor expose a seam"
                )
            } else {
                XCTAssertFalse(normal.bytes == pressed.bytes)
                // red 与 blue 的共同零通道 green 直接观测实际 glyph alpha，非整数交界的覆盖率必须完整保留。
                let ordinaryAlpha = stride(from: 1, to: normal.bytes.count, by: 4).map { normal.bytes[$0] }
                let pressedAlpha = stride(from: 1, to: pressed.bytes.count, by: 4).map { pressed.bytes[$0] }
                XCTAssertTrue(
                    ordinaryAlpha == pressedAlpha,
                    "different RGB with equal alpha must preserve every mask pixel"
                )
            }
        }
    }

    func testEveryUnderlineBasePatternAndByWordUsesOriginalPhaseAndInheritedColor() throws {
        let bases: [NSUnderlineStyle] = [.single, .thick, .double]
        let patterns: [NSUnderlineStyle] = [[], .patternDot, .patternDash, .patternDashDot, .patternDashDotDot]
        for base in bases {
            for pattern in patterns {
                for byWord in [false, true] {
                    let style = base.union(pattern).union(byWord ? .byWord : [])
                    let value = try layout(document(
                        "AA AA AA",
                        attributes: [.underlineStyle: style.rawValue],
                        actions: [
                            .init(actionID: "middle", range: NSRange(location: 3, length: 2), pressedStyle: .init(
                                foregroundColor: .red, backgroundColor: nil
                            ))
                        ]
                    ))
                    let groups = try XCTUnwrap(value.preparedDecorations?.allGroups)
                    XCTAssertFalse(groups.isEmpty)
                    let first = try XCTUnwrap(groups.first)
                    let actionRect = try XCTUnwrap(value.actionIndex[0].rects.first)
                    let band = try CGRect(
                        x: actionRect.minX,
                        y: first.stroke.center - 6,
                        width: XCTUnwrap(value.actionIndex[0].rects.last?.maxX) - actionRect.minX,
                        height: 13
                    )
                    let normal = try render(value), pressed = try render(value, pressed: 0)
                    XCTAssertGreaterThan(pressed.count(in: band, matching: red), 0, "style=\(style.rawValue)")
                    let reference = try render(value, draw: { context in
                        for group in groups {
                            group.draw(in: context, scale: 2, color: UIColor.red.cgColor)
                        }
                    })
                    for y in Int(ceil(band.minY)) ..< Int(floor(band.maxY)) {
                        for x in Int(ceil(band.minX + 1)) ..< Int(floor(band.maxX - 1)) {
                            if red(reference.color(x, y)) { XCTAssertTrue(
                                red(pressed.color(x, y)),
                                "phase reset for \(style.rawValue)"
                            ) }
                        }
                    }
                    XCTAssertTrue(try normal.bytes == render(value).bytes)
                }
            }
        }
    }

    func testExplicitUnderlineAndStrikeStayOrdinaryWhileInheritedMembersFollowForeground() throws {
        let text = NSMutableAttributedString(string: "AA AA", attributes: [
            .font: font, .foregroundColor: UIColor.green, .underlineStyle: 2, .strikethroughStyle: 2
        ])
        text.addAttributes(
            [.underlineColor: UIColor.green, .strikethroughColor: UIColor.green],
            range: NSRange(location: 0, length: 2)
        )
        let value = try layout(LYGlyphTextDocument(attributedText: text, actions: [
            .init(
                actionID: "all",
                range: NSRange(location: 0, length: 5),
                pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
            )
        ]))
        let pressed = try render(value, pressed: 0)
        for group in try XCTUnwrap(value.preparedDecorations?.allGroups) {
            let members = group.members
            for member in members where member.member.piece.rect.width > 4 {
                let rect = CGRect(
                    x: member.interval.lowerBound + 2,
                    y: member.center - 2,
                    width: member.interval.upperBound - member.interval.lowerBound - 4,
                    height: 4
                )
                XCTAssertGreaterThan(pressed.count(in: rect, matching: member.colorIsInherited ? red : green), 0)
            }
        }
    }

    func testImagesAndMountedViewPixelsAreIndependentOfPressedForeground() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 15, height: 30))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 15, y: 0, width: 15, height: 30))
        }
        let doc = try LYGlyphTextDocument(
            attributedText: NSAttributedString(
                string: "A\u{FFFC}\u{FFFC}",
                attributes: [.font: font, .foregroundColor: UIColor.green]
            ),
            attachments: [1: .init(id: "image", image: image, size: CGSize(width: 30, height: 30))],
            viewAttachments: [2: .init(id: "view", viewID: "badge", size: CGSize(width: 30, height: 30))],
            actions: [.init(
                actionID: "all",
                range: NSRange(location: 0, length: 3),
                pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
            )]
        )
        let value = layout(doc)
        let view = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 30, height: 30)))
        view.backgroundColor = .magenta
        let placement = try XCTUnwrap(value.viewAttachments.first)
        func pixels(pressed: Int?) throws -> Pixels {
            try render(value, draw: { context in
                value.draw(in: context, pressedActionIndex: pressed)
                context.saveGState()
                context.translateBy(x: placement.rect.minX, y: placement.rect.minY)
                view.layer.render(in: context)
                context.restoreGState()
            })
        }
        let normal = try pixels(pressed: nil), pressed = try pixels(pressed: 0)
        for rect in value.attachments.map(\.rect) + value.viewAttachments.map(\.rect) {
            for y in Int(ceil(rect.minY + 1)) ..< Int(floor(rect.maxY - 1)) {
                for x in Int(ceil(rect.minX + 1)) ..< Int(floor(rect.maxX - 1)) {
                    XCTAssertEqual(normal.color(x, y), pressed.color(x, y))
                }
            }
        }
        let imageRect = try XCTUnwrap(value.attachments.first?.rect)
        XCTAssertGreaterThan(pressed.count(in: imageRect) { $0[2] > 200 && $0[0] < 20 }, 50)
        XCTAssertGreaterThan(pressed.count(in: placement.rect) { $0[0] > 200 && $0[2] > 200 && $0[1] < 20 }, 50)
    }

    func testDrawsOnlyConsumePreparedPlansWithAndWithoutDecorations() throws {
        for decorated in [false, true] {
            let source = String(repeating: "AA ", count: 40)
            let actions = (0 ..< 40).map { index in
                LYGlyphTextAction(
                    actionID: "same",
                    range: NSRange(location: index * 3, length: 2),
                    pressedStyle: .init(foregroundColor: .red)
                )
            }
            var work: [TextDecorations.PreparationEvent: Int] = [:]
            let value = try layout(
                document(
                    source,
                    attributes: decorated ? [.underlineStyle: 2, .backgroundColor: UIColor.blue] : [:],
                    actions: actions
                ),
                observe: { work[$0, default: 0] += 1 }
            )
            XCTAssertEqual(work[.sourceSnapshot], 1)
            XCTAssertEqual(work[.drawingPlan], 1)
            XCTAssertLessThan(work[.selectionPreparation, default: 0], 500)
            let before = work, identities = value.lines.map { Unmanaged.passUnretained($0.text).toOpaque() }
            let beforeSignature = try signature(value)
            for ordinal in [nil, 0, 1, 5, nil, 0, nil] as [Int?] {
                _ = try render(value, pressed: ordinal, observe: { work[$0, default: 0] += 1 })
            }
            for event in [
                TextDecorations.PreparationEvent.sourceSnapshot,
                .drawingPlan,
                .selectionPreparation,
                .geometryQuery,
                .visiblePiece,
                .styleComparison,
                .groupComparison,
                .paintMemberQuery,
                .paintRegion
            ] {
                XCTAssertEqual(work[event, default: 0], before[event, default: 0], "draw performed \(event)")
            }
            XCTAssertEqual(work[.drawCachedContent], 7)
            XCTAssertEqual(identities, value.lines.map { Unmanaged.passUnretained($0.text).toOpaque() })
            XCTAssertEqual(beforeSignature, try signature(value))
            XCTAssertEqual(value.preparedDrawing.actions.count, 40)
        }
    }

    func testOutsideGlyphClipHasNoFixedCoordinateUniverse() throws {
        let action = LYGlyphTextAction(
            actionID: "f",
            range: NSRange(location: 0, length: 1),
            pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
        )
        let ordinary = try layout(document("fi", actions: [action]))
        let offset: CGFloat = 1_500_000_000
        let value = LYGlyphTextLayout(size: ordinary.size, lines: ordinary.lines.map {
            .init(
                text: $0.text,
                baseline: CGPoint(x: $0.baseline.x + offset, y: $0.baseline.y),
                visibleSourceRanges: $0.visibleSourceRanges,
                sourceOffset: $0.sourceOffset,
                truncationTokenRange: $0.truncationTokenRange
            )
        }, source: "fi", actions: [action])
        let pixels = try render(value, draw: { context in
            context.translateBy(x: -offset, y: 0)
            value.draw(in: context, pressedActionIndex: 0)
        })
        let first = try XCTUnwrap(ordinary.actionIndex[0].rects.first)
        let second = try XCTUnwrap(ordinary.sourceGeometry?.cells.last?.pieces.first?.rect)
        XCTAssertGreaterThan(pixels.count(in: first, matching: red), 10)
        XCTAssertGreaterThan(pixels.count(in: second, matching: green), 10)
    }

    func testFractionalClipRasterizationProbe() throws {
        let value = try layout(document("A"))
        let boundary: CGFloat = 22.35
        let all = CGRect(x: 10, y: 10, width: 40, height: 40)
        let selected = CGRect(x: 10, y: 10, width: boundary - 10, height: 40)
        let remainder = CGRect(x: boundary, y: 10, width: 50 - boundary, height: 40)
        let reference = try render(value, draw: { context in
            context.setFillColor(UIColor.red.withAlphaComponent(0.5).cgColor)
            context.fill(all)
        })
        for mode in ["path", "rect", "aliased", "plusLighter"] {
            let pixels = try render(value, draw: { context in
                if mode == "plusLighter" { context.beginTransparencyLayer(auxiliaryInfo: nil)
                    context.setBlendMode(.plusLighter)
                }
                for rect in [selected, remainder] {
                    context.saveGState()
                    if mode == "aliased" { context.setShouldAntialias(false) }
                    if mode == "rect" { context.clip(to: rect) }
                    else { context.addRect(rect)
                        context.clip()
                    }
                    if mode == "aliased" { context.setShouldAntialias(true) }
                    context.setFillColor(UIColor.red.withAlphaComponent(0.5).cgColor)
                    context.fill(all)
                    context.restoreGState()
                }
                if mode == "plusLighter" { context.endTransparencyLayer() }
            })
            let differences = pixels.bytes.indices.filter { pixels.bytes[$0] != reference.bytes[$0] }
            print(
                "clip raster probe \(mode): differing channels=\(differences.count), boundary pixel=\(pixels.color(22, 20)), reference=\(reference.color(22, 20))"
            )
            if mode == "plusLighter" { XCTAssertTrue(pixels.bytes == reference.bytes) }
            else { XCTAssertFalse(
                pixels.bytes == reference.bytes,
                "diagnostic probe must reproduce the edge-composition defect"
            ) }
        }
    }

    func testFractionalBackgroundAndStrokeBoundariesPreserveEqualAlphaMask() throws {
        for kind in ["background", "underline", "strike"] {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.blue.withAlphaComponent(0.5), .kern: 0.35, .baselineOffset: 0.35
            ]
            if kind == "background" { attributes[.backgroundColor] = UIColor.blue.withAlphaComponent(0.5) }
            if kind == "underline" { attributes[.underlineStyle] = NSUnderlineStyle.double.rawValue }
            if kind == "strike" { attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue }
            let value = try layout(document("fi", attributes: attributes, actions: [
                .init(actionID: "f", range: NSRange(location: 0, length: 1), pressedStyle: .init(
                    foregroundColor: UIColor.red.withAlphaComponent(0.5),
                    backgroundColor: kind == "background" ? UIColor.red.withAlphaComponent(0.5) : nil
                ))
            ]))
            XCTAssertEqual(CTLineGetGlyphCount(value.lines[0].text), 1)
            func pixels(_ pressed: Int?) throws -> Pixels {
                try render(value, draw: { context in
                    if kind == "background" { value.preparedDrawing.drawBackgrounds(in: context, pressed: pressed) }
                    else { value.preparedDrawing.drawStrokes(in: context, pressed: pressed) }
                })
            }
            let ordinary = try pixels(nil), pressed = try pixels(0)
            let differences = stride(from: 1, to: ordinary.bytes.count, by: 4)
                .map { abs(Int(ordinary.bytes[$0]) - Int(pressed.bytes[$0])) }
            print(
                "fractional \(kind): max mask difference=\(differences.max() ?? 0), differing pixels=\(differences.count(where: { $0 != 0 }))"
            )
            XCTAssertLessThanOrEqual(
                differences.max() ?? 0,
                1,
                "source-disjoint \(kind) boundaries must not lose alpha"
            )
            XCTAssertFalse(ordinary.bytes == pressed.bytes)
        }
    }

    func testRegionClipIsAppliedAfterSourceStackProbe() throws {
        let value = try layout(document("A"))
        let all = CGRect(x: 10, y: 10, width: 40, height: 40)
        let source = [UIColor.red.withAlphaComponent(0.5), UIColor.blue.withAlphaComponent(0.5)]
        let reference = try render(value, draw: { context in
            for color in source {
                context.setFillColor(color.cgColor)
                context.fill(all)
            }
        })
        for resetsClip in [false, true] {
            let pixels = try render(value, draw: { context in
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.setBlendMode(.plusLighter)
                for rect in [
                    CGRect(x: 10, y: 10, width: 12.35, height: 40),
                    CGRect(x: 22.35, y: 10, width: 27.65, height: 40)
                ] {
                    context.saveGState()
                    context.clip(to: rect)
                    context.beginTransparencyLayer(auxiliaryInfo: nil)
                    if resetsClip { context.resetClip() }
                    for color in source {
                        context.setFillColor(color.cgColor)
                        context.fill(all)
                    }
                    context.endTransparencyLayer()
                    context.restoreGState()
                }
                context.endTransparencyLayer()
            })
            let maxDifference = pixels.bytes.indices.map { abs(Int(pixels.bytes[$0]) - Int(reference.bytes[$0])) }
                .max() ?? 0
            XCTAssertLessThanOrEqual(maxDifference, 1, "region coverage must apply after the complete source stack")
        }
    }

    func testRealOverlapElsewhereDoesNotDamageRemoteFractionalBoundaryInSamePaintGroup() throws {
        let source = String(repeating: "\u{FFFC}", count: 4)
        let rects = [
            CGRect(x: 20, y: 14, width: 45, height: 55),
            CGRect(x: 20, y: 14, width: 45, height: 55),
            CGRect(x: 100, y: 14, width: 22.35, height: 55),
            CGRect(x: 122.35, y: 14, width: 30, height: 55)
        ]
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.clear])
        for (index, rect) in rects.enumerated() {
            let metrics = AttachmentMetrics(
                size: rect.size,
                ascender: font.ascender,
                descender: font.descender,
                alignment: .bottom
            )
            text.addAttribute(
                .init(kCTRunDelegateAttributeName as String),
                value: metrics.makeDelegate(),
                range: NSRange(location: index, length: 1)
            )
        }
        for kind in ["background", "stroke"] {
            let color = UIColor.blue.withAlphaComponent(0.5).cgColor
            let decorations = TextDecorations(source: source, styles: (0 ..< 4).map { index in
                .init(
                    range: NSRange(location: index, length: 1),
                    background: kind == "background" ? color : nil,
                    underlineStyle: 0,
                    underlineColor: color,
                    strikethroughStyle: kind == "stroke" ? 2 : 0,
                    strikethroughColor: color,
                    strikethroughColorIsInherited: index == 1 || index == 2
                )
            }, scale: 2)
            let value = LYGlyphTextLayout(size: canvas, lines: [
                .init(
                    text: CTLineCreateWithAttributedString(text),
                    baseline: CGPoint(x: 20, y: 58),
                    visibleSourceRanges: [NSRange(location: 0, length: 4)],
                    sourceOffset: 0,
                    truncationTokenRange: nil
                )
            ], viewAttachments: rects.enumerated().map {
                .init(
                    attachment: .init(id: "v\($0.offset)", viewID: "badge", size: $0.element.size),
                    sourceLocation: $0.offset,
                    rect: $0.element
                )
            }, decorations: decorations, actions: [
                .init(actionID: "middle", range: NSRange(location: 1, length: 2), pressedStyle: .init(
                    foregroundColor: UIColor.red.withAlphaComponent(0.5),
                    backgroundColor: UIColor.red.withAlphaComponent(0.5)
                ))
            ])
            if kind == "stroke" { XCTAssertEqual(value.preparedDecorations?.allGroups.count, 1) }
            func pixels(_ pressed: Int?) throws -> Pixels {
                try render(value, draw: { context in
                    if kind == "background" { value.preparedDrawing.drawBackgrounds(in: context, pressed: pressed) }
                    else { value.preparedDrawing.drawStrokes(in: context, pressed: pressed) }
                })
            }
            let normal = try pixels(nil), pressed = try pixels(0)
            let band = CGRect(x: 118, y: 12, width: 10, height: 60)
            var maximum = 0
            for y in Int(band.minY) ..< Int(band.maxY) {
                for x in Int(band.minX) ..< Int(band.maxX) {
                    maximum = max(maximum, abs(Int(normal.color(x, y)[1]) - Int(pressed.color(x, y)[1])))
                }
            }
            XCTAssertLessThanOrEqual(
                maximum,
                1,
                "\(kind) remote edge must retain alpha despite a real overlap elsewhere"
            )
            let overlapColors = (12 ..< 72).map { pressed.color(40, $0) }
            let overlap = try XCTUnwrap(overlapColors.min { $0[1] < $1[1] })
            XCTAssertEqual(Int(overlap[0]), 192, accuracy: 3)
            XCTAssertEqual(Int(overlap[1]), 64, accuracy: 3)
            XCTAssertEqual(Int(overlap[2]), 128, accuracy: 3)
        }
    }

    func testIndependentActionsPrepareOnlyLocalPaintRegions() throws {
        for count in [40, 160] {
            let source = String(repeating: "A ", count: count)
            let actions = (0 ..< count).map { index in
                LYGlyphTextAction(actionID: "same", range: NSRange(location: index * 2, length: 1), pressedStyle: .init(
                    foregroundColor: .red, backgroundColor: .yellow
                ))
            }
            var work: [TextDecorations.PreparationEvent: Int] = [:]
            let value = try layout(document(source, attributes: [
                .underlineStyle: NSUnderlineStyle.double.rawValue, .backgroundColor: UIColor.blue
            ], actions: actions), width: CGFloat(count) * 100, observe: { work[$0, default: 0] += 1 })
            XCTAssertEqual(value.lines.count, 1)
            // 两棵共享树每动作仅访问 O(log n) 路径和相邻 stroke 成员；不做 A × 全文字分区。
            XCTAssertLessThan(work[.paintMemberQuery, default: 0], count * 80)
            XCTAssertLessThan(work[.paintRegion, default: 0], count * 20)
            XCTAssertGreaterThan(work[.paintRegion, default: 0], count)
            let before = work
            _ = try render(value, pressed: 0, observe: { work[$0, default: 0] += 1 })
            _ = try render(value, pressed: count - 1, observe: { work[$0, default: 0] += 1 })
            XCTAssertEqual(work[.paintMemberQuery], before[.paintMemberQuery])
            XCTAssertEqual(work[.paintRegion], before[.paintRegion])
        }
    }

    func testBackgroundPatchDoesNotConsumeNeighboringSourceGroups() throws {
        let rect = CGRect(x: 20.25, y: 14, width: 45.5, height: 55)
        let source = String(repeating: "\u{FFFC}", count: 3)
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.clear])
        for index in 0 ..< 3 {
            let metrics = AttachmentMetrics(
                size: rect.size,
                ascender: font.ascender,
                descender: font.descender,
                alignment: .bottom
            )
            text.addAttribute(
                .init(kCTRunDelegateAttributeName as String),
                value: metrics.makeDelegate(),
                range: NSRange(location: index, length: 1)
            )
        }
        let colors = [UIColor.blue, .green, .yellow].map { $0.withAlphaComponent(0.5).cgColor }
        let decorations = TextDecorations(source: source, styles: (0 ..< 3).map { index in
            .init(
                range: NSRange(location: index, length: 1),
                background: colors[index],
                underlineStyle: 0,
                underlineColor: colors[index],
                strikethroughStyle: 0,
                strikethroughColor: colors[index]
            )
        }, scale: 2)
        let selectedColor = UIColor.red.withAlphaComponent(0.5).cgColor
        let value = LYGlyphTextLayout(size: canvas, lines: [
            .init(
                text: CTLineCreateWithAttributedString(text),
                baseline: CGPoint(x: 20.25, y: 58),
                visibleSourceRanges: [NSRange(location: 0, length: 3)],
                sourceOffset: 0,
                truncationTokenRange: nil
            )
        ], viewAttachments: (0 ..< 3).map {
            .init(attachment: .init(id: "v\($0)", viewID: "badge", size: rect.size), sourceLocation: $0, rect: rect)
        }, decorations: decorations, actions: [
            .init(
                actionID: "middle",
                range: NSRange(location: 1, length: 1),
                pressedStyle: .init(backgroundColor: UIColor(cgColor: selectedColor))
            )
        ])
        let actual = try render(value, draw: { value.preparedDrawing.drawBackgrounds(in: $0, pressed: 0) })
        let reference = try render(value, draw: { context in
            for color in [colors[0], selectedColor, colors[2]] {
                context.setFillColor(color)
                context.fill(rect)
            }
        })
        XCTAssertEqual(actual.color(40, 40), reference.color(40, 40))
    }

    func testOneActionRecolorsEveryLineWithoutFillingInterlineSpaceAndRestores() throws {
        let source = "MMMM\nMMMM"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 24
        let value = try layout(document(source, attributes: [.paragraphStyle: paragraph], actions: [
            .init(actionID: "multiline", range: NSRange(location: 0, length: source.utf16.count), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: .blue
            ))
        ]))
        XCTAssertEqual(value.lines.count, 2)
        let action = try XCTUnwrap(value.actionIndex.first)
        let geometry = try XCTUnwrap(value.sourceGeometry)
        let normal = try render(value), pressed = try render(value, pressed: 0), restored = try render(value)
        let lineRects = (0 ..< 2).map { index in
            geometry.cells.filter { $0.lineIndex == index }.flatMap { $0.pieces.map(\.rect) }
                .reduce(CGRect.null) { $0.union($1) }
        }
        for rect in lineRects {
            XCTAssertTrue(action.rects.contains { $0.intersects(rect) })
            XCTAssertGreaterThan(pressed.count(in: rect, matching: red), 100)
            XCTAssertGreaterThan(pressed.count(in: rect) { $0[0] < 5 && $0[1] < 5 && $0[2] > 250 }, 100)
            XCTAssertGreaterThan(normal.count(in: rect, matching: green), 100)
        }
        let gap = CGRect(
            x: lineRects[0].minX,
            y: lineRects[0].maxY + 1,
            width: min(lineRects[0].width, lineRects[1].width),
            height: lineRects[1].minY - lineRects[0].maxY - 2
        )
        XCTAssertGreaterThan(gap.height, 10, "fixture must contain real interline space")
        XCTAssertEqual(pressed.count(in: gap) { $0 != [255, 255, 255] }, 0)
        XCTAssertEqual(normal.bytes, restored.bytes)
        XCTAssertNotEqual(normal.bytes, pressed.bytes)
    }

    func testNilPressedBackgroundPreservesAdjacentDifferentOrdinaryColors() throws {
        let text = NSMutableAttributedString(string: "MM", attributes: [.font: font, .foregroundColor: UIColor.green])
        text.addAttribute(
            .backgroundColor,
            value: UIColor.blue.withAlphaComponent(0.5),
            range: NSRange(location: 0, length: 1)
        )
        text.addAttribute(
            .backgroundColor,
            value: UIColor.magenta.withAlphaComponent(0.5),
            range: NSRange(location: 1, length: 1)
        )
        let value = try layout(LYGlyphTextDocument(attributedText: text, actions: [
            .init(actionID: "two-colors", range: NSRange(location: 0, length: 2), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: nil
            ))
        ]))
        let normal = try render(value, draw: { value.preparedDrawing.drawBackgrounds(in: $0, pressed: nil) })
        let pressed = try render(value, draw: { value.preparedDrawing.drawBackgrounds(in: $0, pressed: 0) })
        let cells = try XCTUnwrap(value.sourceGeometry).cells
        XCTAssertEqual(cells.count, 2)
        let first = try XCTUnwrap(cells[0].pieces.first).rect
        let second = try XCTUnwrap(cells[1].pieces.first).rect
        for (rect, expected) in [(first, [128, 128, 255]), (second, [255, 128, 255])] {
            for (actual, reference) in zip(normal.color(Int(rect.midX), Int(rect.midY)), expected) {
                XCTAssertEqual(Int(actual), reference, accuracy: 1, "8-bit alpha quantization")
            }
        }
        XCTAssertEqual(normal.bytes, pressed.bytes, "nil must inherit each source background independently")
        XCTAssertGreaterThan(try render(value, pressed: 0).count(in: first.union(second), matching: red), 100)
    }

    func testGeneratedTokenInkInsideAnActionRectKeepsItsOwnOrdinaryColor() throws {
        let source = "MMMMM\nMMMMMMMMMMMM"
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 12
        paragraph.maximumLineHeight = 12
        let value = try layout(document(source, attributes: [.paragraphStyle: paragraph], actions: [
            .init(actionID: "first-line", range: NSRange(location: 0, length: 5), pressedStyle: .init(
                foregroundColor: .red, backgroundColor: nil
            ))
        ]), width: 240, lines: 2)
        let line = try XCTUnwrap(value.lines.last)
        let token = try XCTUnwrap(line.truncationTokenRange)
        let tokenRuns = (CTLineGetGlyphRuns(line.text) as! [CTRun]).filter { run in
            let range = CTRunGetStringRange(run)
            return NSIntersectionRange(NSRange(location: range.location, length: range.length), token).length > 0
        }
        XCTAssertFalse(tokenRuns.isEmpty)
        for run in tokenRuns {
            let range = CTRunGetStringRange(run)
            XCTAssertEqual(
                NSRange(location: range.location, length: range.length),
                token,
                "token-only pixel reference must exclude every original-source glyph"
            )
        }
        let tokenOnly = try render(value, draw: { context in
            context.setFillColor(UIColor.green.cgColor)
            context.textMatrix = .identity
            context.scaleBy(x: 1, y: -1)
            context.textPosition = CGPoint(x: line.baseline.x, y: -line.baseline.y)
            for run in tokenRuns {
                CTRunDraw(run, context, .init(location: 0, length: 0))
            }
        })
        let normal = try render(value), pressed = try render(value, pressed: 0)
        let rects = try XCTUnwrap(value.actionIndex.first).rects
        var provenTokenInkInsideAction = 0
        for y in 0 ..< Int(canvas.height) {
            for x in 0 ..< Int(canvas.width) where rects.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
                let ink = tokenOnly.color(x, y)
                if ink[0] < 5, ink[1] > 250, ink[2] < 5 {
                    provenTokenInkInsideAction += 1
                    XCTAssertEqual(pressed.color(x, y), normal.color(x, y))
                    XCTAssertTrue(green(pressed.color(x, y)))
                }
            }
        }
        XCTAssertGreaterThan(
            provenTokenInkInsideAction,
            5,
            "actual generated-token ink must enter the action rectangle"
        )
        XCTAssertGreaterThan(rects.reduce(0) { $0 + pressed.count(in: $1, matching: red) }, 100)
        XCTAssertNotEqual(normal.bytes, pressed.bytes)
    }

    func testOneLongByWordActionDoesNotRescanOrRedrawEveryIntervalPerRegion() throws {
        var smaller: [TextDecorations.PreparationEvent: Int]?
        for count in [40, 160] {
            let source = String(repeating: "A ", count: count)
            var work: [TextDecorations.PreparationEvent: Int] = [:]
            let value = try ResolvedText(document: document(source, attributes: [
                .underlineStyle: NSUnderlineStyle.single.union(.byWord).rawValue
            ], actions: [
                .init(actionID: "whole", range: NSRange(location: 0, length: source.utf16.count), pressedStyle: .init(
                    foregroundColor: .red, backgroundColor: nil
                ))
            ]), traits: .init(userInterfaceStyle: .light)).layout(
                width: nil, insets: .zero, scale: 2, observe: { work[$0, default: 0] += 1 }
            )
            XCTAssertEqual(value.lines.count, 1, "also exercise intrinsic ideal-width layout")
            let groups = try XCTUnwrap(value.preparedDecorations?.allGroups)
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups[0].mergedIntervals.count, count)
            _ = try render(value, draw: { context in
                value.preparedDrawing.drawStrokes(in: context, pressed: 0, observe: { work[$0, default: 0] += 1 })
            })
            print(
                "long byWord action \(count): barrier=\(work[.barrierMemberVisit, default: 0]), active=\(work[.activeRectCheck, default: 0]), actual strokes=\(work[.strokeIntervalDraw, default: 0])"
            )
            XCTAssertLessThan(work[.barrierMemberVisit, default: 0], count * 8)
            XCTAssertLessThan(work[.activeRectCheck, default: 0], count * 20)
            XCTAssertLessThanOrEqual(work[.strokeIntervalDraw, default: 0], count * 4)
            if let smaller {
                for event in [
                    TextDecorations.PreparationEvent.barrierMemberVisit,
                    .activeRectCheck,
                    .strokeIntervalDraw
                ] {
                    XCTAssertLessThanOrEqual(
                        work[event, default: 0],
                        max(1, smaller[event, default: 0]) * 6,
                        "\(event) grows quadratically"
                    )
                }
            }
            smaller = work
        }
    }

    func testFiveThousandCharactersWithoutActionsUseRunDrawingAndNoPressedRecords() throws {
        var work: [TextDecorations.PreparationEvent: Int] = [:]
        let value = try ResolvedText(
            document: document(String(repeating: "A", count: 5000)),
            traits: .init(userInterfaceStyle: .light)
        ).layout(
            width: nil, insets: .zero, scale: 2, observe: { work[$0, default: 0] += 1 }
        )
        XCTAssertEqual(value.lines.count, 1)
        XCTAssertEqual(CTLineGetGlyphCount(value.lines[0].text), 5000)
        XCTAssertEqual((CTLineGetGlyphRuns(value.lines[0].text) as? [CTRun])?.count, 1)
        XCTAssertEqual(work[.glyphPaintRecord, default: 0], 0)
        XCTAssertEqual(work[.glyphImageBoundsQuery, default: 0], 0)
        for pressed in [nil, 0, nil] as [Int?] {
            var calls = 0
            _ = try render(value, draw: { context in
                value.preparedDrawing.drawGlyphs(
                    in: context,
                    pressed: pressed,
                    observe: { if $0 == .glyphDrawCall { calls += 1 } }
                )
            })
            print(
                "5000 no action: pressed=\(String(describing: pressed)) records=\(work[.glyphPaintRecord, default: 0]) bounds=\(work[.glyphImageBoundsQuery, default: 0]) draw=\(calls)"
            )
            XCTAssertEqual(calls, 1)
        }
    }

    func testFiveThousandCharactersWithOneActionBatchUnrelatedGlyphsInSameAndOtherRuns() throws {
        for multipleRuns in [false, true] {
            let source = String(repeating: "A", count: 5000)
            let text = NSMutableAttributedString(
                string: source,
                attributes: [.font: font, .foregroundColor: UIColor.green]
            )
            if multipleRuns { text.addAttribute(
                .foregroundColor,
                value: UIColor.blue,
                range: NSRange(location: 2500, length: 2500)
            ) }
            let doc = try LYGlyphTextDocument(attributedText: text, actions: [
                .init(
                    actionID: "one",
                    range: NSRange(location: 1, length: 1),
                    pressedStyle: .init(foregroundColor: .red, backgroundColor: nil)
                )
            ])
            var work: [TextDecorations.PreparationEvent: Int] = [:]
            let value = ResolvedText(document: doc, traits: .init(userInterfaceStyle: .light)).layout(
                width: nil, insets: .zero, scale: 2, observe: { work[$0, default: 0] += 1 }
            )
            let count = value.lines.reduce(0) { $0 + (CTLineGetGlyphRuns($1.text) as! [CTRun]).count }
            XCTAssertEqual(value.lines.count, 1)
            XCTAssertEqual(count, multipleRuns ? 2 : 1)
            XCTAssertEqual(work[.glyphPaintRecord, default: 0], 1)
            XCTAssertEqual(work[.glyphImageBoundsQuery, default: 0], 1)
            let identity = Unmanaged.passUnretained(value.lines[0].text).toOpaque()
            for pressed in [nil, 0, nil] as [Int?] {
                var calls = 0
                _ = try render(value, draw: { context in
                    value.preparedDrawing.drawGlyphs(
                        in: context,
                        pressed: pressed,
                        observe: { if $0 == .glyphDrawCall { calls += 1 } }
                    )
                })
                print(
                    "5000 one action: runs=\(count) pressed=\(String(describing: pressed)) records=\(work[.glyphPaintRecord, default: 0]) bounds=\(work[.glyphImageBoundsQuery, default: 0]) draw=\(calls)"
                )
                XCTAssertEqual(calls, pressed == nil ? count : count + 2)
                XCTAssertEqual(Unmanaged.passUnretained(value.lines[0].text).toOpaque(), identity)
            }
        }
    }
}
