@testable import LYGlyphText
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class SelectionCopyTests: XCTestCase {
    private func hosted(_ text: NSAttributedString, attachments: [Int: LYGlyphTextAttachment] = [:]) throws
        -> (UIWindow, LYGlyphTextLabel)
    {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 360, height: 160))
        label.document = try LYGlyphTextDocument(attributedText: text, attachments: attachments)
        label.isSelectable = true
        window.addSubview(label)
        label.layoutIfNeeded()
        return (window, label)
    }

    func testCopyWritesPlainAndRichTextWithMatchingContent() throws {
        let bold = UIFont.boldSystemFont(ofSize: 22)
        let text = NSMutableAttributedString(string: "粗体 plain \u{FFFC} end", attributes: [
            .font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.red
        ])
        text.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 2))
        text.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 3, length: 5)
        )
        let image = try LYGlyphTextAttachment(
            id: "i", image: XCTUnwrap(UIImage(systemName: "star")), size: CGSize(width: 16, height: 16),
            alternativeText: "星"
        )
        let (window, label) = try hosted(text, attachments: [9: image])
        label.selectedRange = NSRange(location: 0, length: text.length)
        label.copy(nil)
        let pasteboard = UIPasteboard.general
        XCTAssertEqual(pasteboard.string, "粗体 plain 星 end")
        let data = try XCTUnwrap(pasteboard.data(forPasteboardType: UTType.rtf.identifier))
        let rich = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
        )
        XCTAssertEqual(rich.string, "粗体 plain 星 end")
        let firstFont = try XCTUnwrap(rich.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(firstFont.pointSize, 22, accuracy: 0.01)
        XCTAssertTrue(firstFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertNotNil(rich.attribute(.underlineStyle, at: 4, effectiveRange: nil))
        withExtendedLifetime(window) {}
    }

    func testAccessibilityCopyActionExistsOnlyWithSelection() throws {
        let (window, label) = try hosted(NSAttributedString(string: "可访问的选区文本"))
        func textElements() -> [TextAccessibilityElement] {
            label.setNeedsLayout()
            label.layoutIfNeeded()
            return (label.accessibilityElements ?? []).compactMap { $0 as? TextAccessibilityElement }
        }
        XCTAssertNil(try XCTUnwrap(textElements().first).accessibilityCustomActions)
        label.selectedRange = NSRange(location: 0, length: 3)
        label.selectionCopyAccessibilityName = "Copy"
        let action = try XCTUnwrap(textElements().first?.accessibilityCustomActions?.first)
        XCTAssertEqual(action.name, "Copy")
        UIPasteboard.general.string = "before"
        XCTAssertTrue(action.actionHandler?(action) ?? false)
        XCTAssertEqual(UIPasteboard.general.string, "可访问")
        withExtendedLifetime(window) {}
    }

    func testDraggingHandlesBeyondLabelClampsToVisibleBoundaries() throws {
        let string = "Drag handles beyond the label edges"
        let (window, label) = try hosted(NSAttributedString(
            string: string,
            attributes: [.font: UIFont.systemFont(ofSize: 24)]
        ))
        label.selectedRange = NSRange(location: 5, length: 7)
        label.moveSelectionHandle(.end, to: CGPoint(x: 2000, y: 2000))
        XCTAssertEqual(label.selectedRange.map(NSMaxRange), (string as NSString).length)
        label.moveSelectionHandle(.start, to: CGPoint(x: -500, y: -500))
        XCTAssertEqual(label.selectedRange, NSRange(location: 0, length: (string as NSString).length))
        for handle in label.subviews.compactMap({ $0 as? SelectionHandleView }) {
            XCTAssertTrue(label.bounds.contains(handle.frame), "\(handle.frame)")
        }
        withExtendedLifetime(window) {}
    }
}
