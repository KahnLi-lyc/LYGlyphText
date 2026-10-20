import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class DecorationDrawingTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 40, weight: .regular)
    private let canvasSize = CGSize(width: 420, height: 220)

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func color(_ x: Int, _ y: Int) -> [UInt8] {
            guard x >= 0, y >= 0, x < width, y < height else { return [] }
            let offset = (y * width + x) * 4
            return Array(bytes[offset ..< offset + 3])
        }

        func red(_ x: Int, _ y: Int) -> Bool {
            let c = color(x, y)
            return c.count == 3 && c[0] > 180 && c[1] < 110 && c[2] < 110
        }

        func redCount(in rect: CGRect) -> Int {
            let left = max(0, Int(floor(rect.minX)))
            let right = min(width, Int(ceil(rect.maxX)))
            let top = max(0, Int(floor(rect.minY)))
            let bottom = min(height, Int(ceil(rect.maxY)))
            guard left < right, top < bottom else { return 0 }
            return (top ..< bottom).reduce(0) { total, y in
                total + (left ..< right).count(where: { red($0, y) })
            }
        }
    }

    private func render(_ draw: (CGContext) -> Void) throws -> Pixels {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: canvasSize))
            draw(renderer.cgContext)
        }
        // 显式转换为已知 RGBA 格式，不假设 renderer 的 BGRA／ARGB 字节顺序。
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(origin: .zero, size: canvasSize))
        }
        return Pixels(bytes: bytes, width: width, height: height)
    }

    private func document(_ string: String, _ attributes: [NSAttributedString.Key: Any]) throws -> LYGlyphTextDocument {
        var attributes = attributes
        attributes[.font] = attributes[.font] ?? font
        attributes[.foregroundColor] = attributes[.foregroundColor] ?? UIColor.green
        return try LYGlyphTextDocument(attributedText: NSAttributedString(string: string, attributes: attributes))
    }

    private func layout(
        _ document: LYGlyphTextDocument,
        width: CGFloat = 400,
        lines: Int = 0,
        traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .light)
    )
        -> LYGlyphTextLayout
    {
        ResolvedText(document: document, traits: traits).layout(
            width: width, insets: UIEdgeInsets(top: 12, left: 12, bottom: 8, right: 8), scale: 2,
            numberOfLines: lines
        )
    }

    func testBackgroundActuallyDrawsAndHalfAlphaIsAppliedOnce() throws {
        for alpha in [CGFloat(1), 0.5] {
            let doc = try document("   ", [.backgroundColor: UIColor.red.withAlphaComponent(alpha)])
            let value = layout(doc)
            let pixels = try render { value.draw(in: $0) }
            let rect = try XCTUnwrap(value.visibleTextFragments(in: NSRange(location: 0, length: 3), source: doc.string)
                .first).rect
            let color = pixels.color(Int(rect.midX), Int(rect.midY))
            XCTAssertEqual(color[0], 255, accuracy: 3)
            XCTAssertEqual(Int(color[1]), alpha == 1 ? 0 : 128, accuracy: 4)
            XCTAssertEqual(Int(color[2]), alpha == 1 ? 0 : 128, accuracy: 4)
        }
    }

    func testStrikethroughActuallyDrawsAtXHeight() throws {
        let doc = try document("    ", [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: UIColor.red
        ])
        let value = layout(doc)
        let pixels = try render { value.draw(in: $0) }
        let piece = try XCTUnwrap(value.visibleTextFragments(in: NSRange(location: 0, length: 4), source: doc.string)
            .first?.runs.first)
        let y = piece.baseline.y - CTFontGetXHeight(piece.font) / 2
        XCTAssertGreaterThan(pixels.redCount(in: CGRect(x: piece.rect.minX + 2, y: y - 2, width: 15, height: 4)), 8)
    }

    func testNativeCoreTextUnderlineProbeRetainsActualByWordBehavior() throws {
        let text = NSAttributedString(string: "AA AA", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): UIColor.green.cgColor,
            NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): NSUnderlineStyle.single.union(.byWord)
                .rawValue,
            NSAttributedString.Key(kCTUnderlineColorAttributeName as String): UIColor.red.cgColor
        ])
        let line = CTLineCreateWithAttributedString(text)
        let baseline = CGPoint(x: 20, y: 65)
        let pixels = try render { context in
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.textPosition = CGPoint(x: baseline.x, y: -baseline.y)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        func count(_ index: Int) -> Int {
            let x1 = CTLineGetOffsetForStringIndex(line, index, nil)
            let x2 = CTLineGetOffsetForStringIndex(line, index + 1, nil)
            return pixels.redCount(in: CGRect(
                x: baseline.x + (x1 + x2) / 2 - 2,
                y: baseline.y + 1,
                width: 4,
                height: 12
            ))
        }
        let counts = [count(0), count(2), count(4)]
        print(
            "B4b current-runtime diagnostic \(UIDevice.current.systemVersion), native byWord red pixel counts word/space/word: \(counts)"
        )
        XCTAssertGreaterThan(counts[0], 0)
        XCTAssertGreaterThan(counts[2], 0)
        // 当前 Core Text 忽略 byWord，空白中心也被画线；这是实际像素诊断，不是支持声明。
        XCTAssertGreaterThan(counts[1], 0)
    }

    func testNativeCoreTextUnderlineBasesPatternsAndExplicitColor() throws {
        var masks: [[Bool]] = []
        var rowsByBase: [[Int]] = []
        for style in [1, 2, 9, 0x101, 0x201, 0x301, 0x401] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "AAAAAAAAAAAAAA", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): UIColor.green.cgColor,
                NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): style,
                NSAttributedString.Key(kCTUnderlineColorAttributeName as String): UIColor.red.cgColor
            ]))
            let pixels = try render { context in
                context.saveGState()
                context.scaleBy(x: 1, y: -1)
                context.textPosition = CGPoint(x: 20, y: -65)
                CTLineDraw(line, context)
                context.restoreGState()
            }
            let rows = (65 ..< 85).filter { y in
                pixels.redCount(in: CGRect(x: 25, y: y, width: 300, height: 1)) > 5
            }
            let mask = (25 ..< 325).map { x in (65 ..< 85).contains { pixels.red(x, $0) } }
            print(
                "B4b native underline style=\(style) rows=\(rows) paintedColumns=\(mask.count(where: { $0 })) transitions=\(zip(mask, mask.dropFirst()).count(where: { $0 != $1 }))"
            )
            var spans: [Int] = []
            var last = mask.first ?? false
            for bit in mask {
                if bit == last, !spans.isEmpty { spans[spans.count - 1] += 1 }
                else { spans.append(1)
                    last = bit
                }
            }
            print(
                "B4b native underline spans=\(spans.prefix(14)), font unit=\(CTFontGetUnderlineThickness(font as CTFont))"
            )
            XCTAssertFalse(rows.isEmpty, "style=\(style)")
            if style < 10 { rowsByBase.append(rows) } else { masks.append(mask) }
        }
        XCTAssertGreaterThan(rowsByBase[1].count, rowsByBase[0].count)
        XCTAssertGreaterThan(rowsByBase[2].count, rowsByBase[0].count)
        XCTAssertTrue(zip(rowsByBase[2], rowsByBase[2].dropFirst()).contains { $1 - $0 > 1 })
        for mask in masks {
            XCTAssertTrue(mask.contains(true))
            XCTAssertTrue(mask.contains(false))
            XCTAssertGreaterThan(zip(mask, mask.dropFirst()).count(where: { $0 != $1 }), 4)
        }
        XCTAssertEqual(Set(masks.map { $0.map { $0 ? "1" : "0" }.joined() }).count, 4)
    }

    private func pieces(_ value: LYGlyphTextLayout, _ doc: LYGlyphTextDocument) -> [VisibleTextFragment.RunPiece] {
        value.visibleTextFragments(in: NSRange(location: 0, length: doc.string.utf16.count), source: doc.string)
            .flatMap(\.runs)
    }

    private func redMask(_ pixels: Pixels, x: Range<Int>, y: Range<Int>) -> [Bool] {
        x.map { horizontal in y.contains { pixels.red(horizontal, $0) } }
    }

    private func spans(_ mask: [Bool]) -> [Int] {
        var result: [Int] = []
        var previous = mask.first ?? false
        for bit in mask {
            if bit == previous, !result.isEmpty { result[result.count - 1] += 1 }
            else { result.append(1)
                previous = bit
            }
        }
        return result
    }

    func testUnderlinePatternsUseFontThicknessUnitsInsteadOfNativePatternLengths() throws {
        let doc = try document("AAAAAAAAAAAA", [
            .underlineStyle: NSUnderlineStyle.single.union(.patternDash).rawValue, .underlineColor: UIColor.red
        ])
        let value = layout(doc)
        let piece = try XCTUnwrap(pieces(value, doc).first)
        let pixels = try render { value.draw(in: $0) }
        let y = Int(piece.baseline.y - CTFontGetUnderlinePosition(piece.font))
        let mask = redMask(pixels, x: Int(piece.rect.minX) ..< Int(piece.rect.minX + 100), y: y - 2 ..< y + 3)
        let lengths = spans(mask)
        // 40pt 固定字体 unit≈1.95pt，dash 的内部周期应约 8pt+4pt；原生实测为20pt+10pt。
        XCTAssertGreaterThan(lengths.count, 10)
        XCTAssertTrue(lengths.dropFirst().dropLast().allSatisfy { (3 ... 9).contains($0) }, "lengths=\(lengths)")
    }

    func testByWordUnderlineAndStrikeSkipCompleteWhitespaceClustersInLTRAndRTL() throws {
        for source in ["AA AA", "אב אב", "AA\tAA", "AA\u{00A0}AA"] {
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle] {
                let colorKey: NSAttributedString.Key = key == .underlineStyle ? .underlineColor : .strikethroughColor
                let doc = try document(
                    source,
                    [key: NSUnderlineStyle.single.union(.byWord).rawValue, colorKey: UIColor.red]
                )
                let value = layout(doc)
                let pixels = try render { value.draw(in: $0) }
                var words = 0
                var spaces = 0
                for piece in pieces(value, doc) {
                    let whitespace = (source as NSString).substring(with: piece.sourceRange).unicodeScalars.allSatisfy {
                        CharacterSet.whitespacesAndNewlines.contains($0)
                    }
                    let y = key == .underlineStyle
                        ? piece.baseline.y - CTFontGetUnderlinePosition(piece.font)
                        : piece.baseline.y - CTFontGetXHeight(piece.font) / 2
                    let count = pixels.redCount(in: CGRect(x: piece.rect.midX - 2, y: y - 2, width: 4, height: 4))
                    if whitespace { XCTAssertEqual(count, 0, source)
                        spaces += 1
                    } else { XCTAssertGreaterThan(count, 0, source)
                        words += 1
                    }
                }
                XCTAssertEqual(spaces, 1, source)
                XCTAssertEqual(words, 4, source)
            }
        }
    }

    func testStrikeSingleThickDoublePixelsAndInheritedForeground() throws {
        var rowSets: [[Int]] = []
        for base in [1, 2, 9] {
            let doc = try document("       ", [.strikethroughStyle: base, .foregroundColor: UIColor.red])
            let value = layout(doc)
            let piece = try XCTUnwrap(pieces(value, doc).first)
            let pixels = try render { value.draw(in: $0) }
            let y = Int(piece.baseline.y - CTFontGetXHeight(piece.font) / 2)
            let rows = (y - 8 ..< y + 9).filter {
                pixels.redCount(in: CGRect(x: piece.rect.minX + 4, y: CGFloat($0), width: 100, height: 1)) > 80
            }
            XCTAssertFalse(rows.isEmpty)
            rowSets.append(rows)
            XCTAssertEqual(pixels.redCount(in: CGRect(x: 0, y: y + 12, width: 300, height: 5)), 0)
        }
        XCTAssertGreaterThan(rowSets[1].count, rowSets[0].count)
        XCTAssertGreaterThan(rowSets[2].count, rowSets[0].count)
        XCTAssertTrue(zip(rowSets[2], rowSets[2].dropFirst()).contains { $1 - $0 > 1 })
    }

    func testEveryManualPatternHasExpectedCoverageAndContinuousPhaseAcrossStyleRuns() throws {
        for pattern in [0, 0x100, 0x200, 0x300, 0x400] {
            let string = "            "
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor.green, .strikethroughStyle: pattern | 1,
                .strikethroughColor: UIColor.red
            ]
            if pattern != 0 {
                attrs[.underlineStyle] = pattern | 1
                attrs[.underlineColor] = UIColor.red
            }
            let normal = try LYGlyphTextDocument(attributedText: NSAttributedString(string: string, attributes: attrs))
            let split = NSMutableAttributedString(string: string, attributes: attrs)
            // 只改变无墨迹空格的前景色，制造真实 source style 边界；删除线仍相同。
            split.addAttribute(.foregroundColor, value: UIColor.blue, range: NSRange(location: 3, length: 4))
            let splitDoc = try LYGlyphTextDocument(attributedText: split)
            let value = layout(normal)
            let actual = try render { value.draw(in: $0) }
            let splitPixels = try render { layout(splitDoc).draw(in: $0) }
            XCTAssertTrue(actual.bytes == splitPixels.bytes, "pattern=\(pattern)")
            let piece = try XCTUnwrap(pieces(value, normal).first)
            let y = Int(piece.baseline.y - CTFontGetXHeight(piece.font) / 2)
            let mask = redMask(actual, x: 20 ..< 260, y: y - 3 ..< y + 4)
            let coverage = Double(mask.count(where: { $0 })) / Double(mask.count)
            if pattern == 0 { XCTAssertGreaterThan(coverage, 0.98) }
            else {
                XCTAssertGreaterThan(coverage, 0.25)
                XCTAssertLessThan(coverage, 0.8)
                XCTAssertGreaterThan(spans(mask).count, 15)
            }
        }
    }

    func testModifierOnlyStylesDrawNoLine() throws {
        let doc = try document("AA AA", [
            .underlineStyle: NSUnderlineStyle.byWord.union(.patternDash).rawValue,
            .strikethroughStyle: NSUnderlineStyle.byWord.union(.patternDot).rawValue,
            .underlineColor: UIColor.red, .strikethroughColor: UIColor.red
        ])
        let value = layout(doc)
        let pixels = try render { value.draw(in: $0) }
        XCTAssertEqual(pixels.redCount(in: CGRect(origin: .zero, size: canvasSize)), 0)
    }

    func testBackgroundUsesRunExtentsAndNeverFillsParagraphSpacing() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 30
        paragraph.paragraphSpacing = 22
        let doc = try document(" \n ", [.backgroundColor: UIColor.red, .paragraphStyle: paragraph])
        let value = layout(doc)
        let all = pieces(value, doc).sorted { $0.rect.minY < $1.rect.minY }
        XCTAssertEqual(all.count, 2)
        let pixels = try render { value.draw(in: $0) }
        for piece in all {
            XCTAssertTrue(pixels.red(Int(piece.rect.midX), Int(piece.rect.midY)))
        }
        let gap = CGRect(
            x: all[0].rect.minX + 2,
            y: all[0].rect.maxY + 2,
            width: 10,
            height: all[1].rect.minY - all[0].rect.maxY - 4
        )
        XCTAssertGreaterThan(gap.height, 20)
        XCTAssertEqual(pixels.redCount(in: gap), 0)
    }

    func testBackgroundBidiSelectionLeavesVisualGapEmpty() throws {
        let source = "abc אבג def"
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.green])
        text.addAttribute(.backgroundColor, value: UIColor.red, range: NSRange(location: 0, length: 5))
        let doc = try LYGlyphTextDocument(attributedText: text)
        let value = layout(doc)
        let fragments = value.visibleTextFragments(in: NSRange(location: 0, length: 5), source: source)
            .sorted { $0.rect.minX < $1.rect.minX }
        XCTAssertEqual(fragments.count, 2)
        let pixels = try render { value.draw(in: $0) }
        let gap = CGRect(
            x: fragments[0].rect.maxX + 2,
            y: fragments[0].rect.minY + 2,
            width: fragments[1].rect.minX - fragments[0].rect.maxX - 4,
            height: 5
        )
        XCTAssertGreaterThan(gap.width, 2)
        XCTAssertEqual(pixels.redCount(in: gap), 0)
    }

    func testMixedFontsPositiveNegativeBaselinesPositionEachStrike() throws {
        let text = NSMutableAttributedString(string: "  ", attributes: [
            .font: font, .foregroundColor: UIColor.green, .strikethroughStyle: 1, .strikethroughColor: UIColor.red
        ])
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 24), .baselineOffset: 9],
            range: NSRange(location: 0, length: 1)
        )
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 48), .baselineOffset: -7],
            range: NSRange(location: 1, length: 1)
        )
        let doc = try LYGlyphTextDocument(attributedText: text)
        let value = layout(doc)
        let pixels = try render { value.draw(in: $0) }
        let all = pieces(value, doc)
        XCTAssertEqual(all.count, 2)
        XCTAssertNotEqual(all[0].baseline.y, all[1].baseline.y)
        for piece in all {
            let y = piece.baseline.y - CTFontGetXHeight(piece.font) / 2
            XCTAssertGreaterThan(pixels.redCount(in: CGRect(x: piece.rect.midX - 2, y: y - 2, width: 4, height: 4)), 3)
            XCTAssertEqual(pixels.redCount(in: CGRect(x: piece.rect.midX - 2, y: y + 5, width: 4, height: 4)), 0)
        }
    }

    func testOverlappingCompleteClusterBackgroundPiecesBlendOnlyOnce() throws {
        let text = NSMutableAttributedString(string: "x\u{301}", attributes: [
            .font: font, .foregroundColor: UIColor.green, .backgroundColor: UIColor.red.withAlphaComponent(0.5)
        ])
        text.addAttribute(.foregroundColor, value: UIColor.blue, range: NSRange(location: 1, length: 1))
        let doc = try LYGlyphTextDocument(attributedText: text)
        let value = layout(doc)
        let all = pieces(value, doc)
        XCTAssertGreaterThan(all.count, 1)
        let pixels = try render { value.draw(in: $0) }
        let rect = try XCTUnwrap(all.first).rect
        let color = pixels.color(Int(rect.midX), Int(rect.maxY - 3))
        XCTAssertEqual(Int(color[1]), 128, accuracy: 4)
        XCTAssertEqual(Int(color[2]), 128, accuracy: 4)
        let runs = try XCTUnwrap(try CTLineGetGlyphRuns(XCTUnwrap(value.lines.first).text) as? [CTRun])
        XCTAssertTrue(runs
            .allSatisfy { (CTRunGetAttributes($0) as NSDictionary)[kCTBackgroundColorAttributeName] == nil })
    }

    func testTruncationExcludesHiddenDecorationsAndGeneratedTokenButKeepsRealEllipsis() throws {
        let source = "… AA AA AA AA AA AA AA AA AA"
        let doc = try document(source, [
            .backgroundColor: UIColor.red,
            .strikethroughStyle: 1,
            .strikethroughColor: UIColor.red,
            .underlineStyle: NSUnderlineStyle.single.union(.byWord).rawValue,
            .underlineColor: UIColor.red
        ])
        let value = layout(doc, width: 170, lines: 1)
        let line = try XCTUnwrap(value.lines.first)
        let token = try XCTUnwrap(line.truncationTokenRange)
        XCTAssertTrue(value.visibleTextFragments(
            in: NSRange(location: source.utf16.count - 2, length: 2),
            source: source
        ).isEmpty)
        let real = try XCTUnwrap(value.visibleTextFragments(in: NSRange(location: 0, length: 1), source: source).first)
        let x1 = line.baseline.x + CTLineGetOffsetForStringIndex(line.text, token.location, nil)
        let x2 = line.baseline.x + CTLineGetOffsetForStringIndex(line.text, NSMaxRange(token), nil)
        let pixels = try render { value.draw(in: $0) }
        XCTAssertGreaterThan(
            pixels.redCount(in: CGRect(x: real.rect.minX + 2, y: real.rect.minY + 2, width: 5, height: 4)),
            0
        )
        XCTAssertEqual(pixels.redCount(in: CGRect(x: min(x1, x2) + 1, y: 0, width: abs(x2 - x1) - 2, height: 100)), 0)
        // 独立隐藏样式不能染到未加装饰的可见前缀或生成 token。
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.green])
        text.addAttributes(
            [.backgroundColor: UIColor.red, .strikethroughStyle: 1, .strikethroughColor: UIColor.red],
            range: NSRange(location: source.utf16.count - 5, length: 5)
        )
        let hidden = try layout(LYGlyphTextDocument(attributedText: text), width: 170, lines: 1)
        XCTAssertEqual(try render { hidden.draw(in: $0) }.redCount(in: CGRect(origin: .zero, size: canvasSize)), 0)
    }

    func testSemanticColorsResolvePerDisplayForSameDocumentIncludingInheritedLines() throws {
        let semantic = UIColor { $0.userInterfaceStyle == .dark ? .blue : .red }
        for attributes: [NSAttributedString.Key: Any] in [
            [.foregroundColor: semantic], [.backgroundColor: semantic],
            [.underlineStyle: 1, .underlineColor: semantic],
            [.strikethroughStyle: 1, .strikethroughColor: semantic],
            [.underlineStyle: NSUnderlineStyle.single.union(.byWord).rawValue, .foregroundColor: semantic],
            [.strikethroughStyle: 1, .foregroundColor: semantic]
        ] {
            let doc = try document("AA AA", attributes)
            let light = try render { layout(doc, traits: UITraitCollection(userInterfaceStyle: .light)).draw(in: $0) }
            let dark = try render { layout(doc, traits: UITraitCollection(userInterfaceStyle: .dark)).draw(in: $0) }
            XCTAssertGreaterThan(light.redCount(in: CGRect(origin: .zero, size: canvasSize)), 20)
            XCTAssertEqual(dark.redCount(in: CGRect(origin: .zero, size: canvasSize)), 0)
            XCTAssertNotEqual(light.bytes, dark.bytes)
        }
        let pressed = LYGlyphTextPressedStyle(foregroundColor: semantic, backgroundColor: semantic)
        XCTAssertEqual(
            pressed.foregroundColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            .blue
        )
        XCTAssertEqual(
            pressed.backgroundColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            .red
        )
    }

    func testDecorationMetadataAndActionsPreserveOriginalLigatureShapingAndMapping() throws {
        let string = "office fi"
        let plain = try NSMutableAttributedString(string: string, attributes: [
            .font: XCTUnwrap(UIFont(name: "Baskerville", size: 40)), .foregroundColor: UIColor.green, .ligature: 1
        ])
        let before = try layout(LYGlyphTextDocument(attributedText: plain))
        plain.addAttributes([
            .backgroundColor: UIColor.red,
            .strikethroughStyle: 1,
            .strikethroughColor: UIColor.blue
        ], range: NSRange(location: 2, length: 1))
        let afterDoc = try LYGlyphTextDocument(attributedText: plain, actions: [
            .init(actionID: "ligature", range: NSRange(location: 2, length: 1))
        ])
        let after = layout(afterDoc)
        func signature(_ value: LYGlyphTextLayout) -> [String] {
            value.lines.flatMap { line in
                (CTLineGetGlyphRuns(line.text) as! [CTRun]).flatMap { run -> [String] in
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                    return (0 ..< count).map { "\(glyphs[$0]):\(positions[$0]):\(indices[$0])" }
                }
            }
        }
        XCTAssertEqual(signature(before), signature(after))
        XCTAssertLessThan(signature(after).count, string.utf16.count)
        XCTAssertEqual(before.lines.map(\.visibleSourceRanges), after.lines.map(\.visibleSourceRanges))
        XCTAssertFalse(after.visibleTextFragments(in: NSRange(location: 2, length: 1), source: string).isEmpty)
    }

    func testAllPatternSegmentsMatchSpecifiedUnitsInStrikeAndFallbackUnderline() throws {
        let patterns: [(Int, [CGFloat])] = [
            (0x100, [1, 2]), (0x200, [4, 2]), (0x300, [4, 2, 1, 2]), (0x400, [4, 2, 1, 2, 1, 2])
        ]
        for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle] {
            let colorKey: NSAttributedString.Key = key == .underlineStyle ? .underlineColor : .strikethroughColor
            for (pattern, lengths) in patterns {
                let doc = try document("            ", [key: pattern | 1, colorKey: UIColor.red])
                let value = layout(doc)
                let all = pieces(value, doc)
                let piece = try XCTUnwrap(all.first)
                let pixels = try render { value.draw(in: $0) }
                let y = key == .underlineStyle
                    ? piece.baseline.y - CTFontGetUnderlinePosition(piece.font)
                    : piece.baseline.y - CTFontGetXHeight(piece.font) / 2
                let unit = CTFontGetUnderlineThickness(piece.font)
                var cursor = all.map(\.rect.minX).min() ?? 0
                for _ in 0 ..< 3 {
                    for (index, length) in lengths.enumerated() {
                        let x = Int(cursor + length * unit / 2)
                        let painted = pixels.redCount(in: CGRect(x: CGFloat(x), y: y - 2, width: 1, height: 4)) > 0
                        XCTAssertEqual(
                            painted,
                            index.isMultiple(of: 2),
                            "key=\(key), pattern=\(pattern), segment=\(index), x=\(x)"
                        )
                        cursor += length * unit
                    }
                }
            }
        }
    }

    func testFallbackUnderlineThickDoubleAndInheritedColor() throws {
        var counts: [Int] = []
        for base in [1, 2, 9] {
            let doc = try document("AAAA", [
                .foregroundColor: UIColor.red, .underlineStyle: base | NSUnderlineStyle.byWord.rawValue
            ])
            let value = layout(doc)
            let piece = try XCTUnwrap(pieces(value, doc).first)
            let pixels = try render { value.draw(in: $0) }
            let y = Int(piece.baseline.y - CTFontGetUnderlinePosition(piece.font))
            let rows = (y - 8 ..< y + 9).filter { pixels.red(Int(piece.rect.midX), $0) }
            counts.append(rows.count)
            if base == 9 { XCTAssertTrue(zip(rows, rows.dropFirst()).contains { $1 - $0 > 1 }) }
        }
        XCTAssertGreaterThan(counts[1], counts[0])
        XCTAssertGreaterThan(counts[2], counts[0])
    }

    func testAttachmentBackgroundUsesExactPlacementAndImageDrawsAboveLines() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 15, y: 0, width: 30, height: 60))
        }
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "\u{FFFC}", attributes: [
            .font: font, .backgroundColor: UIColor.red, .strikethroughStyle: 2, .strikethroughColor: UIColor.red
        ]), attachments: [0: .init(id: "image", image: image, size: CGSize(width: 60, height: 60))])
        let value = layout(doc)
        let rect = try XCTUnwrap(value.attachments.first).rect
        let piece = try XCTUnwrap(pieces(value, doc).first)
        let pixels = try render { value.draw(in: $0) }
        XCTAssertTrue(pixels.red(Int(rect.minX + 3), Int(rect.minY + 3)))
        XCTAssertEqual(pixels.color(Int(rect.minX - 2), Int(rect.minY + 3)), [255, 255, 255])
        let y = Int(piece.baseline.y - CTFontGetXHeight(piece.font) / 2)
        XCTAssertTrue(rect.contains(CGPoint(x: rect.midX, y: CGFloat(y))))
        XCTAssertEqual(pixels.color(Int(rect.midX), y), [0, 0, 255])
    }

    func testViewPlacementBackgroundDrawsBeforeMountedUIView() throws {
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "\u{FFFC}", attributes: [
            .font: font, .backgroundColor: UIColor.red, .strikethroughStyle: 2, .strikethroughColor: UIColor.red
        ]), viewAttachments: [0: .init(id: "view", viewID: "blue", size: CGSize(width: 60, height: 60))])
        let value = layout(doc)
        let rect = try XCTUnwrap(value.viewAttachments.first).rect
        let background = try render { value.draw(in: $0) }
        XCTAssertTrue(background.red(Int(rect.midX), Int(rect.midY)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: canvasSize))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let label = LYGlyphTextLabel(frame: CGRect(origin: .zero, size: canvasSize))
        label.configuration.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 8, right: 8)
        label.document = doc
        var creations = 0
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            creations += 1
            let view = UIView()
            view.backgroundColor = .blue
            return view
        }
        XCTAssertEqual(creations, 0)
        controller.view.addSubview(label)
        label.layoutIfNeeded()
        XCTAssertEqual(creations, 1)
        let pixels = try render { label.layer.render(in: $0) }
        XCTAssertEqual(pixels.color(Int(rect.midX), Int(rect.midY)), [0, 0, 255])
    }

    func testDecorationsRespectInsetsCompressedHeightAndNonzeroBoundsOrigin() throws {
        let doc = try document("AAAA\nAAAA", [
            .backgroundColor: UIColor.red, .strikethroughStyle: 2, .strikethroughColor: UIColor.red,
            .underlineStyle: NSUnderlineStyle.single.union(.byWord).rawValue, .underlineColor: UIColor.red
        ])
        let host = UIView(frame: CGRect(origin: .zero, size: canvasSize))
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        host.addSubview(label)
        label.document = doc
        label.configuration.textContainerInset = UIEdgeInsets(top: 6, left: 9, bottom: 8, right: 10)
        let normal = try render { host.layer.render(in: $0) }
        label.bounds.origin = CGPoint(x: 17, y: 23)
        label.setNeedsDisplay()
        let shifted = try render { host.layer.render(in: $0) }
        XCTAssertEqual(normal.bytes, shifted.bytes)
        XCTAssertGreaterThan(shifted.redCount(in: CGRect(x: 9, y: 6, width: 81, height: 36)), 100)
        for outside in [
            CGRect(x: 0, y: 0, width: 9, height: 100),
            CGRect(x: 90, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 6),
            CGRect(x: 0, y: 42, width: 100, height: 100)
        ] {
            XCTAssertEqual(shifted.redCount(in: outside), 0)
        }
    }

    func testBackgroundDoesNotCoverOriginalGlyphInk() throws {
        let doc = try document("AAAA", [.backgroundColor: UIColor.red, .foregroundColor: UIColor.blue])
        let value = layout(doc)
        let pixels = try render { value.draw(in: $0) }
        let rect = try XCTUnwrap(pieces(value, doc).first).rect
        var blue = 0
        for y in Int(rect.minY) ..< Int(rect.maxY) {
            for x in Int(rect.minX) ..< Int(rect.maxX) where pixels.color(x, y) == [0, 0, 255] {
                blue += 1
            }
        }
        XCTAssertGreaterThan(blue, 20)
        XCTAssertGreaterThan(pixels.redCount(in: rect), 100)
    }

    func testSmallFontStrokeHonorsOneDisplayPixelMinimum() throws {
        let doc = try document("                                        ", [
            .font: UIFont.monospacedSystemFont(ofSize: 4, weight: .regular),
            .strikethroughStyle: 1, .strikethroughColor: UIColor.red
        ])
        for scale: CGFloat in [1, 2, 3] {
            let value = ResolvedText(document: doc, traits: .init()).layout(
                width: 400, insets: UIEdgeInsets(top: 12, left: 12, bottom: 8, right: 8), scale: scale
            )
            let piece = try XCTUnwrap(pieces(value, doc).first)
            let pixels = try render { value.draw(in: $0) }
            let x = Int(piece.rect.midX)
            let ink = (0 ..< 40).reduce(0.0) { total, y in
                let color = pixels.color(x, y)
                return total + max(0, Double(color[0]) - Double(color[1])) / 255
            }
            XCTAssertEqual(ink, Double(1 / scale), accuracy: 0.12, "scale=\(scale)")
        }
    }

    func testMixedFontBackgroundUsesEachShiftedRunInsteadOfLineHeight() throws {
        let text = NSMutableAttributedString(string: "  ", attributes: [
            .font: font, .foregroundColor: UIColor.green, .backgroundColor: UIColor.red
        ])
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 24), .baselineOffset: 9],
            range: NSRange(location: 0, length: 1)
        )
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 48), .baselineOffset: -7],
            range: NSRange(location: 1, length: 1)
        )
        let doc = try LYGlyphTextDocument(attributedText: text)
        let value = layout(doc)
        let pixels = try render { value.draw(in: $0) }
        for piece in pieces(value, doc) {
            let x = Int(piece.rect.midX)
            XCTAssertTrue(pixels.red(x, Int(piece.rect.minY + 2)))
            XCTAssertTrue(pixels.red(x, Int(piece.rect.maxY - 3)))
            XCTAssertEqual(pixels.color(x, Int(piece.rect.minY - 2)), [255, 255, 255])
            XCTAssertEqual(pixels.color(x, Int(piece.rect.maxY + 2)), [255, 255, 255])
        }
    }

    func testSecondTruncatedLineUsesSourceOffsetAndExcludesTokenDecorations() throws {
        let source = "AA AA AA AA AA AA AA AA AA AA AA\n"
        let doc = try document(source, [
            .backgroundColor: UIColor.red, .underlineStyle: NSUnderlineStyle.single.union(.byWord).rawValue,
            .underlineColor: UIColor.red, .strikethroughStyle: NSUnderlineStyle.single.union(.patternDash).rawValue,
            .strikethroughColor: UIColor.red
        ])
        let value = layout(doc, width: 155, lines: 2)
        XCTAssertEqual(value.lines.count, 2)
        let last = try XCTUnwrap(value.lines.last)
        XCTAssertGreaterThan(last.sourceOffset, 0)
        let token = try XCTUnwrap(last.truncationTokenRange)
        let pixels = try render { value.draw(in: $0) }
        let all = value.visibleTextFragments(in: NSRange(location: 0, length: source.utf16.count), source: source)
        XCTAssertEqual(Set(all.map(\.lineIndex)), [0, 1])
        for fragment in all {
            XCTAssertTrue(pixels.red(Int(fragment.rect.minX + 2), Int(fragment.rect.minY + 2)))
        }
        let x1 = last.baseline.x + CTLineGetOffsetForStringIndex(last.text, token.location, nil)
        let x2 = last.baseline.x + CTLineGetOffsetForStringIndex(last.text, NSMaxRange(token), nil)
        XCTAssertEqual(pixels.redCount(in: CGRect(
            x: min(x1, x2) + 2,
            // 只采样本行内部；相邻行背景边缘可能占据同一个抗锯齿像素。
            y: ceil(last.baseline.y - font.ascender) + 1,
            width: abs(x2 - x1) - 4,
            height: font.lineHeight - 2
        )), 0)
    }

    func testDifferentBackgroundColorsKeepSourceOrderForOverlappingCompleteClusterPieces() throws {
        let text = NSMutableAttributedString(string: "x\u{301}\u{302}", attributes: [
            .font: font, .foregroundColor: UIColor.clear, .backgroundColor: UIColor.red.withAlphaComponent(0.5)
        ])
        text.addAttributes(
            [.font: UIFont.systemFont(ofSize: 42), .backgroundColor: UIColor.blue.withAlphaComponent(0.5)],
            range: NSRange(location: 1, length: 1)
        )
        text.addAttribute(.font, value: UIFont.systemFont(ofSize: 44), range: NSRange(location: 2, length: 1))
        let doc = try LYGlyphTextDocument(attributedText: text)
        XCTAssertEqual(doc.styleRuns.count, 3)
        let value = layout(doc)
        let all = pieces(value, doc)
        XCTAssertGreaterThan(all.count, 1)
        let rect = try XCTUnwrap(all.first { $0.rect.width > 4 }).rect
        let actual = try render { value.draw(in: $0) }
        let color = actual.color(Int(rect.midX), Int(rect.midY))
        // 白底依次合成半透明 red / blue / red，不把两个 red 跨过 blue 重排。
        XCTAssertEqual(Int(color[0]), 192, accuracy: 4)
        XCTAssertEqual(Int(color[1]), 32, accuracy: 4)
        XCTAssertEqual(Int(color[2]), 96, accuracy: 4)
    }

    func testTranslucentFallbackUnderlineMovesWithBothBaselineOffsetsAndCompositesOnlyOnce() throws {
        let decorated = NSRange(location: 2, length: 5)
        for style in [NSUnderlineStyle.single.union(.byWord), NSUnderlineStyle.single.union(.patternDash)] {
            func fixture(shift: CGFloat, alpha: CGFloat = 0.5) throws -> LYGlyphTextDocument {
                let text = NSMutableAttributedString(string: "M AA AA", attributes: [
                    .font: font, .foregroundColor: UIColor.green
                ])
                // 大字体锚定同一行的度量，让 +/- offset 的实际绘制移动可与原位置直接比较。
                text.addAttribute(.font, value: UIFont.systemFont(ofSize: 100), range: NSRange(location: 0, length: 1))
                text.addAttributes([
                    .underlineStyle: style.rawValue, .underlineColor: UIColor.red.withAlphaComponent(alpha),
                    .baselineOffset: shift
                ], range: decorated)
                return try LYGlyphTextDocument(attributedText: text)
            }
            let originalDoc = try fixture(shift: 0)
            let original = layout(originalDoc)
            let originalPiece = try XCTUnwrap(pieces(original, originalDoc).first { $0.sourceRange.location == 2 })
            let originalY = originalPiece.baseline.y - CTFontGetUnderlinePosition(originalPiece.font)
            for shift: CGFloat in [-12, 12] {
                let doc = try fixture(shift: shift)
                let value = layout(doc)
                let piece = try XCTUnwrap(pieces(value, doc).first { $0.sourceRange.location == 2 })
                let line = try XCTUnwrap(value.lines.first)
                XCTAssertEqual(line.baseline.y, try XCTUnwrap(original.lines.first).baseline.y, accuracy: 0.01)
                XCTAssertEqual(piece.baseline.y, originalPiece.baseline.y - shift, accuracy: 0.01)
                let decoratedRuns = (CTLineGetGlyphRuns(line.text) as! [CTRun]).filter {
                    let range = CTRunGetStringRange($0)
                    return NSIntersectionRange(NSRange(location: range.location, length: range.length), decorated)
                        .length > 0
                }
                XCTAssertFalse(decoratedRuns.isEmpty)
                for run in decoratedRuns {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let nativeStyle = try XCTUnwrap(attributes[kCTUnderlineStyleAttributeName] as? NSNumber)
                    XCTAssertEqual(nativeStyle.intValue, 0, "fallback must suppress the native underline")
                }
                let pixels = try render { value.draw(in: $0) }
                let unit = CTFontGetUnderlineThickness(piece.font)
                // dash 第一段中央远离抗锯齿边缘；byWord 同样采样第一单词内部。
                let x = Int(piece.rect.minX + unit * 2)
                let y = piece.baseline.y - CTFontGetUnderlinePosition(piece.font)
                let sampleRows = Array(Int(floor(y)) - 2 ... Int(ceil(y)) + 2)
                let sampleY = try XCTUnwrap(sampleRows.min { pixels.color(x, $0)[1] < pixels.color(x, $1)[1] })
                let peak = pixels.color(x, sampleY)
                let opaqueDoc = try fixture(shift: shift, alpha: 1)
                let opaque = try render { layout(opaqueDoc).draw(in: $0) }
                let opaqueColor = opaque.color(x, sampleY)
                // 用同位置不透明像素提供实际栅格覆盖率，排除缩采样／抗锯齿带来的少量白色。
                // 50% red 一次合成应在白底和不透明结果的正中；重复合成会明显更接近不透明结果。
                XCTAssertLessThan(opaqueColor[1], 30)
                XCTAssertEqual(Int(peak[0]), 255, accuracy: 4)
                for channel in [1, 2] {
                    let onceBlended = (255 + Double(opaqueColor[channel])) / 2
                    XCTAssertEqual(
                        Double(peak[channel]),
                        onceBlended,
                        accuracy: 4,
                        "style=\(style.rawValue), shift=\(shift), opaque=\(opaqueColor)"
                    )
                }
                let oldColors = (Int(floor(originalY)) - 2 ... Int(ceil(originalY)) + 2).map { pixels.color(x, $0) }
                XCTAssertTrue(
                    oldColors.allSatisfy { $0[1] > 245 },
                    "old baseline position must contain no red underline"
                )
                print(
                    "B4b translucent underline style=\(style.rawValue), shift=\(shift), y=\(y), oldY=\(originalY), peakRGBA=\(peak)"
                )
            }
        }
    }

    private func preparationWork(
        _ doc: LYGlyphTextDocument,
        width: CGFloat = 400
    ) throws -> [TextDecorations.PreparationEvent: Int] {
        let decorations = TextDecorations(source: doc.string, styles: doc.styleRuns.map {
            .init(
                range: $0.range,
                background: $0.background?.cgColor,
                underlineStyle: $0.underlineStyle,
                underlineColor: ($0.underlineColor ?? $0.color ?? .label).cgColor,
                strikethroughStyle: $0.strikethroughStyle,
                strikethroughColor: ($0.strikethroughColor ?? $0.color ?? .label).cgColor
            )
        }, scale: 2)
        let value = layout(doc, width: width)
        var events: [TextDecorations.PreparationEvent: Int] = [:]
        _ = try render { context in
            let prepared = decorations.prepare(in: value) { events[$0, default: 0] += 1 }
            prepared.drawBackgrounds(in: context)
            prepared.drawLines(in: context)
        }
        return events
    }

    func testOverlappingCompleteClusterStrikeColorsPreserveSourceCompositingOrder() throws {
        let text = NSMutableAttributedString(string: "x\u{301}\u{302}", attributes: [
            .font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.clear, .strikethroughStyle: 1,
            .strikethroughColor: UIColor.red.withAlphaComponent(0.5)
        ])
        text.addAttribute(
            .strikethroughColor,
            value: UIColor.blue.withAlphaComponent(0.5),
            range: NSRange(location: 1, length: 1)
        )
        let doc = try LYGlyphTextDocument(attributedText: text)
        XCTAssertEqual(doc.styleRuns.count, 3)
        let value = layout(doc)
        let piece = try XCTUnwrap(pieces(value, doc).first { $0.rect.width > 4 })
        print(
            "B4b quality strike geometry \(pieces(value, doc).map { (CTFontCopyPostScriptName($0.font), $0.baseline, $0.rect) })"
        )
        let pixels = try render { value.draw(in: $0) }
        let center = piece.baseline.y - CTFontGetXHeight(piece.font) / 2
        let x = Int(piece.rect.midX)
        let color = try XCTUnwrap((Int(center) - 3 ... Int(center) + 4).map { pixels.color(x, $0) }
            .min { $0[1] < $1[1] })
        print("B4b quality strike red/blue/red RGBA=\(color)")
        XCTAssertEqual(Int(color[0]), 192, accuracy: 16)
        XCTAssertEqual(Int(color[1]), 32, accuracy: 16)
        XCTAssertEqual(Int(color[2]), 96, accuracy: 16)
    }

    func testDecorationPreparationQueriesGeometryOnceForManyVisibleAndHiddenStyles() throws {
        let count = 600
        let text = NSMutableAttributedString(string: String(repeating: "A", count: count), attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular), .strikethroughStyle: 1
        ])
        for index in 0 ..< count {
            text.addAttributes([
                .backgroundColor: index.isMultiple(of: 2) ? UIColor.red : .blue,
                .strikethroughColor: index.isMultiple(of: 2) ? UIColor.blue : .red
            ], range: NSRange(location: index, length: 1))
        }
        let doc = try LYGlyphTextDocument(attributedText: text)
        let visible = try preparationWork(doc, width: 4000)
        print("B4b quality alternating styles count=\(count), events=\(visible)")
        XCTAssertEqual(visible[.geometryQuery, default: 0], 1)
        XCTAssertEqual(visible[.visiblePiece, default: 0], count)
        XCTAssertLessThan(visible[.styleComparison, default: 0], count * 24)
        let hidden = try LYGlyphTextDocument(attributedText: text)
        let limited = ResolvedText(document: hidden, traits: .init()).layout(
            width: 100,
            insets: .zero,
            scale: 2,
            numberOfLines: 1
        )
        // 直接使用截断后的最终布局，避免测试 helper 自行建立未截断替代布局。
        let decorations = TextDecorations(source: hidden.string, styles: hidden.styleRuns.map {
            .init(
                range: $0.range,
                background: $0.background?.cgColor,
                underlineStyle: 0,
                underlineColor: UIColor.red.cgColor,
                strikethroughStyle: 1,
                strikethroughColor: ($0.strikethroughColor ?? .red).cgColor
            )
        }, scale: 2)
        var queries = 0
        _ = try render { context in
            let prepared = decorations.prepare(in: limited) { if $0 == .geometryQuery { queries += 1 } }
            prepared.drawBackgrounds(in: context)
            prepared.drawLines(in: context)
        }
        print("B4b quality hidden styles queries=\(queries)")
        XCTAssertLessThanOrEqual(queries, 1)
    }

    func testDecorationGroupingWorkGrowsWithGlyphsInsteadOfSquareOfLineCount() throws {
        let lineCount = 80
        let perLine = 10
        let doc = try document(
            Array(repeating: String(repeating: "A", count: perLine), count: lineCount).joined(separator: "\n"),
            [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .strikethroughStyle: 1, .strikethroughColor: UIColor.red
            ]
        )
        let work = try preparationWork(doc)
        print("B4b quality lineCount=\(lineCount), perLine=\(perLine), events=\(work)")
        XCTAssertLessThanOrEqual(work[.groupComparison, default: 0], lineCount * perLine * 4)
    }

    func testPlainTextPreparationDoesNotVisitGeometry() throws {
        let work = try preparationWork(document("ordinary plain text", [:]))
        XCTAssertEqual(work[.geometryQuery, default: 0], 0)
        XCTAssertEqual(work[.groupComparison, default: 0], 0)
    }

    func testOverlappingFinalAttachmentGeometryAcrossClustersKeepsLaterStrokeAboveEarlierColor() throws {
        let source = "\u{FFFC}\u{FFFC}\u{FFFC}"
        let rects = [
            CGRect(x: 12, y: 12, width: 5, height: 48),
            CGRect(x: 17, y: 12, width: 10, height: 48),
            CGRect(x: 17, y: 12, width: 10, height: 48)
        ]
        let text = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor.clear])
        let colors = [UIColor.red, .blue, .red].map { $0.withAlphaComponent(0.5).cgColor }
        for (index, rect) in rects.enumerated() {
            let metrics = AttachmentMetrics(
                size: rect.size,
                ascender: font.ascender,
                descender: font.descender,
                alignment: .bottom
            )
            text.addAttribute(
                NSAttributedString.Key(kCTRunDelegateAttributeName as String),
                value: metrics.makeDelegate(),
                range: NSRange(location: index, length: 1)
            )
        }
        let decorations = TextDecorations(source: source, styles: colors.enumerated().map { index, color in
            .init(
                range: NSRange(location: index, length: 1),
                background: nil,
                underlineStyle: 0,
                underlineColor: color,
                strikethroughStyle: 1,
                strikethroughColor: color
            )
        }, scale: 2)
        // 明确构造已有最终 placement 的重叠几何；不声称 Core Text 的负 kern 生成过这些位置。
        let value = LYGlyphTextLayout(size: canvasSize, lines: [
            .init(
                text: CTLineCreateWithAttributedString(text),
                baseline: CGPoint(x: 12, y: 50),
                visibleSourceRanges: [NSRange(location: 0, length: 3)],
                sourceOffset: 0,
                truncationTokenRange: nil
            )
        ], viewAttachments: rects.enumerated().map { index, rect in
            .init(
                attachment: .init(id: "overlap-\(index)", viewID: "badge", size: rect.size),
                sourceLocation: index,
                rect: rect
            )
        }, decorations: decorations)
        let all = value.visibleTextFragments(in: NSRange(location: 0, length: 3), source: source).flatMap(\.runs)
        let middle = try XCTUnwrap(all.first { $0.sourceRange.location == 1 })
        let last = try XCTUnwrap(all.first { $0.sourceRange.location == 2 })
        XCTAssertNotEqual(middle.sourceRange, last.sourceRange)
        XCTAssertEqual(middle.rect, last.rect)
        let pixels = try render { value.draw(in: $0) }
        let y = last.baseline.y - CTFontGetXHeight(last.font) / 2
        let color = try XCTUnwrap((Int(y) - 3 ... Int(y) + 4).map { pixels.color(Int(last.rect.midX), $0) }
            .min { $0[1] < $1[1] })
        print("B4b quality synthetic final placement blue/red RGBA=\(color)")
        // 此区域没有第一段 red，应依次合成 blue / red；后来的 red 不能并回最早批次。
        XCTAssertEqual(Int(color[0]), 192, accuracy: 20)
        XCTAssertEqual(Int(color[1]), 64, accuracy: 20)
        XCTAssertEqual(Int(color[2]), 128, accuracy: 20)
    }
}
