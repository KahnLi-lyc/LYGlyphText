@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class SelectionHandleAccessibilityTests: XCTestCase {
    private func hosted(_ string: String) throws -> (UIWindow, LYGlyphTextLabel) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 360, height: 120))
        label.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: 22)])
        )
        label.isSelectable = true
        window.addSubview(label)
        label.layoutIfNeeded()
        return (window, label)
    }

    private func handles(_ label: LYGlyphTextLabel) -> [SelectionHandleView] {
        (label.accessibilityElements ?? []).compactMap { $0 as? SelectionHandleView }
    }

    func testHandlesAppearInAccessibilityTreeOnlyWithSelection() throws {
        let (window, label) = try hosted("可调节的选区拖柄")
        XCTAssertTrue(handles(label).isEmpty)
        label.selectedRange = NSRange(location: 2, length: 2)
        label.layoutIfNeeded()
        let found = handles(label)
        XCTAssertEqual(found.map(\.accessibilityIdentifier), ["LYGlyphText.selectionStart", "LYGlyphText.selectionEnd"])
        XCTAssertEqual(found.map(\.accessibilityLabel), ["选区开始", "选区结束"])
        XCTAssertEqual(found.first?.accessibilityValue, "节的")
        XCTAssertTrue(try XCTUnwrap(found.first).accessibilityTraits.contains(.adjustable))
        // 无障碍框与触摸命中区一致，不小于 44pt 宽。
        let handle = try XCTUnwrap(found.first)
        XCTAssertGreaterThanOrEqual(handle.accessibilityFrame.width, 44)
        XCTAssertGreaterThanOrEqual(handle.accessibilityFrame.height, 44)
        // accessibilityFrame 是屏幕坐标；用同一换算求出拖柄原点，再把中心换回拖柄坐标。
        // 测试窗口没有挂场景时换算为恒等，挂场景时含窗口偏移，两种情况都成立。
        let origin = UIAccessibility.convertToScreenCoordinates(handle.bounds, in: handle).origin
        let center = CGPoint(
            x: handle.accessibilityFrame.midX - origin.x + handle.bounds.minX,
            y: handle.accessibilityFrame.midY - origin.y + handle.bounds.minY
        )
        XCTAssertTrue(handle.point(inside: center, with: nil))
        label.selectionStartAccessibilityName = "Start"
        XCTAssertEqual(found.first?.accessibilityLabel, "Start")
        // 文字元素仍在拖柄之前。
        XCTAssertTrue((label.accessibilityElements ?? []).first is TextAccessibilityElement)
        label.selectedRange = nil
        XCTAssertTrue(handles(label).isEmpty)
        withExtendedLifetime(window) {}
    }

    func testIncrementAndDecrementMoveOneComposedCharacterWithinBounds() throws {
        let string = "a👨‍👩‍👧‍👦bc"
        let (window, label) = try hosted(string)
        let family = (string as NSString).range(of: "👨‍👩‍👧‍👦")
        label.selectedRange = NSRange(location: NSMaxRange(family), length: 1)
        label.layoutIfNeeded()
        let start = try XCTUnwrap(handles(label).first)
        let end = try XCTUnwrap(handles(label).last)
        start.accessibilityDecrement()
        XCTAssertEqual(label.selectedRange, NSRange(location: family.location, length: family.length + 1))
        start.accessibilityDecrement()
        start.accessibilityDecrement()
        XCTAssertEqual(label.selectedRange?.location, 0)
        end.accessibilityIncrement()
        end.accessibilityIncrement()
        XCTAssertEqual(label.selectedRange.map(NSMaxRange), (string as NSString).length)
        // 结束端向前收缩时不越过开始端，至少保留一个组合字符。
        for _ in 0 ..< 10 {
            end.accessibilityDecrement()
        }
        XCTAssertEqual(label.selectedRange, NSRange(location: 0, length: 1))
        for _ in 0 ..< 10 {
            start.accessibilityIncrement()
        }
        XCTAssertEqual(label.selectedRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(end.accessibilityValue, "a")
        withExtendedLifetime(window) {}
    }

    func testAdjustingKeepsVoiceOverFocusOnTheAdjustedHandle() throws {
        let (window, label) = try hosted("焦点保持在拖柄上")
        var arguments: [Any?] = []
        label.postAccessibilityLayoutChanged = { arguments.append($0) }
        label.selectedRange = NSRange(location: 1, length: 2)
        label.layoutIfNeeded()
        let start = try XCTUnwrap(handles(label).first)
        let end = try XCTUnwrap(handles(label).last)
        end.accessibilityIncrement()
        start.accessibilityDecrement()
        XCTAssertEqual(arguments.count, 2)
        XCTAssertTrue(arguments.first.flatMap { $0 as AnyObject? } === end)
        XCTAssertTrue(arguments.last.flatMap { $0 as AnyObject? } === start)
        withExtendedLifetime(window) {}
    }
}
