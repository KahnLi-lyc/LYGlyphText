@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class TapTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 24)

    private func cellRect(_ label: LYGlyphTextLabel, at location: Int) throws -> CGRect {
        let layout = label.measuredLayout(width: label.bounds.width)
        let source = try XCTUnwrap(label.document?.string)
        let range = (source as NSString).rangeOfComposedCharacterSequence(at: location)
        // 内边距为 0、顶部对齐时 Layout 坐标即 Label 本地坐标。
        return try XCTUnwrap(layout.visibleTextFragments(in: range, source: source).first?.rect)
    }

    private func hosted(_ string: String, actions: [LYGlyphTextAction] = []) throws -> (UIWindow, LYGlyphTextLabel) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 360, height: 120))
        label.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: string, attributes: [.font: font]), actions: actions
        )
        window.addSubview(label)
        label.layoutIfNeeded()
        return (window, label)
    }

    func testRecognizerExistsOnlyWhileCallbackIsSet() throws {
        let (window, label) = try hosted("Plain text")
        XCTAssertNil(label.labelTapRecognizer)
        let before = label.gestureRecognizers?.count ?? 0
        label.onTap = { _ in }
        XCTAssertNotNil(label.labelTapRecognizer)
        XCTAssertEqual(label.gestureRecognizers?.count, before + 1)
        label.onTap = nil
        XCTAssertNil(label.labelTapRecognizer)
        XCTAssertEqual(label.gestureRecognizers?.count, before)
        label.onTap = { _ in }
        label.clearForDismantle()
        XCTAssertNil(label.onTap)
        XCTAssertNil(label.labelTapRecognizer)
        withExtendedLifetime(window) {}
    }

    func testTapYieldsToActionsTokensSelectionAndAttachments() throws {
        let (window, label) = try hosted(
            "Open detail or tap elsewhere", actions: [.init(actionID: "detail", range: NSRange(location: 5, length: 6))]
        )
        label.onTap = { _ in }
        let plain = try cellRect(label, at: 15)
        let action = try cellRect(label, at: 7)
        let plainPoint = CGPoint(x: plain.midX, y: plain.midY)
        let actionPoint = CGPoint(x: action.midX, y: action.midY)
        XCTAssertTrue(label.shouldSendTap(at: plainPoint, touchedView: label))
        // 没有动作回调时动作不会发送事件，单击交给 onTap。
        XCTAssertTrue(label.shouldSendTap(at: actionPoint, touchedView: label))
        label.onAction = { _ in }
        XCTAssertFalse(label.shouldSendTap(at: actionPoint, touchedView: label))
        XCTAssertTrue(label.shouldSendTap(at: CGPoint(x: 350, y: 110), touchedView: label))
        XCTAssertFalse(label.shouldSendTap(at: CGPoint(x: 500, y: 10), touchedView: label))
        label.isSelectable = true
        label.selectedRange = NSRange(location: 0, length: 4)
        XCTAssertFalse(label.shouldSendTap(at: plainPoint, touchedView: label))
        label.selectedRange = nil
        XCTAssertTrue(label.shouldSendTap(at: plainPoint, touchedView: label))
        label.removeFromSuperview()
        XCTAssertFalse(label.shouldSendTap(at: plainPoint, touchedView: label))
        withExtendedLifetime(window) {}
    }

    func testTruncationTokenAndInteractiveAttachmentTakePriority() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 260, height: 40))
        let button = LYGlyphTextViewAttachment(
            id: "b", viewID: "button", size: CGSize(width: 30, height: 20), isInteractive: true
        )
        var made: UIView?
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            let view = UIButton(type: .system)
            made = view
            return view
        }
        label.document = try LYGlyphTextDocument(segments: [
            .view(button), .text(NSAttributedString(string: String(repeating: " 很长的内容", count: 20)))
        ])
        label.configuration.numberOfLines = 1
        label.configuration.truncationToken = .init(text: "…展开", actionID: "expand")
        label.onAction = { _ in }
        label.onTap = { _ in }
        window.addSubview(label)
        label.layoutIfNeeded()
        let layout = label.measuredLayout(width: label.bounds.width)
        let geometry = ActionGeometry(layout: layout, bounds: label.bounds, configuration: label.configuration)
        let token = try XCTUnwrap(geometry.entries.first { $0.isTruncationToken }?.rects.first)
        XCTAssertFalse(label.shouldSendTap(at: CGPoint(x: token.midX, y: token.midY), touchedView: label))
        let attachment = try XCTUnwrap(made)
        XCTAssertFalse(label.shouldSendTap(at: CGPoint(x: 5, y: 5), touchedView: attachment))
        withExtendedLifetime(window) {}
    }

    func testSwiftUIPassesTapCallback() throws {
        var taps = 0
        let view = try LYGlyphTextView(
            document: LYGlyphTextDocument(attributedText: NSAttributedString(string: "SwiftUI tap")),
            onTap: { _ in taps += 1 }
        )
        let controller = UIHostingController(rootView: view.frame(width: 300))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        func find(_ view: UIView) -> LYGlyphTextLabel? {
            (view as? LYGlyphTextLabel) ?? view.subviews.lazy.compactMap(find).first
        }
        let label = try XCTUnwrap(find(controller.view))
        XCTAssertNotNil(label.labelTapRecognizer)
        label.onTap?(.zero)
        XCTAssertEqual(taps, 1)
        withExtendedLifetime(window) {}
    }
}
