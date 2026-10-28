@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class BackgroundStyleTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 40, weight: .regular)
    private let canvas = CGSize(width: 420, height: 260)

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func color(_ x: Int, _ y: Int) -> [UInt8] {
            guard x >= 0, y >= 0, x < width, y < height else { return [255, 255, 255] }
            let offset = (y * width + x) * 4
            return Array(bytes[offset ..< offset + 3])
        }
    }

    private static func isRed(_ c: [UInt8]) -> Bool {
        c[0] > 180 && c[1] < 110 && c[2] < 110
    }

    private static func isBlue(_ c: [UInt8]) -> Bool {
        c[2] > 180 && c[0] < 110 && c[1] < 110
    }

    private func render(_ layout: LYGlyphTextLayout) throws -> Pixels {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: canvas))
            layout.draw(in: renderer.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(origin: .zero, size: canvas))
        }
        return Pixels(bytes: bytes, width: width, height: height)
    }

    private func layout(
        _ text: NSAttributedString, width: CGFloat = 400,
        traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .light)
    ) throws -> LYGlyphTextLayout {
        try ResolvedText(document: LYGlyphTextDocument(attributedText: text), traits: traits).layout(
            width: width, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), scale: 1
        )
    }

    private func styled(_ string: String, _ style: LYGlyphTextBackgroundStyle, range: NSRange? = nil)
        -> NSAttributedString
    {
        let text = NSMutableAttributedString(string: string, attributes: [.font: font, .foregroundColor: UIColor.white])
        text.addAttribute(
            .lyGlyphTextBackground, value: style, range: range ?? NSRange(location: 0, length: text.length)
        )
        return text
    }

    func testRoundedFillCoversTextButNotCorners() throws {
        let value = try layout(styled("WWWW", .init(fillColor: .red, cornerRadius: 16)))
        let shape = try XCTUnwrap(value.backgroundShapes.first)
        XCTAssertEqual(shape.rects.count, 1)
        let rect = try XCTUnwrap(shape.rects.first)
        let pixels = try render(value)
        XCTAssertTrue(Self.isRed(pixels.color(Int(rect.midX), Int(rect.minY) + 2)))
        XCTAssertFalse(Self.isRed(pixels.color(Int(rect.minX) + 1, Int(rect.minY) + 1)))
        let square = try layout(styled("WWWW", .init(fillColor: .red)))
        let squareRect = try XCTUnwrap(square.backgroundShapes.first?.rects.first)
        XCTAssertTrue(try Self.isRed(render(square).color(Int(squareRect.minX) + 1, Int(squareRect.minY) + 1)))
    }

    func testStrokePaddingAndMeasurementUnchanged() throws {
        let plain = try layout(NSAttributedString(string: "WWWW", attributes: [.font: font]))
        let style = LYGlyphTextBackgroundStyle(
            strokeColor: .blue, strokeWidth: 4, padding: UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        )
        let value = try layout(styled("WWWW", style))
        XCTAssertEqual(value.size, plain.size)
        let rect = try XCTUnwrap(value.backgroundShapes.first?.rects.first)
        let text = try XCTUnwrap(value.visibleTextFragments(in: NSRange(location: 0, length: 4), source: "WWWW").first)
            .rect
        XCTAssertEqual(rect.minX, text.minX - 8, accuracy: 0.01)
        XCTAssertEqual(rect.maxY, text.maxY + 3, accuracy: 0.01)
        let pixels = try render(value)
        XCTAssertTrue(Self.isBlue(pixels.color(Int(rect.minX) + 1, Int(rect.midY))))
        XCTAssertFalse(Self.isBlue(pixels.color(Int(rect.minX) + 8, Int(rect.midY))))
    }

    func testAdjacentEqualStylesMergeAcrossRunsAndWrappedLinesSplit() throws {
        let style = LYGlyphTextBackgroundStyle(fillColor: .red, cornerRadius: 6)
        let text = NSMutableAttributedString(attributedString: styled("#话题#", style))
        text.addAttribute(.foregroundColor, value: UIColor.yellow, range: NSRange(location: 1, length: 2))
        XCTAssertEqual(try layout(text).backgroundShapes.map(\.rects.count), [1])
        let other = LYGlyphTextBackgroundStyle(fillColor: .blue, cornerRadius: 6)
        text.addAttribute(.lyGlyphTextBackground, value: other, range: NSRange(location: 3, length: 1))
        XCTAssertEqual(try layout(text).backgroundShapes.count, 2)
        let wrapped = try layout(styled("WWWWWWWWWWWW", style), width: 200)
        XCTAssertGreaterThan(try XCTUnwrap(wrapped.backgroundShapes.first).rects.count, 1)
    }

    func testHiddenTruncatedTextHasNoShapeAndInvalidValuesAreSanitized() throws {
        let style = LYGlyphTextBackgroundStyle(fillColor: .red)
        let text = NSMutableAttributedString(string: "Visible line\nhidden", attributes: [.font: font])
        text.addAttribute(.lyGlyphTextBackground, value: style, range: NSRange(location: 13, length: 6))
        let truncated = try ResolvedText(document: LYGlyphTextDocument(attributedText: text), traits: .init())
            .layout(width: 400, insets: .zero, scale: 1, numberOfLines: 1)
        XCTAssertTrue(truncated.backgroundShapes.isEmpty)
        let invalid = LYGlyphTextBackgroundStyle(
            fillColor: .red, strokeWidth: -3, cornerRadius: .nan,
            padding: UIEdgeInsets(top: .infinity, left: 2, bottom: 0, right: 0)
        )
        XCTAssertEqual(invalid.strokeWidth, 0)
        XCTAssertEqual(invalid.cornerRadius, 0)
        XCTAssertEqual(invalid.padding, UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 0))
        XCTAssertTrue(try layout(styled("W", .init())).backgroundShapes.isEmpty)
        let wrongType = NSMutableAttributedString(string: "W", attributes: [.lyGlyphTextBackground: "red"])
        XCTAssertTrue(try layout(wrongType).backgroundShapes.isEmpty)
    }

    func testDynamicColorFollowsInterfaceStyleAndRightToLeftCoversGlyphs() throws {
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .blue : .red }
        let source = styled("WWWW", .init(fillColor: dynamic))
        let light = try layout(source)
        let dark = try layout(source, traits: UITraitCollection(userInterfaceStyle: .dark))
        let rect = try XCTUnwrap(light.backgroundShapes.first?.rects.first)
        XCTAssertTrue(try Self.isRed(render(light).color(Int(rect.midX), Int(rect.minY) + 2)))
        XCTAssertTrue(try Self.isBlue(render(dark).color(Int(rect.midX), Int(rect.minY) + 2)))
        let arabic = "مرحبا"
        let rtl = try layout(styled(arabic, .init(fillColor: .red)))
        let shape = try XCTUnwrap(rtl.backgroundShapes.first?.rects.first)
        let glyphs = try XCTUnwrap(rtl.visibleTextFragments(
            in: NSRange(location: 0, length: (arabic as NSString).length), source: arabic
        ).first).rect
        XCTAssertEqual(shape.minX, glyphs.minX, accuracy: 0.5)
        XCTAssertEqual(shape.maxX, glyphs.maxX, accuracy: 0.5)
    }

    func testParserRuleAttributesCreateCapsules() throws {
        let style = LYGlyphTextBackgroundStyle(fillColor: .systemBlue, cornerRadius: 4)
        let doc = try LYGlyphTextParser(rules: [.topics(attributes: [.lyGlyphTextBackground: style])])
            .document(from: NSAttributedString(string: "看 #春天# 吧", attributes: [.font: font]))
        XCTAssertEqual(doc.styleRuns.compactMap(\.backgroundStyle), [style])
        XCTAssertEqual(doc.actions.map(\.actionID), ["topic:春天"])
    }
}
