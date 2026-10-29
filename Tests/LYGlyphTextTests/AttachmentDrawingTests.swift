@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class AttachmentDrawingTests: XCTestCase {
    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 12, height: 18), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 18))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 9, width: 12, height: 9))
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 5))
        }
    }

    private func document(image: UIImage, size: CGSize) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}", attributes: [.font: UIFont.systemFont(ofSize: 20)]),
            attachments: [0: LYGlyphTextAttachment(id: "direction", image: image, size: size)]
        )
    }

    private func canvas(_ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 160), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 160))
            draw(context)
        }
    }

    private func pixels(_ image: UIImage) throws -> (bytes: [UInt8], stride: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        XCTAssertEqual(cgImage.bitsPerPixel, 32)
        return (
            Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data))),
            cgImage.bytesPerRow
        )
    }

    func testEveryUIImageOrientationMatchesUIKitImageDrawing() throws {
        let source = try XCTUnwrap(image().cgImage)
        for orientation in [
            UIImage.Orientation.up,
            .down,
            .left,
            .right,
            .upMirrored,
            .downMirrored,
            .leftMirrored,
            .rightMirrored
        ] {
            let image = UIImage(cgImage: source, scale: 3, orientation: orientation)
            let view = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 80, height: 100))
            view.document = try document(image: image, size: CGSize(width: 32, height: 44))
            let rect = try XCTUnwrap(view.measuredLayout(width: 80).attachments.first).rect
            let actual = try pixels(canvas { view.layer.render(in: $0.cgContext) })
            let expected = try pixels(canvas { _ in image.draw(in: rect) })
            // layer 先在设备 scale 栅格化再合成；参考图直接在 scale 1 绘制。
            // 采样色块内部的主色，避免将两次插值的边缘像素差异误判为方向错误。
            var sampledColors: Set<Int> = []
            for vertical in [0.16, 0.4, 0.6, 0.84] {
                for horizontal in [0.16, 0.4, 0.6, 0.84] {
                    let x = Int(rect.minX + rect.width * horizontal)
                    let y = Int(rect.minY + rect.height * vertical)
                    let offset = y * actual.stride + x * 4
                    let expectedOffset = y * expected.stride + x * 4
                    let actualColor = try XCTUnwrap((0 ..< 3)
                        .max { actual.bytes[offset + $0] < actual.bytes[offset + $1] })
                    let expectedColor = try XCTUnwrap((0 ..< 3).max {
                        expected.bytes[expectedOffset + $0] < expected.bytes[expectedOffset + $1]
                    })
                    sampledColors.insert(expectedColor)
                    XCTAssertEqual(
                        actualColor, expectedColor,
                        "orientation=\(orientation.rawValue), pixel=(\(x),\(y))"
                    )
                }
            }
            XCTAssertEqual(sampledColors.count, 3)
            XCTAssertEqual(rect.size, CGSize(width: 32, height: 44))
        }
    }

    func testOversizedImageClipsToInsetsAndCompressedBoundsIncludingNonzeroOrigin() throws {
        let view = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 80, height: 54))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 160))
        host.addSubview(view)
        view.document = try document(image: image(), size: CGSize(width: 200, height: 120))
        view.configuration.textContainerInset = UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 10)
        let normal = try pixels(canvas { host.layer.render(in: $0.cgContext) })
        view.bounds.origin = CGPoint(x: 13, y: 17)
        view.setNeedsDisplay()
        // 渲染宿主以包含子 layer 的 bounds→frame 变换；直接 render 子 layer 使用其本地坐标。
        let shifted = try pixels(canvas { host.layer.render(in: $0.cgContext) })
        XCTAssertEqual(normal.bytes, shifted.bytes)
        let white = try pixels(canvas { _ in })
        var colored = 0
        for y in 0 ..< 160 {
            for x in 0 ..< 100 {
                let offset = y * shifted.stride + x * 4
                let actual = Array(shifted.bytes[offset ..< offset + 4])
                let background = Array(white.bytes[offset ..< offset + 4])
                if x < 6 || x >= 70 || y < 4 || y >= 46 {
                    XCTAssertEqual(actual, background, "裁切外像素 (\(x),\(y))")
                } else if actual != background {
                    colored += 1
                }
            }
        }
        XCTAssertGreaterThan(colored, 1000)
    }

    func testContentModeDrawingRectsMatchUIImageViewSemantics() {
        let box = CGRect(x: 10, y: 20, width: 30, height: 30)
        let size = CGSize(width: 40, height: 20)
        let expected: [(UIView.ContentMode, CGRect)] = [
            (.scaleToFill, box),
            (.redraw, box),
            (.scaleAspectFit, CGRect(x: 10, y: 27.5, width: 30, height: 15)),
            (.scaleAspectFill, CGRect(x: -5, y: 20, width: 60, height: 30)),
            (.center, CGRect(x: 5, y: 25, width: 40, height: 20)),
            (.top, CGRect(x: 5, y: 20, width: 40, height: 20)),
            (.bottom, CGRect(x: 5, y: 30, width: 40, height: 20)),
            (.left, CGRect(x: 10, y: 25, width: 40, height: 20)),
            (.right, CGRect(x: 0, y: 25, width: 40, height: 20)),
            (.topLeft, CGRect(x: 10, y: 20, width: 40, height: 20)),
            (.topRight, CGRect(x: 0, y: 20, width: 40, height: 20)),
            (.bottomLeft, CGRect(x: 10, y: 30, width: 40, height: 20)),
            (.bottomRight, CGRect(x: 0, y: 30, width: 40, height: 20))
        ]
        for (mode, rect) in expected {
            XCTAssertEqual(
                AttachmentImageGeometry.drawingRect(imageSize: size, in: box, contentMode: mode), rect,
                "contentMode=\(mode.rawValue)"
            )
        }
        // 无有效像素尺寸的图片退回填满声明框。
        for invalid in [CGSize.zero, CGSize(width: 0, height: 10), CGSize(width: CGFloat.nan, height: 10)] {
            XCTAssertEqual(
                AttachmentImageGeometry.drawingRect(imageSize: invalid, in: box, contentMode: .scaleAspectFit), box
            )
        }
    }

    func testContentModeDrawsInsideDeclaredBoxWithoutChangingLayout() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        func render(_ mode: UIView.ContentMode?) throws -> (rect: CGRect, pixels: (bytes: [UInt8], stride: Int)) {
            let attachment = if let mode {
                LYGlyphTextAttachment(id: "wide", image: wide, size: CGSize(width: 30, height: 30), contentMode: mode)
            } else {
                LYGlyphTextAttachment(id: "wide", image: wide, size: CGSize(width: 30, height: 30))
            }
            let view = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            view.configuration.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 0, right: 0)
            view.document = try LYGlyphTextDocument(
                attributedText: NSAttributedString(
                    string: "\u{FFFC}", attributes: [.font: UIFont.systemFont(ofSize: 20)]
                ),
                attachments: [0: attachment]
            )
            let rect = try XCTUnwrap(view.measuredLayout(width: 100).attachments.first).rect
            return try (rect, pixels(canvas { view.layer.render(in: $0.cgContext) }))
        }
        func isRed(_ result: (bytes: [UInt8], stride: Int), _ x: CGFloat, _ y: CGFloat) -> Bool {
            let offset = Int(y) * result.stride + Int(x) * 4
            return result.bytes[offset ..< offset + 3].count(where: { $0 < 60 }) == 2
        }
        func isWhite(_ result: (bytes: [UInt8], stride: Int), _ x: CGFloat, _ y: CGFloat) -> Bool {
            let offset = Int(y) * result.stride + Int(x) * 4
            return result.bytes[offset ..< offset + 3].allSatisfy { $0 > 240 }
        }

        let stretched = try render(nil)
        let box = stretched.rect
        XCTAssertEqual(box.size, CGSize(width: 30, height: 30))
        XCTAssertTrue(isRed(stretched.pixels, box.midX, box.minY + 3), "默认拉伸填满")

        let fit = try render(.scaleAspectFit)
        XCTAssertEqual(fit.rect, box, "contentMode 不改变排版")
        XCTAssertTrue(isRed(fit.pixels, box.midX, box.midY))
        XCTAssertTrue(isWhite(fit.pixels, box.midX, box.minY + 3), "fit 上方留白")
        XCTAssertTrue(isWhite(fit.pixels, box.midX, box.maxY - 3), "fit 下方留白")

        let fill = try render(.scaleAspectFill)
        XCTAssertEqual(fill.rect, box)
        XCTAssertTrue(isRed(fill.pixels, box.minX + 3, box.minY + 3), "fill 覆盖整个声明框")
        XCTAssertTrue(isWhite(fill.pixels, box.minX - 3, box.midY), "fill 左侧溢出被裁切")
        XCTAssertTrue(isWhite(fill.pixels, box.maxX + 3, box.midY), "fill 右侧溢出被裁切")

        let center = try render(.center)
        XCTAssertTrue(isRed(center.pixels, box.midX, box.midY))
        XCTAssertTrue(isWhite(center.pixels, box.midX, box.minY + 2), "center 保持原尺寸")
        XCTAssertTrue(isWhite(center.pixels, box.maxX + 3, box.midY), "center 横向溢出被裁切")
    }

    func testTwoLabelsShareDocumentAndClearIndependently() throws {
        let document = try document(image: image(), size: CGSize(width: 32, height: 44))
        let first = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 80, height: 100))
        let second = LYGlyphTextLabel(frame: first.frame)
        first.document = document
        second.document = document
        let expected = try pixels(canvas { first.layer.render(in: $0.cgContext) })
        XCTAssertEqual(expected.bytes, try pixels(canvas { second.layer.render(in: $0.cgContext) }).bytes)
        first.document = nil
        first.setNeedsDisplay()
        XCTAssertEqual(
            try pixels(canvas { first.layer.render(in: $0.cgContext) }).bytes,
            try pixels(canvas { _ in }).bytes
        )
        XCTAssertEqual(expected.bytes, try pixels(canvas { second.layer.render(in: $0.cgContext) }).bytes)
        XCTAssertTrue(first.subviews.isEmpty && second.subviews.isEmpty)
    }
}
