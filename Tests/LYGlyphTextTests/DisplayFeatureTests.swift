import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class DisplayFeatureTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 40, weight: .regular)
    private let canvasSize = CGSize(width: 420, height: 220)
    private let longText = String(repeating: "Truncated feed content ", count: 8)

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func color(_ x: Int, _ y: Int) -> [UInt8] {
            guard x >= 0, y >= 0, x < width, y < height else { return [] }
            let offset = (y * width + x) * 4
            return Array(bytes[offset ..< offset + 3])
        }

        func count(in rect: CGRect, where predicate: ([UInt8]) -> Bool) -> Int {
            let left = max(0, Int(floor(rect.minX)))
            let right = min(width, Int(ceil(rect.maxX)))
            let top = max(0, Int(floor(rect.minY)))
            let bottom = min(height, Int(ceil(rect.maxY)))
            guard left < right, top < bottom else { return 0 }
            return (top ..< bottom).reduce(0) { total, y in
                total + (left ..< right).count { predicate(color($0, y)) }
            }
        }

        /// 满足条件像素的平均 y；没有像素时返回 nil。
        func meanY(where predicate: ([UInt8]) -> Bool) -> CGFloat? {
            var sum = 0
            var count = 0
            for y in 0 ..< height {
                for x in 0 ..< width where predicate(color(x, y)) {
                    sum += y
                    count += 1
                }
            }
            return count == 0 ? nil : CGFloat(sum) / CGFloat(count)
        }
    }

    private static func isRed(_ c: [UInt8]) -> Bool {
        c.count == 3 && c[0] > 180 && c[1] < 110 && c[2] < 110
    }

    private static func isGreen(_ c: [UInt8]) -> Bool {
        c.count == 3 && c[1] > 150 && c[0] < 110 && c[2] < 110
    }

    private func render(_ draw: (CGContext) -> Void) throws -> Pixels {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: canvasSize))
            draw(renderer.cgContext)
        }
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

    private func layout(
        _ document: LYGlyphTextDocument, width: CGFloat = 400, lines: Int = 0,
        token: LYGlyphTextTruncationToken? = nil
    ) -> LYGlyphTextLayout {
        ResolvedText(document: document, traits: UITraitCollection(userInterfaceStyle: .light)).layout(
            width: width, insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10), scale: 1,
            numberOfLines: lines, truncationToken: token
        )
    }

    private func document(_ string: String, _ attributes: [NSAttributedString.Key: Any] = [:]) throws
        -> LYGlyphTextDocument
    {
        var attributes = attributes
        attributes[.font] = attributes[.font] ?? UIFont.systemFont(ofSize: 20)
        attributes[.foregroundColor] = attributes[.foregroundColor] ?? UIColor.green
        return try LYGlyphTextDocument(attributedText: NSAttributedString(string: string, attributes: attributes))
    }

    private func tokenRun(_ layout: LYGlyphTextLayout) throws -> CTRun {
        let line = try XCTUnwrap(layout.lines.last)
        return try XCTUnwrap((CTLineGetGlyphRuns(line.text) as! [CTRun]).first {
            (CTRunGetAttributes($0) as NSDictionary)[TailTruncation.tokenKey] != nil
        })
    }

    // MARK: - Truncation token

    func testDefaultTokenIsUnchangedEllipsisWithoutAction() throws {
        let value = try layout(document(longText), width: 220, lines: 1)
        let line = try XCTUnwrap(value.lines.last)
        let text = try XCTUnwrap(line.truncationTokenRange)
        XCTAssertEqual(text.length, 1)
        XCTAssertEqual(value.truncationToken?.text, "…")
        XCTAssertNil(value.truncationToken?.actionID)
        XCTAssertNil(value.truncationTokenActionIndex)
        XCTAssertFalse(try XCTUnwrap(value.truncationToken?.rects).isEmpty)
    }

    func testCustomTokenTextFontAndColorReplaceEllipsis() throws {
        let tokenFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let token = LYGlyphTextTruncationToken(text: "…展开全文", font: tokenFont, foregroundColor: .red)
        let value = try layout(document(longText), width: 260, lines: 2, token: token)
        XCTAssertEqual(value.lines.count, 2)
        let line = try XCTUnwrap(value.lines.last)
        XCTAssertEqual(line.truncationTokenRange?.length, 5)
        XCTAssertEqual(value.truncationToken?.text, "…展开全文")
        let attributes = try CTRunGetAttributes(tokenRun(value)) as NSDictionary
        XCTAssertEqual((attributes[kCTFontAttributeName] as? UIFont)?.pointSize, 14)
        let color = try XCTUnwrap(attributes[kCTForegroundColorAttributeName])
        XCTAssertTrue(CFEqual(color as CFTypeRef, UIColor.red.cgColor))
        // token 不属于原文：可见原文区间不包含生成内容，最后一行不超出可用宽度。
        let source = longText as NSString
        for range in line.visibleSourceRanges {
            XCTAssertLessThanOrEqual(NSMaxRange(range), source.length)
        }
        XCTAssertLessThanOrEqual(CGFloat(CTLineGetTypographicBounds(line.text, nil, nil, nil)), 240.5)
    }

    func testEmptyTokenTruncatesWithoutGeneratedContentAndNewlineBecomesSpace() throws {
        let empty = try layout(document(longText), width: 220, lines: 1, token: .init(text: ""))
        XCTAssertNil(empty.truncationToken)
        XCTAssertEqual(empty.lines.count, 1)
        let spaced = try layout(document(longText), width: 260, lines: 1, token: .init(text: "…\nmore"))
        XCTAssertEqual(spaced.truncationToken?.text, "… more")
    }

    func testTokenFittingNothingIsOmittedLikeEllipsis() throws {
        let token = LYGlyphTextTruncationToken(text: String(repeating: "W", count: 30), actionID: "expand")
        let value = try layout(document(longText), width: 120, lines: 1, token: token)
        XCTAssertNil(value.truncationToken)
        XCTAssertNil(value.truncationTokenActionIndex)
    }

    func testChangingTokenInvalidatesLabelLayout() throws {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document(longText)
        label.configuration.numberOfLines = 1
        XCTAssertEqual(label.measuredLayout(width: 220).truncationToken?.text, "…")
        label.configuration.truncationToken = .init(text: "…全文")
        XCTAssertEqual(label.measuredLayout(width: 220).truncationToken?.text, "…全文")
    }

    func testTokenActionTapSendsTokenEventAndPressedState() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 260, height: 40))
        label.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: longText, attributes: [.font: UIFont.systemFont(ofSize: 20)]),
            actions: [.init(actionID: "first", range: NSRange(location: 0, length: 9))]
        )
        label.configuration.numberOfLines = 1
        label.configuration.truncationToken = .init(text: "…展开", actionID: "expand")
        var events: [LYGlyphTextActionEvent] = []
        label.onAction = { events.append($0) }
        window.addSubview(label)
        label.layoutIfNeeded()
        let layout = label.measuredLayout(width: label.bounds.width)
        XCTAssertEqual(layout.truncationTokenActionIndex, 1)
        let geometry = ActionGeometry(layout: layout, bounds: label.bounds, configuration: label.configuration)
        let entry = try XCTUnwrap(geometry.entries.last)
        XCTAssertTrue(entry.isTruncationToken)
        let rect = try XCTUnwrap(entry.rects.first)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
        XCTAssertEqual(label.pressedActionIndex, 1)
        label.endActionInteraction(at: point)
        XCTAssertNil(label.pressedActionIndex)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.actionID, "expand")
        XCTAssertTrue(event.isTruncationToken)
        XCTAssertEqual(event.range.location, NSNotFound)
        XCTAssertEqual(event.kind, .tap)
        // 文档动作仍正常命中且不是 token 事件。
        let first = try XCTUnwrap(geometry.entries.first { $0.actionIndex == 0 }?.rects.first)
        let firstPoint = CGPoint(x: first.midX, y: first.midY)
        XCTAssertTrue(label.beginActionInteraction(at: firstPoint, touchedView: label))
        label.endActionInteraction(at: firstPoint)
        XCTAssertEqual(events.last?.actionID, "first")
        XCTAssertEqual(events.last?.isTruncationToken, false)
    }

    func testTokenWithoutOrEmptyActionIDIsNotInteractive() throws {
        for id in [nil, ""] as [String?] {
            let value = try layout(document(longText), width: 220, lines: 1, token: .init(text: "…更多", actionID: id))
            XCTAssertNotNil(value.truncationToken)
            XCTAssertNil(value.truncationTokenActionIndex)
            let geometry = ActionGeometry(
                layout: value, bounds: CGRect(x: 0, y: 0, width: 220, height: 60), configuration: .init()
            )
            XCTAssertTrue(geometry.entries.isEmpty)
        }
    }

    func testPressedTokenDrawsBackgroundAndForegroundColor() throws {
        let token = LYGlyphTextTruncationToken(
            text: "█████", font: font, foregroundColor: .green, actionID: "expand",
            pressedForegroundColor: .blue, pressedBackgroundColor: .red
        )
        let doc = try document(String(repeating: "AAAA ", count: 20), [.font: font])
        let value = layout(doc, width: 400, lines: 1, token: token)
        let index = try XCTUnwrap(value.truncationTokenActionIndex)
        let rect = try XCTUnwrap(value.truncationToken?.rects.first)
        let normal = try render { value.draw(in: $0) }
        let pressed = try render { value.draw(in: $0, pressedActionIndex: index) }
        let isBlue: ([UInt8]) -> Bool = { $0.count == 3 && $0[2] > 150 && $0[0] < 110 && $0[1] < 110 }
        XCTAssertGreaterThan(normal.count(in: rect, where: Self.isGreen), 50)
        XCTAssertEqual(normal.count(in: rect, where: isBlue), 0)
        XCTAssertEqual(normal.count(in: rect, where: Self.isRed), 0)
        XCTAssertGreaterThan(pressed.count(in: rect, where: isBlue), 50)
        XCTAssertEqual(pressed.count(in: rect, where: Self.isGreen), 0)
        XCTAssertGreaterThan(pressed.count(in: rect, where: Self.isRed), 0)
    }

    func testInteractiveTokenIsLastAccessibilityButton() throws {
        let doc = try document(longText)
        let value = layout(doc, width: 260, lines: 1, token: .init(text: "…展开", actionID: "expand"))
        let semantics = TextAccessibility(
            layout: value, document: doc, bounds: CGRect(x: 0, y: 0, width: 260, height: 60),
            configuration: .init(textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)),
            nativeViews: [:]
        )
        guard case let .text(entry) = try XCTUnwrap(semantics.items.last) else { return XCTFail("缺少 token 元素") }
        XCTAssertEqual(entry.label, "…展开")
        XCTAssertEqual(entry.actionIndex, value.truncationTokenActionIndex)
        let plain = layout(doc, width: 260, lines: 1, token: .init(text: "…展开"))
        let decorative = TextAccessibility(
            layout: plain, document: doc, bounds: CGRect(x: 0, y: 0, width: 260, height: 60),
            configuration: .init(textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)),
            nativeViews: [:]
        )
        XCTAssertFalse(decorative.items.contains {
            if case let .text(entry) = $0 { return entry.label == "…展开" }
            return false
        })
    }

    // MARK: - Pressed corner radius

    func testPressedCornerRadiusRoundsMergedLineBackground() throws {
        for radius in [CGFloat(0), 14] {
            let source = "████████"
            let doc = try LYGlyphTextDocument(
                attributedText: NSAttributedString(string: source, attributes: [
                    .font: font, .foregroundColor: UIColor.green
                ]),
                actions: [.init(
                    actionID: "a", range: NSRange(location: 0, length: 8),
                    pressedStyle: .init(foregroundColor: .green, backgroundColor: .red, cornerRadius: radius)
                )]
            )
            let value = layout(doc)
            let merged = try XCTUnwrap(LYGlyphTextLayout.mergedLineRects(value.actionIndex[0].rects).first)
            XCTAssertEqual(LYGlyphTextLayout.mergedLineRects(value.actionIndex[0].rects).count, 1)
            let pixels = try render { value.draw(in: $0, pressedActionIndex: 0) }
            let corner = pixels.color(Int(merged.minX) + 1, Int(merged.minY) + 1)
            if radius == 0 {
                XCTAssertTrue(Self.isRed(corner) || Self.isGreen(corner), "\(corner)")
            } else {
                XCTAssertFalse(Self.isRed(corner), "\(corner)")
            }
        }
    }

    // MARK: - Shadow and stroke

    func testShadowDrawsOffsetBelowGlyphs() throws {
        let shadow = NSShadow()
        shadow.shadowOffset = CGSize(width: 0, height: 12)
        shadow.shadowBlurRadius = 0
        shadow.shadowColor = UIColor.red
        let doc = try document("████", [.font: font, .shadow: shadow])
        let pixels = try render { layout(doc).draw(in: $0) }
        let shadowY = try XCTUnwrap(pixels.meanY(where: Self.isRed))
        let glyphY = try XCTUnwrap(pixels.meanY(where: Self.isGreen))
        XCTAssertGreaterThan(shadowY, glyphY + 4)
        let plainLayout = try layout(document("████", [.font: font]))
        let plain = try render { plainLayout.draw(in: $0) }
        XCTAssertNil(plain.meanY(where: Self.isRed))
    }

    func testStrokeWidthSignControlsFillAndUsesStrokeColor() throws {
        let outlineLayout = try layout(document("████", [.font: font, .strokeWidth: 8, .strokeColor: UIColor.red]))
        let outline = try render { outlineLayout.draw(in: $0) }
        XCTAssertGreaterThan(outline.count(in: CGRect(origin: .zero, size: canvasSize), where: Self.isRed), 50)
        XCTAssertEqual(outline.count(in: CGRect(origin: .zero, size: canvasSize), where: Self.isGreen), 0)
        let filledLayout = try layout(document("████", [.font: font, .strokeWidth: -8, .strokeColor: UIColor.red]))
        let filled = try render { filledLayout.draw(in: $0) }
        XCTAssertGreaterThan(filled.count(in: CGRect(origin: .zero, size: canvasSize), where: Self.isRed), 50)
        XCTAssertGreaterThan(filled.count(in: CGRect(origin: .zero, size: canvasSize), where: Self.isGreen), 50)
    }

    func testStrokeDoesNotChangeMeasurement() throws {
        let plain = try layout(document("Stroke text", [.font: font]), width: 400)
        let stroked = try layout(document("Stroke text", [.font: font, .strokeWidth: -8]), width: 400)
        XCTAssertEqual(plain.size, stroked.size)
    }

    // MARK: - Links

    func testLinksBecomeActionsOnlyWhenRequested() throws {
        let text = NSMutableAttributedString(string: "访问 官网 或 帮助")
        let url = try XCTUnwrap(URL(string: "https://example.com/home"))
        text.addAttribute(.link, value: url, range: NSRange(location: 3, length: 2))
        text.addAttribute(.link, value: "help", range: NSRange(location: 8, length: 2))
        text.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 20), range: NSRange(location: 4, length: 1))
        XCTAssertTrue(try LYGlyphTextDocument(attributedText: text).actions.isEmpty)
        let style = LYGlyphTextPressedStyle(backgroundColor: .red, cornerRadius: 4)
        let doc = try LYGlyphTextDocument(attributedText: text, linkPressedStyle: style)
        XCTAssertEqual(doc.actions.map(\.actionID), ["https://example.com/home", "help"])
        XCTAssertEqual(doc.actions.map(\.range), [NSRange(location: 3, length: 2), NSRange(location: 8, length: 2)])
        XCTAssertEqual(doc.actions.first?.pressedStyle.cornerRadius, 4)
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: text, actions: [.init(actionID: "x", range: NSRange(location: 4, length: 2))],
            linkPressedStyle: style
        )) { error in
            XCTAssertEqual(
                error as? LYGlyphTextDocumentError,
                .overlappingActionRanges(
                    first: NSRange(location: 3, length: 2),
                    second: NSRange(location: 4, length: 2)
                )
            )
        }
    }

    func testPressedStyleSanitizesCornerRadius() {
        XCTAssertEqual(LYGlyphTextPressedStyle(cornerRadius: -3).cornerRadius, 0)
        XCTAssertEqual(LYGlyphTextPressedStyle(cornerRadius: .infinity).cornerRadius, 0)
        XCTAssertEqual(LYGlyphTextPressedStyle(cornerRadius: 6).cornerRadius, 6)
    }
}
