import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class TruncationTokenPiecesTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)
    private let canvasSize = CGSize(width: 280, height: 80)
    private let longText = "Start of the article " + String(repeating: "middle words ", count: 12) + "final END"
    private let insets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

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
    }

    private static func isRed(_ c: [UInt8]) -> Bool {
        c.count == 3 && c[0] > 180 && c[1] < 110 && c[2] < 110
    }

    private static func isBlue(_ c: [UInt8]) -> Bool {
        c.count == 3 && c[2] > 180 && c[0] < 110 && c[1] < 110
    }

    private static func isGreen(_ c: [UInt8]) -> Bool {
        c.count == 3 && c[1] > 150 && c[0] < 110 && c[2] < 110
    }

    private func icon(_ color: UIColor = .blue) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    private func document(_ string: String) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: string, attributes: [.font: font, .foregroundColor: UIColor.green]
        ))
    }

    private func layout(
        _ document: LYGlyphTextDocument, token: LYGlyphTextTruncationToken?,
        mode: LYGlyphTextConfiguration.TruncationMode = .tail, width: CGFloat = 280
    ) -> LYGlyphTextLayout {
        ResolvedText(document: document, traits: UITraitCollection(userInterfaceStyle: .light)).layout(
            width: width, insets: insets, scale: 1, numberOfLines: 1, truncationToken: token, truncationMode: mode
        )
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

    private func tokenRuns(_ layout: LYGlyphTextLayout) throws -> [CTRun] {
        let line = try XCTUnwrap(layout.lines.last)
        return (CTLineGetGlyphRuns(line.text) as! [CTRun]).filter {
            (CTRunGetAttributes($0) as NSDictionary)[TailTruncation.tokenKey] != nil
        }
    }

    private func expandToken(actionID: String? = "expand") -> LYGlyphTextTruncationToken {
        .init(
            pieces: [
                .text("…"),
                .text("全文", foregroundColor: .red),
                .image(icon(), size: CGSize(width: 16, height: 16), alternativeText: "展开")
            ],
            actionID: actionID
        )
    }

    func testMixedTextAndIconPiecesRenderInOrderInsideTokenArea() throws {
        let value = try layout(document(longText), token: expandToken())
        let token = try XCTUnwrap(value.truncationToken)
        XCTAssertEqual(token.text, "…全文展开")
        // 三个片段各自成 run：继承的绿色省略号、红色文字、图片占位。
        let runs = try tokenRuns(value)
        XCTAssertEqual(runs.count, 3)
        let colors = runs.prefix(2).map {
            (CTRunGetAttributes($0) as NSDictionary)[kCTForegroundColorAttributeName].map { $0 as! CGColor }
        }
        XCTAssertTrue(try CFEqual(XCTUnwrap(colors[0]), UIColor.green.cgColor))
        XCTAssertTrue(try CFEqual(XCTUnwrap(colors[1]), UIColor.red.cgColor))

        let image = try XCTUnwrap(token.images.first)
        XCTAssertEqual(token.images.count, 1)
        XCTAssertEqual(image.rect.size, CGSize(width: 16, height: 16))
        let textMaxX = try XCTUnwrap(token.rects.dropLast().map(\.maxX).max())
        XCTAssertGreaterThanOrEqual(image.rect.minX, textMaxX - 0.5, "LTR 下图标位于文字之后")
        XCTAssertLessThanOrEqual(image.rect.maxX, canvasSize.width - insets.right + 0.5)
        XCTAssertTrue(token.rects.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(image.rect) }, "图标在点击区域内")
        // center 对齐：图标中心位于基线上方字体 ascender／descender 区域的中点。
        let baseline = try XCTUnwrap(value.lines.last).baseline.y
        XCTAssertEqual(image.rect.midY, baseline - (font.ascender + font.descender) / 2, accuracy: 0.5)

        let pixels = try render { value.draw(in: $0) }
        XCTAssertGreaterThan(pixels.count(in: image.rect.insetBy(dx: 1, dy: 1), where: Self.isBlue), 180)
        XCTAssertGreaterThan(pixels.count(in: token.rects[1], where: Self.isRed), 10)
    }

    func testHeadAndMiddleTruncationDrawTheIcon() throws {
        for mode in [LYGlyphTextConfiguration.TruncationMode.head, .middle] {
            let value = try layout(document(longText), token: expandToken(), mode: mode)
            let token = try XCTUnwrap(value.truncationToken, "\(mode)")
            let image = try XCTUnwrap(token.images.first, "\(mode)")
            XCTAssertGreaterThanOrEqual(image.rect.minX, insets.left - 0.5)
            XCTAssertLessThanOrEqual(image.rect.maxX, canvasSize.width - insets.right + 0.5)
            let pixels = try render { value.draw(in: $0) }
            XCTAssertGreaterThan(pixels.count(in: image.rect.insetBy(dx: 1, dy: 1), where: Self.isBlue), 180, "\(mode)")
            XCTAssertEqual(token.text, "…全文展开")
        }
    }

    func testTokenTooWideIsOmittedWithItsIcon() throws {
        let token = LYGlyphTextTruncationToken(pieces: [
            .text("…"), .image(icon(), size: CGSize(width: 400, height: 16))
        ], actionID: "expand")
        let value = try layout(document(longText), token: token)
        XCTAssertNil(value.truncationToken)
        XCTAssertNil(value.truncationTokenActionIndex)
        let pixels = try render { value.draw(in: $0) }
        XCTAssertEqual(pixels.count(in: CGRect(origin: .zero, size: canvasSize), where: Self.isBlue), 0)
    }

    func testInvalidImageSizeIsIgnored() throws {
        let token = LYGlyphTextTruncationToken(pieces: [
            .text("…更多"),
            .image(icon(), size: .zero, alternativeText: "忽略"),
            .image(icon(), size: CGSize(width: CGFloat.nan, height: 16))
        ])
        let value = try layout(document(longText), token: token)
        XCTAssertEqual(value.truncationToken?.text, "…更多")
        XCTAssertEqual(value.truncationToken?.images.count, 0)
        // 中文会因字体回退拆成多个 run，只断言没有图片占位 run。
        XCTAssertFalse(try tokenRuns(value).contains {
            (CTRunGetAttributes($0) as NSDictionary)[TruncationTokenContent.imageKey] != nil
        })
    }

    func testTappingIconSendsTruncationTokenEvent() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 280, height: 40))
        label.document = try document(longText)
        label.configuration.numberOfLines = 1
        label.configuration.truncationToken = expandToken()
        var events: [LYGlyphTextActionEvent] = []
        label.onAction = { events.append($0) }
        window.addSubview(label)
        label.layoutIfNeeded()
        let layout = label.measuredLayout(width: label.bounds.width)
        let image = try XCTUnwrap(layout.truncationToken?.images.first)
        let geometry = ActionGeometry(layout: layout, bounds: label.bounds, configuration: label.configuration)
        let entry = try XCTUnwrap(geometry.entries.last)
        XCTAssertTrue(entry.isTruncationToken)
        // 图标矩形相对文本容器原点，Label 内容按 configuration 的内边距（默认 0）平移。
        let point = CGPoint(x: image.rect.midX, y: image.rect.midY)
        XCTAssertTrue(entry.rects.contains { $0.contains(point) })
        XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
        label.endActionInteraction(at: point)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.actionID, "expand")
        XCTAssertEqual(events.first?.isTruncationToken, true)
    }

    func testRightToLeftKeepsIconAtLogicalEnd() throws {
        let doc = try document(String(repeating: "مرحبا بالعالم ", count: 12))
        let value = layout(doc, token: .init(pieces: [.text("…"), .image(icon(), size: CGSize(width: 16, height: 16))]))
        let image = try XCTUnwrap(value.truncationToken?.images.first)
        XCTAssertGreaterThanOrEqual(image.rect.minX, insets.left - 0.5)
        XCTAssertLessThan(image.rect.midX, canvasSize.width / 2, "RTL 行的逻辑末尾在左侧")
        let pixels = try render { value.draw(in: $0) }
        XCTAssertGreaterThan(pixels.count(in: image.rect.insetBy(dx: 1, dy: 1), where: Self.isBlue), 180)
    }

    func testSingleTextPieceMatchesLegacyToken() throws {
        let tokenFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let legacy = LYGlyphTextTruncationToken(text: "…展开\n全文", font: tokenFont, foregroundColor: .red)
        let pieces = LYGlyphTextTruncationToken(pieces: [.text("…展开\n全文", font: tokenFont, foregroundColor: .red)])
        XCTAssertEqual(pieces.text, "…展开\n全文")
        XCTAssertNil(pieces.font)
        let doc = try document(longText)
        let old = layout(doc, token: legacy)
        let new = layout(doc, token: pieces)
        XCTAssertEqual(old.truncationToken?.text, "…展开 全文")
        XCTAssertEqual(new.truncationToken?.text, old.truncationToken?.text)
        XCTAssertEqual(new.truncationToken?.rects, old.truncationToken?.rects)
        XCTAssertEqual(new.lines.last?.visibleSourceRanges, old.lines.last?.visibleSourceRanges)
        XCTAssertEqual(try render { new.draw(in: $0) }.bytes, try render { old.draw(in: $0) }.bytes)
    }

    func testPiecesParticipateInEquality() {
        let image = icon()
        let first = LYGlyphTextTruncationToken(pieces: [.text("…"), .image(image, size: CGSize(width: 16, height: 16))])
        XCTAssertEqual(first, .init(pieces: [.text("…"), .image(image, size: CGSize(width: 16, height: 16))]))
        XCTAssertNotEqual(first, .init(pieces: [.text("…"), .image(image, size: CGSize(width: 18, height: 16))]))
        XCTAssertNotEqual(first, .init(text: "…"))
    }

    func testPressedColorRecolorsTextButNotIcon() throws {
        let token = LYGlyphTextTruncationToken(
            pieces: [.text("…全文"), .image(icon(), size: CGSize(width: 16, height: 16))], actionID: "expand",
            pressedForegroundColor: .red, pressedBackgroundColor: nil
        )
        let value = try layout(document(longText), token: token)
        let index = try XCTUnwrap(value.truncationTokenActionIndex)
        let tokenGeometry = try XCTUnwrap(value.truncationToken)
        let image = try XCTUnwrap(tokenGeometry.images.first)
        let textRect = try XCTUnwrap(tokenGeometry.rects.first)
        let normal = try render { value.draw(in: $0) }
        let pressed = try render { value.draw(in: $0, pressedActionIndex: index) }
        XCTAssertGreaterThan(normal.count(in: textRect, where: Self.isGreen), 5)
        XCTAssertEqual(pressed.count(in: textRect, where: Self.isGreen), 0)
        XCTAssertGreaterThan(pressed.count(in: textRect, where: Self.isRed), 5)
        XCTAssertGreaterThan(pressed.count(in: image.rect.insetBy(dx: 1, dy: 1), where: Self.isBlue), 180)
    }

    func testAccessibilityReadsTextAndAlternativeTextInOrder() throws {
        let doc = try document(longText)
        let bounds = CGRect(x: 0, y: 0, width: 280, height: 60)
        func tokenLabel(_ token: LYGlyphTextTruncationToken) -> String? {
            let value = layout(doc, token: token)
            let semantics = TextAccessibility(
                layout: value, document: doc, bounds: bounds, configuration: .init(textContainerInset: insets),
                nativeViews: [:]
            )
            guard let index = value.truncationTokenActionIndex else { return nil }
            for item in semantics.items {
                if case let .text(entry) = item, entry.actionIndex == index { return entry.label }
            }
            return nil
        }
        XCTAssertEqual(tokenLabel(expandToken()), "…全文展开")
        let iconOnly = LYGlyphTextTruncationToken(
            pieces: [.image(icon(), size: CGSize(width: 16, height: 16), alternativeText: "展开")], actionID: "expand"
        )
        XCTAssertEqual(tokenLabel(iconOnly), "展开")
        let decorative = LYGlyphTextTruncationToken(
            pieces: [.image(icon(), size: CGSize(width: 16, height: 16))], actionID: "expand"
        )
        XCTAssertNil(tokenLabel(decorative), "没有文字与替代文本时不单独朗读")
    }

    func testPreparedLayoutCarriesTokenIcon() async throws {
        let doc = try document(longText)
        let configuration = LYGlyphTextConfiguration(
            textContainerInset: insets, numberOfLines: 1, truncationToken: expandToken()
        )
        // 预排版在后台构造布局，token 图片随 Sendable 配置一起传递。
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: doc, configuration: configuration, width: 280,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )
        XCTAssertEqual(prepared.layout.truncationToken?.images.count, 1)
        XCTAssertEqual(prepared.layout.truncationToken?.text, "…全文展开")
    }
}
