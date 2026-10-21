import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class SelectionTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 24)

    private func layout(_ string: String, width: CGFloat = 400) throws -> (LYGlyphTextLayout, String) {
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: string, attributes: [.font: font]))
        let value = ResolvedText(document: doc, traits: UITraitCollection(displayScale: 2)).layout(
            width: width, insets: .zero, scale: 2
        )
        return (value, string)
    }

    private func cellRect(_ layout: LYGlyphTextLayout, _ string: String, at location: Int) throws -> CGRect {
        let range = (string as NSString).rangeOfComposedCharacterSequence(at: location)
        return try XCTUnwrap(layout.visibleTextFragments(in: range, source: string).first?.rect)
    }

    private func hosted(_ text: NSAttributedString, actions: [LYGlyphTextAction] = []) throws
        -> (UIWindow, LYGlyphTextLabel)
    {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 360, height: 120))
        label.document = try LYGlyphTextDocument(attributedText: text, actions: actions)
        label.isSelectable = true
        window.addSubview(label)
        label.layoutIfNeeded()
        return (window, label)
    }

    // MARK: - Geometry

    func testClosestBoundaryUsesCharacterMidlineAndNearestLine() throws {
        let (value, string) = try layout("Hello world")
        let geometry = SelectionGeometry(layout: value, source: string)
        let w = try cellRect(value, string, at: 6)
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: w.minX + 1, y: w.midY)), 6)
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: w.maxX - 1, y: w.midY)), 7)
        // 行外的点归到垂直方向最近的行。
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: w.minX + 1, y: w.maxY + 200)), 6)
        let h = try cellRect(value, string, at: 0)
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: h.minX - 50, y: h.midY)), 0)
        XCTAssertEqual(geometry.visibleRange, NSRange(location: 0, length: 11))
    }

    func testRightToLeftBoundaryIsMirrored() throws {
        let (value, string) = try layout("مرحبا")
        let geometry = SelectionGeometry(layout: value, source: string)
        let first = try cellRect(value, string, at: 0)
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: first.maxX - 1, y: first.midY)), 0)
        XCTAssertEqual(geometry.closestBoundary(to: CGPoint(x: first.minX + 1, y: first.midY)), 1)
    }

    func testWordRangeAndClampKeepComposedCharacters() throws {
        let (value, string) = try layout("Hello world 👨‍👩‍👧‍👦 e\u{301}")
        let geometry = SelectionGeometry(layout: value, source: string)
        let w = try cellRect(value, string, at: 8)
        XCTAssertEqual(geometry.wordRange(at: CGPoint(x: w.midX, y: w.midY)), NSRange(location: 6, length: 5))
        let family = (string as NSString).range(of: "👨‍👩‍👧‍👦")
        XCTAssertEqual(geometry.clamped(NSRange(location: family.location + 2, length: 1)), family)
        XCTAssertNil(geometry.clamped(NSRange(location: 3, length: 0)))
        XCTAssertNil(geometry.clamped(NSRange(location: 400, length: 2)))
        let rects = geometry.rects(for: NSRange(location: 0, length: 11))
        XCTAssertEqual(rects.count, 1)
        let carets = try XCTUnwrap(geometry.carets(for: NSRange(location: 6, length: 5)))
        XCTAssertEqual(carets.start.midX, try cellRect(value, string, at: 6).minX, accuracy: 0.01)
        XCTAssertEqual(carets.end.midX, try cellRect(value, string, at: 10).maxX, accuracy: 0.01)
    }

    // MARK: - Label

    func testSelectedRangeRequiresSelectableAndExpandsGraphemes() throws {
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "a👨‍👩‍👧‍👦b"))
        label.selectedRange = NSRange(location: 0, length: 1)
        XCTAssertNil(label.selectedRange)
        label.isSelectable = true
        label.selectedRange = NSRange(location: 2, length: 1)
        XCTAssertEqual(label.selectedRange, NSRange(location: 1, length: 11))
        XCTAssertEqual(label.selectedText, "👨‍👩‍👧‍👦")
        label.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertNil(label.selectedRange)
    }

    func testSelectedTextUsesAttachmentAlternativeTextAndCopyWritesPasteboard() throws {
        let image = try LYGlyphTextAttachment(
            id: "star", image: XCTUnwrap(UIImage(systemName: "star")), size: CGSize(width: 20, height: 20),
            alternativeText: "星星"
        )
        let decorative = try LYGlyphTextAttachment(
            id: "dot",
            image: XCTUnwrap(UIImage(systemName: "circle")),
            size: CGSize(width: 8, height: 8)
        )
        let (window, label) = try hosted(NSAttributedString(string: ""))
        label.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "图\u{FFFC}文\u{FFFC}", attributes: [.font: font]),
            attachments: [1: image, 3: decorative]
        )
        label.selectedRange = NSRange(location: 0, length: 4)
        XCTAssertEqual(label.selectedText, "图星星文")
        XCTAssertTrue(label.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil))
        XCTAssertFalse(label.canPerformAction(#selector(UIResponder.paste(_:)), withSender: nil))
        UIPasteboard.general.string = "before"
        label.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "图星星文")
        withExtendedLifetime(window) {}
    }

    func testLongPressSelectsWordButYieldsToActions() throws {
        let text = NSAttributedString(string: "Tap here or select words", attributes: [.font: font])
        let (window, label) = try hosted(
            text,
            actions: [.init(actionID: "tap", range: NSRange(location: 0, length: 8))]
        )
        label.onAction = { _ in }
        var changes: [NSRange?] = []
        label.onSelectionChange = { changes.append($0) }
        let layout = label.measuredLayout(width: label.bounds.width)
        let source = text.string
        let action = try cellRect(layout, source, at: 2)
        XCTAssertFalse(label.beginSelection(at: CGPoint(x: action.midX, y: action.midY)))
        XCTAssertNil(label.selectedRange)
        let select = try cellRect(layout, source, at: 13)
        XCTAssertTrue(label.beginSelection(at: CGPoint(x: select.midX, y: select.midY)))
        XCTAssertEqual(label.selectedRange, NSRange(location: 12, length: 6))
        XCTAssertEqual(label.selectedText, "select")
        XCTAssertTrue(label.isFirstResponder)
        XCTAssertEqual(label.subviews.compactMap { $0 as? SelectionHandleView }.count, 2)
        XCTAssertEqual(changes.last, NSRange(location: 12, length: 6))

        let end = try cellRect(layout, source, at: (source as NSString).length - 1)
        label.moveSelectionHandle(.end, to: CGPoint(x: end.maxX, y: end.midY))
        XCTAssertEqual(label.selectedText, "select words")
        // 拖动开始拖柄越过结束端时交换，选区仍有效。
        label.moveSelectionHandle(.start, to: CGPoint(x: end.maxX, y: end.midY))
        XCTAssertNotNil(label.selectedRange)
        withExtendedLifetime(window) {}
    }

    func testSelectionClearsOnDocumentChangeWindowRemovalAndDisable() throws {
        let text = NSAttributedString(string: "Selectable text", attributes: [.font: font])
        let (window, label) = try hosted(text)
        var changes: [NSRange?] = []
        label.onSelectionChange = { changes.append($0) }
        label.selectedRange = NSRange(location: 0, length: 10)
        label.document = try LYGlyphTextDocument(attributedText: text)
        XCTAssertNil(label.selectedRange)
        XCTAssertEqual(changes, [NSRange(location: 0, length: 10), nil])
        label.selectedRange = NSRange(location: 0, length: 4)
        label.removeFromSuperview()
        XCTAssertNil(label.selectedRange)
        XCTAssertFalse(label.isFirstResponder)
        window.addSubview(label)
        label.selectedRange = NSRange(location: 0, length: 4)
        label.isSelectable = false
        XCTAssertNil(label.selectedRange)
        XCTAssertTrue(label.subviews.compactMap { $0 as? SelectionHandleView }.isEmpty)
        XCTAssertFalse(label.canBecomeFirstResponder)
    }

    func testSelectAllSelectsVisibleTextOnly() throws {
        let text = NSAttributedString(
            string: String(repeating: "Visible words then hidden ", count: 10), attributes: [.font: font]
        )
        let (window, label) = try hosted(text)
        label.configuration.numberOfLines = 1
        label.layoutIfNeeded()
        label.selectedRange = NSRange(location: 0, length: 1)
        label.selectAll(nil)
        let range = try XCTUnwrap(label.selectedRange)
        XCTAssertEqual(range.location, 0)
        XCTAssertLessThan(range.length, (text.string as NSString).length)
        XCTAssertFalse(label.canPerformAction(#selector(UIResponder.selectAll(_:)), withSender: nil))
        withExtendedLifetime(window) {}
    }
}
