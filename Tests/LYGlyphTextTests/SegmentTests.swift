@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class SegmentTests: XCTestCase {
    private func image(id: String = "image") -> LYGlyphTextAttachment {
        .init(id: id, image: UIImage(), size: CGSize(width: 24, height: 32), alignment: .top)
    }

    private func view(id: String = "view") -> LYGlyphTextViewAttachment {
        .init(id: id, viewID: "badge", size: CGSize(width: 30, height: 20), alignment: .center)
    }

    func testMixedSegmentsUseUTF16LocationsAndIndependentActions() throws {
        let document = try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "😀"), actionID: "repeat"),
            .image(image(), actionID: "repeat"),
            .text(NSAttributedString(string: "e\u{301}"), actionID: "repeat"),
            .view(view(), actionID: "repeat")
        ])
        XCTAssertEqual(document.string, "😀\u{FFFC}e\u{301}\u{FFFC}")
        XCTAssertEqual(document.attachments.keys.sorted(), [2])
        XCTAssertEqual(document.viewAttachments.keys.sorted(), [5])
        XCTAssertEqual(document.actions.map(\.actionID), Array(repeating: "repeat", count: 4))
        XCTAssertEqual(document.actions.map(\.range), [
            NSRange(location: 0, length: 2), NSRange(location: 2, length: 1),
            NSRange(location: 3, length: 2), NSRange(location: 5, length: 1)
        ])
    }

    func testDefaultAssociatedArgumentsAndEmptyUnactedText() throws {
        let document = try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "")), .text(NSAttributedString(string: "a")),
            .image(image()), .view(view())
        ])
        XCTAssertEqual(document.string, "a\u{FFFC}\u{FFFC}")
        XCTAssertTrue(document.actions.isEmpty)
        let empty = try LYGlyphTextDocument(segments: [])
        XCTAssertTrue(empty.string.isEmpty)
        XCTAssertTrue(empty.styleRuns.isEmpty)
        XCTAssertTrue(empty.attachments.isEmpty)
        XCTAssertTrue(empty.viewAttachments.isEmpty)
    }

    func testUnstyledAttachmentsDoNotInheritPrecedingTextFontOrColor() throws {
        let document = try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "A", attributes: [
                .font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.systemRed
            ])),
            .image(image()), .view(view())
        ])
        let textRun = try XCTUnwrap(document.styleRuns.first { NSLocationInRange(0, $0.range) })
        XCTAssertEqual(textRun.font?.pointSize, 52)
        XCTAssertEqual(textRun.color, .systemRed)
        for location in [1, 2] {
            let placeholderRun = try XCTUnwrap(document.styleRuns.first { NSLocationInRange(location, $0.range) })
            XCTAssertNil(placeholderRun.font)
            XCTAssertNil(placeholderRun.color)
        }
    }

    func testExplicitPressedStyleKeepsOtherCaseDefaults() throws {
        let style = LYGlyphTextPressedStyle(foregroundColor: .systemRed, backgroundColor: nil)
        let segments: [LYGlyphTextSegment] = [
            .text(NSAttributedString(string: "a"), pressedStyle: style),
            .image(image(), pressedStyle: style), .view(view(), pressedStyle: style)
        ]
        for segment in segments {
            switch segment {
            case let .text(_, actionID, pressedStyle),
                 let .image(_, _, actionID, pressedStyle),
                 let .view(_, _, actionID, pressedStyle):
                XCTAssertNil(actionID)
                XCTAssertEqual(pressedStyle.foregroundColor, .systemRed)
                XCTAssertNil(pressedStyle.backgroundColor)
            }
        }
        XCTAssertEqual(try LYGlyphTextDocument(segments: segments).string, "a\u{FFFC}\u{FFFC}")
    }

    func testEmptyActedTextUsesCommonRangeValidation() {
        let range = NSRange(location: 1, length: 0)
        XCTAssertThrowsError(try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "a")), .text(NSAttributedString(string: ""), actionID: "tap")
        ])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidActionRange(range: range))
        }
        XCTAssertThrowsError(try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: ""), actionID: "")
        ])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .emptyActionID(range: NSRange(location: 0, length: 0)))
        }
    }

    func testActionCannotSplitClusterAcrossSegmentBoundary() {
        let range = NSRange(location: 0, length: 1)
        XCTAssertThrowsError(try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "e"), actionID: "tap"), .text(NSAttributedString(string: "\u{301}"))
        ])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .actionRangeSplitsComposedCharacter(range: range))
        }
    }

    func testSegmentSnapshotOccursAtDocumentInitialization() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.baseWritingDirection = .rightToLeft
        let input = NSMutableAttributedString(string: "before", attributes: [
            .font: UIFont.systemFont(ofSize: 27), .foregroundColor: UIColor.systemPink, .paragraphStyle: paragraph
        ])
        let segment = LYGlyphTextSegment.text(input, actionID: "tap")
        input.mutableString.setString("😀 now")
        let document = try LYGlyphTextDocument(segments: [segment])
        input.mutableString.setString("after")
        paragraph.alignment = .left
        paragraph.baseWritingDirection = .leftToRight
        XCTAssertEqual(document.string, "😀 now")
        XCTAssertEqual(document.actions.first?.range, NSRange(location: 0, length: 6))
        let run = try XCTUnwrap(document.styleRuns.first)
        XCTAssertEqual(run.font?.pointSize, 27)
        XCTAssertEqual(run.color, .systemPink)
        XCTAssertEqual(run.alignment, .right)
        XCTAssertEqual(run.writingDirection, .rightToLeft)
    }

    func testPlaceholderAttributesStylesMetricsAndMeasurementMatchDesignatedInitializer() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 31), .foregroundColor: UIColor.systemTeal, .paragraphStyle: paragraph
        ]
        let pressed = LYGlyphTextPressedStyle(foregroundColor: .systemYellow, backgroundColor: .systemBlue)
        let image = image()
        let view = view()
        let document = try LYGlyphTextDocument(segments: [
            .image(image, attributes: attributes, actionID: "image", pressedStyle: pressed),
            .view(view, attributes: attributes, actionID: "view", pressedStyle: pressed)
        ])
        paragraph.alignment = .left
        let expectedParagraph = NSMutableParagraphStyle()
        expectedParagraph.alignment = .right
        let expected = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{FFFC}", attributes: [
                .font: UIFont.systemFont(ofSize: 31), .foregroundColor: UIColor.systemTeal,
                .paragraphStyle: expectedParagraph
            ]),
            attachments: [0: image],
            viewAttachments: [1: view]
        )
        for run in document.styleRuns {
            XCTAssertEqual(run.font?.pointSize, 31)
            XCTAssertEqual(run.color, .systemTeal)
            XCTAssertEqual(run.alignment, .right)
        }
        XCTAssertEqual(document.actions.map(\.pressedStyle.foregroundColor), [.systemYellow, .systemYellow])
        XCTAssertEqual(document.actions.map(\.pressedStyle.backgroundColor), [.systemBlue, .systemBlue])
        let label = LYGlyphTextLabel(frame: .zero)
        let expectedLabel = LYGlyphTextLabel(frame: .zero)
        var factoryCalls = 0
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            factoryCalls += 1
            return UIView()
        }
        label.document = document
        expectedLabel.document = expected
        for width: CGFloat in [40, 120, 240] {
            let layout = label.measuredLayout(width: width)
            let expectedLayout = expectedLabel.measuredLayout(width: width)
            XCTAssertEqual(layout.size, expectedLayout.size)
            XCTAssertEqual(layout.attachments.map(\.rect), expectedLayout.attachments.map(\.rect))
            XCTAssertEqual(layout.viewAttachments.map(\.rect), expectedLayout.viewAttachments.map(\.rect))
            XCTAssertEqual(layout.attachments.first?.rect.size, image.size)
            XCTAssertEqual(layout.viewAttachments.first?.rect.size, view.size)
        }
        _ = label.sizeThatFits(CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude))
        _ = label.systemLayoutSizeFitting(
            CGSize(width: 120, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertTrue(label.subviews.isEmpty)
    }

    func testBuilderRejectsOrphanPlaceholderAndStandardAttachment() {
        XCTAssertThrowsError(try LYGlyphTextDocument(segments: [.text(NSAttributedString(string: "😀\u{FFFC}"))])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 2))
        }
        for segment in [
            LYGlyphTextSegment.text(NSAttributedString(string: "a", attributes: [.attachment: NSTextAttachment()])),
            .image(image(), attributes: [.attachment: NSTextAttachment()]),
            .view(view(), attributes: [.attachment: NSTextAttachment()])
        ] {
            XCTAssertThrowsError(try LYGlyphTextDocument(segments: [segment])) {
                XCTAssertEqual(
                    $0 as? LYGlyphTextDocumentError,
                    .unsupportedAttachment(range: NSRange(location: 0, length: 1))
                )
            }
        }
    }

    func testBuilderRejectsDuplicateIDsAcrossAttachmentKinds() {
        XCTAssertThrowsError(try LYGlyphTextDocument(segments: [.image(image(id: "same")), .view(view(id: "same"))])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .duplicateAttachmentID(id: "same"))
        }
    }

    func testBuilderRejectsCombiningMarkAfterEitherAttachmentKind() {
        for segment in [LYGlyphTextSegment.image(image()), .view(view())] {
            XCTAssertThrowsError(try LYGlyphTextDocument(segments: [
                segment,
                .text(NSAttributedString(string: "\u{301}"))
            ])) {
                XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: 0))
            }
        }
    }
}
