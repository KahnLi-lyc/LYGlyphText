import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class DebugOverlayTests: XCTestCase {
    private let canvas = CGSize(width: 400, height: 200)

    private func pixels(_ draw: (CGContext) -> Void) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: canvas))
            draw(renderer.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: Int(canvas.width * canvas.height) * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                bytesPerRow: Int(canvas.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(origin: .zero, size: canvas))
        }
        return bytes
    }

    private func color(_ bytes: [UInt8], _ x: CGFloat, _ y: CGFloat) -> [Int] {
        let offset = (Int(y) * Int(canvas.width) + Int(x)) * 4
        return [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]
    }

    /// 1pt 线落在小数坐标时会抗锯齿到相邻两行；取 y±1 范围内目标通道领先最多的像素。
    private func strongest(_ bytes: [UInt8], _ x: CGFloat, _ y: CGFloat, channel: Int, over other: Int) -> Int {
        (-1 ... 1).map { offset in
            let value = color(bytes, x, y.rounded(.down) + CGFloat(offset))
            return value[channel] - value[other]
        }.max() ?? 0
    }

    private func layout() throws -> LYGlyphTextLayout {
        let image = try LYGlyphTextAttachment(
            id: "i", image: XCTUnwrap(UIImage(systemName: "star")), size: CGSize(width: 30, height: 30)
        )
        let doc = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "Line \u{FFFC} action", attributes: [
                .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white
            ]),
            attachments: [5: image], actions: [.init(actionID: "a", range: NSRange(location: 7, length: 6))]
        )
        return ResolvedText(document: doc, traits: UITraitCollection()).layout(
            width: 400, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), scale: 1
        )
    }

    func testEmptyOptionsDrawNothingExtra() throws {
        let value = try layout()
        let plain = try pixels { value.draw(in: $0) }
        let empty = try pixels {
            value.draw(in: $0)
            value.drawDebug([], in: $0)
        }
        XCTAssertEqual(plain, empty)
    }

    func testEachOptionDrawsItsGeometry() throws {
        let value = try layout()
        let line = try XCTUnwrap(value.lines.first)
        let baseline = try pixels { value.drawDebug(.baselines, in: $0) }
        let onBaseline = color(baseline, line.baseline.x + 10, line.baseline.y)
        XCTAssertGreaterThan(onBaseline[2], onBaseline[0] + 60)
        let frames = try pixels { value.drawDebug(.lineFrames, in: $0) }
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line.text, &ascent, nil, nil)
        XCTAssertGreaterThan(strongest(frames, line.baseline.x + 10, line.baseline.y - ascent, channel: 0, over: 2), 60)
        let attachment = try XCTUnwrap(value.attachments.first?.rect)
        let boxes = try pixels { value.drawDebug(.attachmentFrames, in: $0) }
        XCTAssertGreaterThan(strongest(boxes, attachment.midX, attachment.minY, channel: 1, over: 0), 60)
        let action = try XCTUnwrap(value.actionIndex.first?.rects.first)
        let regions = try pixels { value.drawDebug(.actionRegions, in: $0) }
        let inside = color(regions, action.midX, action.midY)
        XCTAssertGreaterThan(inside[0], inside[2] + 40)
        XCTAssertEqual(color(regions, 395, 195), [255, 255, 255])
    }

    func testViewAttachmentFrameIsDrawnOutsideTheView() throws {
        let descriptor = LYGlyphTextViewAttachment(id: "v", viewID: "badge", size: CGSize(width: 40, height: 30))
        let doc = try LYGlyphTextDocument(
            attributedText: NSAttributedString(
                string: "A\u{FFFC}B",
                attributes: [.font: UIFont.systemFont(ofSize: 24)]
            ),
            viewAttachments: [1: descriptor]
        )
        let value = ResolvedText(document: doc, traits: UITraitCollection()).layout(
            width: 400, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), scale: 1
        )
        let rect = try XCTUnwrap(value.viewAttachments.first?.rect)
        let boxes = try pixels { value.drawDebug(.attachmentFrames, in: $0) }
        // 视图会盖住自身区域，所以框必须落在视图外侧。
        XCTAssertGreaterThan(strongest(boxes, rect.midX, rect.minY - 1, channel: 1, over: 0), 60)
        XCTAssertEqual(color(boxes, rect.midX, rect.midY), [255, 255, 255])
    }

    func testChangingOptionsDoesNotRebuildLayout() throws {
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "Debug"))
        _ = label.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        label.resetLayoutMeasurementCounts()
        label.debugOptions = .all
        _ = label.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        XCTAssertEqual(LYGlyphTextView(document: nil, debugOptions: .baselines).debugOptions, .baselines)
    }
}
