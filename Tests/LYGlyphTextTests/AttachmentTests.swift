import CoreText
@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class AttachmentTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 10, width: 10, height: 10))
        }
    }

    private func attachment(
        id: String = "image", size: CGSize = CGSize(width: 30, height: 40),
        alignment: LYGlyphTextAttachmentAlignment = .bottom
    ) -> LYGlyphTextAttachment {
        LYGlyphTextAttachment(id: id, image: image(), size: size, alignment: alignment, alternativeText: "红蓝图")
    }

    private func label(
        _ string: String = "A\u{FFFC}B", attachments: [Int: LYGlyphTextAttachment]? = nil
    ) throws -> LYGlyphTextLabel {
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: string, attributes: [.font: font]),
            attachments: attachments ?? [1: attachment()]
        )
        return view
    }

    func testUTF16PlacementAndSnapshotIsolation() throws {
        let input = NSMutableAttributedString(string: "😀\u{FFFC}", attributes: [.font: font])
        let document = try LYGlyphTextDocument(attributedText: input, attachments: [2: attachment()])
        input.mutableString.setString("changed")
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = document
        let placement = try XCTUnwrap(view.measuredLayout(width: 200).attachments.first)
        XCTAssertEqual(document.string, "😀\u{FFFC}")
        XCTAssertEqual(placement.sourceLocation, 2)
        XCTAssertEqual(placement.attachment.id, "image")
        XCTAssertEqual(placement.attachment.alternativeText, "红蓝图")
        XCTAssertEqual(placement.rect.size, CGSize(width: 30, height: 40))
    }

    func testInvalidLocationsSizesAndDuplicateIDsFail() {
        for location in [-1, 0, 2, Int.max] {
            XCTAssertThrowsError(try label("A\u{FFFC}", attachments: [location: attachment()])) {
                XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: location))
            }
        }
        for size in [
            CGSize(width: 0, height: 10),
            CGSize(width: -1, height: 10),
            CGSize(width: 10, height: CGFloat.infinity),
            CGSize(width: CGFloat.nan, height: 10)
        ] {
            XCTAssertThrowsError(try label(attachments: [1: attachment(size: size)])) {
                XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentSize(id: "image"))
            }
        }
        XCTAssertThrowsError(try label("\u{FFFC}\u{FFFC}", attachments: [0: attachment(), 1: attachment()])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .duplicateAttachmentID(id: "image"))
        }
        XCTAssertThrowsError(try label("\u{FFFC}\u{FFFC}", attachments: [0: attachment()])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 1))
        }
    }

    func testAlignmentUsesPlaceholderFontAndDeclaredSize() throws {
        for alignment in [LYGlyphTextAttachmentAlignment.top, .center, .bottom] {
            let view = try label(attachments: [1: attachment(alignment: alignment)])
            let layout = view.measuredLayout(width: 200)
            let line = try XCTUnwrap(layout.lines.first)
            let rect = try XCTUnwrap(layout.attachments.first).rect
            let top = line.baseline.y - font.ascender
            let bottom = line.baseline.y - font.descender
            switch alignment {
            case .top: XCTAssertEqual(rect.minY, top, accuracy: 0.01)
            case .center: XCTAssertEqual(rect.midY, (top + bottom) / 2, accuracy: 0.01)
            case .bottom: XCTAssertEqual(rect.maxY, bottom, accuracy: 0.01)
            }
            XCTAssertGreaterThanOrEqual(layout.size.height + 0.5, rect.maxY)
            XCTAssertGreaterThanOrEqual(rect.minY, -0.5)
        }
    }

    func testHiddenTallAttachmentDoesNotAffectTruncatedHeightOrToken() throws {
        let view = try label("\u{FFFC}后续内容需要省略", attachments: [0: attachment(size: CGSize(width: 120, height: 160))])
        view.configuration.numberOfLines = 1
        let layout = view.measuredLayout(width: 30)
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertTrue(layout.attachments.isEmpty)
        XCTAssertLessThan(layout.size.height, 40)
        let line = try XCTUnwrap(layout.lines.first)
        XCTAssertTrue(line.visibleSourceRanges.isEmpty)
        XCTAssertNotNil(line.truncationTokenRange)
        for run in try XCTUnwrap(CTLineGetGlyphRuns(line.text) as? [CTRun]) {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            XCTAssertNil(attributes[kCTRunDelegateAttributeName])
        }
    }

    func testStandardAttachmentAndNonStandalonePlaceholderAreRejected() {
        let input = NSAttributedString(string: "\u{FFFC}", attributes: [.attachment: NSTextAttachment()])
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: input, attachments: [0: attachment()])) {
            XCTAssertEqual(
                $0 as? LYGlyphTextDocumentError,
                .unsupportedAttachment(range: NSRange(location: 0, length: 1))
            )
        }
        XCTAssertThrowsError(try label("\u{FFFC}\u{301}", attachments: [0: attachment()])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: 0))
        }
    }

    func testConsecutiveLeadingTrailingAttachmentsAndMixedFont() throws {
        let input = NSMutableAttributedString(string: "\u{FFFC}\u{FFFC}中文😀\u{FFFC}", attributes: [.font: font])
        let source = input.string as NSString
        input.addAttribute(.font, value: UIFont.systemFont(ofSize: 36), range: NSRange(location: 1, length: 1))
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(attributedText: input, attachments: [
            0: attachment(id: "first", size: CGSize(width: 25, height: 24), alignment: .top),
            1: attachment(id: "second", size: CGSize(width: 25, height: 24), alignment: .top),
            source.length - 1: attachment(id: "last")
        ])
        let layout = view.measuredLayout(width: 300)
        XCTAssertEqual(layout.attachments.count, 3)
        let first = try XCTUnwrap(layout.attachments.first)
        let second = layout.attachments[1]
        XCTAssertEqual(second.rect.minX - first.rect.minX, 25, accuracy: 0.01)
        XCTAssertLessThan(second.rect.minY, first.rect.minY)
        XCTAssertEqual(layout.attachments.last?.sourceLocation, source.length - 1)
        let wrapped = view.measuredLayout(width: 60)
        XCTAssertEqual(wrapped.attachments.count, 3)
        XCTAssertGreaterThan(wrapped.lines.count, 1)
    }

    func testRTLPreservesImageOrderAndTruncatedSourceLocations() throws {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .rightToLeft
        style.alignment = .right
        let input = NSAttributedString(string: "\u{FFFC}\u{FFFC} مرحبا بالعالم مرحبا", attributes: [
            .font: font, .paragraphStyle: style
        ])
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(attributedText: input, attachments: [
            0: attachment(id: "first"), 1: attachment(id: "second")
        ])
        let layout = view.measuredLayout(width: 260)
        let first = try XCTUnwrap(layout.attachments.first { $0.sourceLocation == 0 })
        let second = try XCTUnwrap(layout.attachments.first { $0.sourceLocation == 1 })
        XCTAssertGreaterThan(first.rect.minX, second.rect.minX)
        view.configuration.numberOfLines = 1
        let truncated = view.measuredLayout(width: 160)
        XCTAssertEqual(truncated.attachments.count, 2)
        for placement in truncated.attachments {
            XCTAssertTrue(truncated.lines[0].visibleSourceRanges.contains { NSLocationInRange(
                placement.sourceLocation,
                $0
            ) })
        }
    }

    func testTruncatedSecondLineKeepsOriginalAttachmentLocation() throws {
        let view = try label("first\n\u{FFFC}ABCD\nthird", attachments: [6: attachment()])
        view.configuration.numberOfLines = 2
        let layout = view.measuredLayout(width: 120)
        XCTAssertEqual(layout.lines.count, 2)
        XCTAssertNotNil(layout.lines.last?.truncationTokenRange)
        let placement = try XCTUnwrap(layout.attachments.first)
        XCTAssertEqual(placement.sourceLocation, 6)
        XCTAssertEqual(layout.lines[1].sourceOffset, 6)
        XCTAssertEqual(placement.rect.size, CGSize(width: 30, height: 40))
    }

    func testRemovedTallTailMatchesEquivalentTextOnlyTruncation() throws {
        let view = try label("AB\u{FFFC}后面的内容", attachments: [2: attachment(size: CGSize(width: 25, height: 180))])
        view.configuration.numberOfLines = 1
        let tokenWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
            NSAttributedString(string: "AB…", attributes: [.font: font])
        ), nil, nil, nil)) + 0.1
        let result = view.measuredLayout(width: tokenWidth)
        let plain = LYGlyphTextLabel(frame: .zero)
        plain.configuration.numberOfLines = 1
        plain.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "AB后面的内容", attributes: [.font: font]
        ))
        XCTAssertTrue(result.attachments.isEmpty)
        XCTAssertEqual(result.size.height, plain.measuredLayout(width: tokenWidth).size.height, accuracy: 0.5)
    }

    func testOversizedImageIsNotShrunkAndZeroWidthHasNoPlacements() throws {
        let view = try label("\u{FFFC}", attachments: [0: attachment(size: CGSize(width: 200, height: 120))])
        for width: CGFloat in [1, 25, 80, 240] {
            let layout = view.measuredLayout(width: width)
            XCTAssertEqual(try XCTUnwrap(layout.attachments.first).rect.size, CGSize(width: 200, height: 120))
            XCTAssertGreaterThanOrEqual(layout.size.height, 120)
        }
        XCTAssertTrue(view.measuredLayout(width: 0).attachments.isEmpty)
        XCTAssertEqual(view.measuredLayout(width: nil).size.width, 200, accuracy: 0.5)
    }

    func testInsetsWidthsReplacementAndMeasurementHaveNoSideEffects() throws {
        let view = try label("\u{FFFC}文字后面\u{FFFC}内容结束", attachments: [0: attachment(id: "a"), 5: attachment(id: "b")])
        let original = view.measuredLayout(width: 120)
        view.configuration.textContainerInset = UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 10)
        let inset = view.measuredLayout(width: 136)
        XCTAssertEqual(inset.size.width - original.size.width, 16, accuracy: 0.5)
        XCTAssertEqual(inset.size.height - original.size.height, 12, accuracy: 0.5)
        XCTAssertEqual(inset.attachments.first?.rect.minX, (original.attachments.first?.rect.minX ?? 0) + 6)
        view.frame = CGRect(x: 4, y: 5, width: 350, height: 2)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let frame = view.frame
        for width: CGFloat in [0, 100, 280, 100, .infinity] {
            let size = view.sizeThatFits(CGSize(width: width, height: 1))
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
        }
        XCTAssertEqual(view.measuredLayout(width: 136).size, inset.size)
        XCTAssertEqual(view.frame, frame)
        XCTAssertTrue(view.constraints.isEmpty)
        XCTAssertTrue(view.subviews.isEmpty)
        let fitted = view.systemLayoutSizeFitting(
            CGSize(width: 136, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        XCTAssertEqual(fitted.height, inset.size.height)
        view.document = try label("\u{FFFC}", attachments: [0: attachment(size: CGSize(width: 30, height: 180))])
            .document
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 136, height: 1)).height, inset.size.height)
        XCTAssertEqual(view.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        view.document = nil
        XCTAssertTrue(view.measuredLayout(width: 136).attachments.isEmpty)
        XCTAssertEqual(view.intrinsicContentSize, CGSize(width: 16, height: 12))
    }

    func testUIKitAutomaticHeightAndSwiftUIAgree() throws {
        let view = try label(
            "文字\u{FFFC}继续\n图片\u{FFFC}末尾",
            attachments: [2: attachment(id: "a"), 8: attachment(id: "b")]
        )
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 1000))
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        for limit in [0, 1, 2] {
            view.configuration.numberOfLines = limit
            for width: CGFloat in [160, 260, 100, 160] {
                container.bounds.size.width = width
                container.setNeedsLayout()
                for _ in 0 ..< 4 {
                    container.layoutIfNeeded()
                }
                let measured = view.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
                XCTAssertEqual(view.bounds.height, measured.height, accuracy: 0.5)
                let host = UIHostingController(rootView: LYGlyphTextView(
                    document: view.document, configuration: .init(numberOfLines: limit)
                ).frame(width: width))
                let size = host.sizeThatFits(in: CGSize(width: width, height: 10000))
                XCTAssertEqual(size.height, measured.height, accuracy: 1 / max(1, host.traitCollection.displayScale))
            }
        }
    }

    func testDelegateReleasesMetricsWhenCoreTextReleasesDelegate() {
        weak var weakMetrics: AttachmentMetrics?
        autoreleasepool {
            let metrics = AttachmentMetrics(
                size: CGSize(width: 20, height: 30),
                ascender: 18,
                descender: -4,
                alignment: .bottom
            )
            weakMetrics = metrics
            let delegate = metrics.makeDelegate()
            withExtendedLifetime(delegate) { XCTAssertNotNil(weakMetrics) }
        }
        XCTAssertNil(weakMetrics)
    }

    func testSmallAttachmentOnlyLinePreservesPlaceholderFontRegion() throws {
        for alignment in [LYGlyphTextAttachmentAlignment.top, .center, .bottom] {
            let view = try label("\u{FFFC}", attachments: [
                0: attachment(size: CGSize(width: 10, height: 2), alignment: alignment)
            ])
            let layout = view.measuredLayout(width: 100)
            let baseline = try XCTUnwrap(layout.lines.first).baseline.y
            XCTAssertGreaterThanOrEqual(baseline, font.ascender - 0.5)
            XCTAssertGreaterThanOrEqual(layout.size.height - baseline, -font.descender - 0.5)
        }
    }

    func testNoRoomForTokenDoesNotRetainHiddenImageHeight() throws {
        let view = try label("\u{FFFC}\nnext", attachments: [
            0: attachment(size: CGSize(width: 60, height: 180))
        ])
        view.configuration.numberOfLines = 1
        let layout = view.measuredLayout(width: 1)
        XCTAssertTrue(layout.attachments.isEmpty)
        XCTAssertTrue(try XCTUnwrap(layout.lines.first).visibleSourceRanges.isEmpty)
        XCTAssertNil(layout.lines.first?.truncationTokenRange)
        XCTAssertLessThan(layout.size.height, 40)
    }

    func testVisibleTallImageRetainsHeightAndPreviousBaselineAfterTruncation() throws {
        let view = try label("\u{FFFC}\n\u{FFFC}AB\nthird", attachments: [
            0: attachment(id: "first", size: CGSize(width: 20, height: 90)),
            2: attachment(id: "second", size: CGSize(width: 20, height: 120))
        ])
        let full = view.measuredLayout(width: 140)
        view.configuration.numberOfLines = 2
        let truncated = view.measuredLayout(width: 140)
        XCTAssertEqual(truncated.attachments.count, 2)
        XCTAssertEqual(truncated.lines[0].baseline, full.lines[0].baseline)
        for placement in truncated.attachments {
            XCTAssertGreaterThanOrEqual(placement.rect.minY, -0.5)
            XCTAssertLessThanOrEqual(placement.rect.maxY, truncated.size.height + 0.5)
        }
        XCTAssertGreaterThanOrEqual(truncated.size.height, 210)
        XCTAssertNotNil(truncated.lines.last?.truncationTokenRange)
    }

    func testAttachmentImmediatelyBeforeGeneratedTokenHasOnlySourceLocation() throws {
        let view = try label("\u{FFFC}\nmore", attachments: [0: attachment()])
        view.configuration.numberOfLines = 1
        let result = view.measuredLayout(width: 70)
        XCTAssertEqual(result.attachments.count, 1)
        XCTAssertEqual(result.lines[0].visibleSourceRanges, [NSRange(location: 0, length: 1)])
        let tokenRange = try XCTUnwrap(result.lines[0].truncationTokenRange)
        XCTAssertEqual(tokenRange.location, 1)
        for run in try XCTUnwrap(CTLineGetGlyphRuns(result.lines[0].text) as? [CTRun]) {
            if NSLocationInRange(tokenRange.location, NSRange(
                location: CTRunGetStringRange(run).location, length: CTRunGetStringRange(run).length
            )) {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                XCTAssertNil(attributes[kCTRunDelegateAttributeName])
                XCTAssertNil(attributes[AttachmentMetrics.locationKey])
            }
        }
    }

    func testAllInvalidDimensionComponentsAndDefaultValues() throws {
        let value = LYGlyphTextAttachment(id: "default", image: image(), size: CGSize(width: 4, height: 5))
        XCTAssertEqual(value.alignment, .bottom)
        XCTAssertNil(value.alternativeText)
        for dimension: CGFloat in [0, -1, .infinity, -.infinity, .nan] {
            for size in [CGSize(width: dimension, height: 10), CGSize(width: 10, height: dimension)] {
                XCTAssertThrowsError(try label(attachments: [1: attachment(size: size)])) {
                    XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentSize(id: "image"))
                }
            }
        }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: ""), attachments: [0: value]
        ))
    }

    func testSoftWrappedRTLTruncationAfterTallAttachment() throws {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .rightToLeft
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "AB\u{FFFC} \u{FFFC} مرحبا بالعالم مرحبا بالعالم مرحبا بالعالم",
            attributes: [.font: font, .paragraphStyle: style]
        ), attachments: [
            2: attachment(id: "tall", size: CGSize(width: 60, height: 100)),
            4: attachment(id: "rtl", size: CGSize(width: 30, height: 40))
        ])
        let full = view.measuredLayout(width: 115)
        XCTAssertGreaterThan(full.lines.count, 2)
        XCTAssertTrue(full.lines[0].visibleSourceRanges.contains { NSLocationInRange(2, $0) })
        XCTAssertTrue(full.lines[1].visibleSourceRanges.contains { NSLocationInRange(4, $0) })
        view.configuration.numberOfLines = 2
        let truncated = view.measuredLayout(width: 115)
        XCTAssertEqual(truncated.lines[0].baseline, full.lines[0].baseline)
        XCTAssertGreaterThan(truncated.lines[1].sourceOffset, 0)
        XCTAssertEqual(Set(truncated.attachments.map(\.sourceLocation)), [2, 4])
        for placement in truncated.attachments {
            XCTAssertLessThanOrEqual(placement.rect.maxY, truncated.size.height + 0.5)
        }
    }

    func testDefaultFontTraitChangesRecomputeAttachmentAlignment() throws {
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "\u{FFFC}"), attachments: [
            0: attachment(size: CGSize(width: 10, height: 6), alignment: .top)
        ])
        var heights: [CGFloat] = []
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let layout = ResolvedText(document: document, traits: traits).layout(width: 200, insets: .zero, scale: 2)
            let rect = try XCTUnwrap(layout.attachments.first).rect
            let baseline = try XCTUnwrap(layout.lines.first).baseline.y
            XCTAssertEqual(
                baseline - rect.minY, UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).ascender,
                accuracy: 0.01
            )
            heights.append(layout.size.height)
        }
        XCTAssertGreaterThan(heights[1], heights[0])
    }
}
