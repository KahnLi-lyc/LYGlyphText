@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class LayoutTests: XCTestCase {
    private func label(_ text: String = "测试 Hello 👨‍👩‍👧‍👦 e\u{301} ", repeatCount: Int = 1) throws -> LYGlyphTextLabel {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: String(repeating: text, count: repeatCount), attributes: [.font: UIFont.systemFont(ofSize: 20)]
        ))
        return label
    }

    func testEmptyTextOnlyKeepsInsets() throws {
        let view = try label("")
        view.configuration.textContainerInset = UIEdgeInsets(top: 3, left: 4, bottom: 5, right: 6)
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 10, height: 8))
        view.document = nil
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 100, height: 1)), CGSize(width: 10, height: 8))
    }

    func testFiniteZeroAndInfiniteWidthsAreSafe() throws {
        let view = try label(repeatCount: 8)
        for width in [CGFloat.zero, 1, 100, .infinity, .greatestFiniteMagnitude] {
            let size = view.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThanOrEqual(size.width, 0)
            XCTAssertGreaterThanOrEqual(size.height, 0)
        }
        XCTAssertEqual(view.sizeThatFits(.zero).width, 0)
    }

    func testExplicitNewlinesAndTrailingEmptyLine() throws {
        let one = try label("Hello").sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        let two = try label("Hello\n世界").sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        let trailing = try label("Hello\n").sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        XCTAssertGreaterThan(two.height, one.height * 1.5)
        XCTAssertGreaterThan(trailing.height, one.height * 1.5)
        XCTAssertLessThan(two.width, 100) // 理想宽度保留显式换行，不连接两行。
    }

    func testNewlineOnlyContentKeepsNaturalLineHeight() throws {
        let one = try label("\n")
        let two = try label("\n\n")
        XCTAssertGreaterThan(one.intrinsicContentSize.height, 20)
        XCTAssertGreaterThan(two.intrinsicContentSize.height, one.intrinsicContentSize.height)
        XCTAssertEqual(
            one.intrinsicContentSize.height,
            one.sizeThatFits(CGSize(width: 100, height: CGFloat.infinity)).height
        )
        let whitespace = try label("   ")
        XCTAssertGreaterThan(whitespace.intrinsicContentSize.height, 0)
    }

    func testUnicodeRangesCoverOriginalUTF16Input() throws {
        let text = "你好😀👨‍👩‍👧‍👦e\u{301} مرحبا بالعالم"
        let view = try label(text)
        let layout = view.measuredLayout(width: 85)
        XCTAssertGreaterThan(layout.lines.count, 1)
        XCTAssertEqual(
            layout.lines.flatMap(\.visibleSourceRanges).map(\.length).reduce(0, +),
            (text as NSString).length
        )
        var cursor = 0
        for line in layout.lines {
            for range in line.visibleSourceRanges {
                XCTAssertEqual(range.location, cursor)
                XCTAssertNotNil(Range(range, in: text))
                cursor = NSMaxRange(range)
            }
        }
    }

    func testInsetsAreIncludedExactlyOnce() throws {
        let view = try label("Hello\nWorld")
        let before = view.sizeThatFits(CGSize(width: 160, height: CGFloat.infinity))
        view.configuration.textContainerInset = UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 10)
        let after = view.sizeThatFits(CGSize(width: 176, height: CGFloat.infinity))
        XCTAssertEqual(after.width - before.width, 16, accuracy: 0.5)
        XCTAssertEqual(after.height - before.height, 12, accuracy: 0.5)
    }

    func testMeasurementDoesNotMutateFrameOrConstraints() throws {
        let view = try label(repeatCount: 10)
        view.frame = CGRect(x: 7, y: 9, width: 400, height: 3)
        let constraint = view.heightAnchor.constraint(lessThanOrEqualToConstant: 500)
        constraint.isActive = true
        let frame = view.frame
        let constraints = view.constraints
        let narrow = view.sizeThatFits(CGSize(width: 90, height: 1))
        let wide = view.sizeThatFits(CGSize(width: 300, height: 1))
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertEqual(view.frame, frame)
        XCTAssertEqual(view.constraints, constraints)
    }

    func testPreferredWidthOnlyAffectsIntrinsicHeight() throws {
        let view = try label(repeatCount: 10)
        view.bounds.size = CGSize(width: 300, height: 1)
        view.preferredMaxLayoutWidth = 90
        XCTAssertEqual(view.intrinsicContentSize.height, view.sizeThatFits(CGSize(width: 90, height: 1)).height)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, view.sizeThatFits(CGSize(width: 300, height: 1)).height)
    }

    func testRequiredFittingWidthIgnoresOldBoundsAndPreferredWidth() throws {
        let view = try label(repeatCount: 10)
        view.bounds.size = CGSize(width: 300, height: 1)
        view.preferredMaxLayoutWidth = 280
        let measured = view.systemLayoutSizeFitting(
            CGSize(width: 100, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        XCTAssertEqual(measured.width, 100)
        XCTAssertEqual(measured.height, view.sizeThatFits(CGSize(width: 100, height: CGFloat.infinity)).height)
    }

    func testWidthChangesAndDocumentReplacementDoNotLeaveStaleSize() throws {
        let view = try label(repeatCount: 12)
        view.bounds.size.width = 0
        view.layoutIfNeeded()
        let ideal = view.intrinsicContentSize
        view.bounds.size.width = 90
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let narrow = view.intrinsicContentSize
        view.bounds.size.width = 300
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertLessThan(view.intrinsicContentSize.height, narrow.height)
        view.bounds.size.width = 90
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.intrinsicContentSize, narrow)
        XCTAssertGreaterThan(narrow.height, ideal.height)
        view.document = try label("短").document
        XCTAssertLessThan(view.intrinsicContentSize.height, narrow.height)
        view.document = nil
        XCTAssertEqual(view.intrinsicContentSize, .zero)
    }

    func testAlignmentAndWritingDirectionAffectLineGeometry() throws {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.baseWritingDirection = .rightToLeft
        let view = try label()
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "مرحبا", attributes: [.font: UIFont.systemFont(ofSize: 20), .paragraphStyle: style]
        ))
        let layout = view.measuredLayout(width: 250)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertGreaterThan(layout.lines[0].baseline.x, 150)
    }

    func testDrawingActuallyProducesColoredPixelsAndClips() throws {
        let view = try label()
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "MMMM\nMMMM\nMMMM", attributes: [
                .font: UIFont.systemFont(ofSize: 30),
                .foregroundColor: UIColor.red
            ]
        ))
        view.frame = CGRect(x: 0, y: 0, width: 130, height: 34)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 150, height: 70), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 70))
            view.layer.render(in: context.cgContext)
        }
        let data = try XCTUnwrap(image.cgImage?.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let bytesPerRow = try XCTUnwrap(image.cgImage?.bytesPerRow)
        var changed = 0
        var colored = 0
        for y in 0 ..< 70 {
            for x in 0 ..< 150 {
                let offset = y * bytesPerRow + x * 4
                let isWhite = bytes[offset] == 255 && bytes[offset + 1] == 255 && bytes[offset + 2] == 255
                if !isWhite {
                    changed += 1
                    if bytes[offset] != bytes[offset + 1] || bytes[offset + 1] != bytes[offset + 2] {
                        colored += 1
                    }
                    XCTAssertLessThan(y, 34)
                    XCTAssertLessThan(x, 130)
                }
            }
        }
        XCTAssertGreaterThan(changed, 50)
        XCTAssertGreaterThan(colored, 50)
    }
}
