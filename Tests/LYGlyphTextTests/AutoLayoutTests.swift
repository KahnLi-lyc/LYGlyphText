@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class AutoLayoutTests: XCTestCase {
    private func label() throws -> LYGlyphTextLabel {
        let label = LYGlyphTextLabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: String(repeating: "自动布局 Hello 世界 😀 ", count: 12),
            attributes: [.font: UIFont.systemFont(ofSize: 20)]
        ))
        return label
    }

    private func host(_ label: LYGlyphTextLabel, width: CGFloat) -> UIView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            label.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        return host
    }

    private func settle(_ host: UIView) {
        // 允许第一次解析宽度触发固有高度失效；后续布局应收敛。
        for _ in 0 ..< 4 {
            host.layoutIfNeeded()
        }
    }

    func testLeadingTrailingConstraintsProduceContentHeightAndConverge() throws {
        let view = try label()
        let container = host(view, width: 210)
        settle(container)
        XCTAssertEqual(view.bounds.width, 210, accuracy: 0.01)
        XCTAssertEqual(
            view.bounds.height,
            view.sizeThatFits(CGSize(width: 210, height: CGFloat.infinity)).height,
            accuracy: 0.5
        )
        let stable = view.frame
        settle(container)
        XCTAssertEqual(view.frame, stable)
        XCTAssertFalse(view.hasAmbiguousLayout)
        container.bounds.size.width = 130
        settle(container)
        XCTAssertGreaterThan(view.frame.height, stable.height)
    }

    func testFixedWidthAndUpperBound() throws {
        for isUpperBound in [false, true] {
            let view = try label()
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 1000))
            container.addSubview(view)
            let width = isUpperBound ? view.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
                : view.widthAnchor.constraint(equalToConstant: 160)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor), width
            ])
            settle(container)
            XCTAssertEqual(view.bounds.width, 160, accuracy: 0.01)
            XCTAssertEqual(
                view.bounds.height,
                view.sizeThatFits(CGSize(width: 160, height: CGFloat.infinity)).height,
                accuracy: 0.5
            )
        }
    }

    func testPrioritiesDetermineSiblingCompressionAndSurviveContentUpdates() throws {
        let view = try label()
        XCTAssertEqual(view.contentHuggingPriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(view.contentCompressionResistancePriority(for: .vertical), .defaultHigh)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(UILayoutPriority(260), for: .vertical)
        let button = UIButton(type: .system)
        button.setTitle("保留按钮宽度", for: .normal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [view, button])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 8
        stack.frame = CGRect(x: 0, y: 0, width: 280, height: 1000)
        settle(stack)
        XCTAssertGreaterThan(view.bounds.height, 30)
        XCTAssertEqual(button.bounds.width, button.intrinsicContentSize.width, accuracy: 0.5)
        view.document = nil
        XCTAssertEqual(view.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        XCTAssertEqual(view.contentHuggingPriority(for: .vertical), UILayoutPriority(260))
    }

    func testLowHuggingAllowsHorizontalStretch() throws {
        let view = try label()
        view.document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "短文本"))
        view.setContentHuggingPriority(UILayoutPriority(240), for: .horizontal)
        let button = UIButton(type: .system)
        button.setTitle("按钮", for: .normal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [view, button])
        stack.axis = .horizontal
        stack.frame = CGRect(x: 0, y: 0, width: 300, height: 50)
        settle(stack)
        XCTAssertGreaterThan(view.bounds.width, view.intrinsicContentSize.width + 100)
        XCTAssertEqual(button.bounds.width, button.intrinsicContentSize.width, accuracy: 0.5)
    }

    func testSwiftUIProposalAndUIKitHeightsAgree() throws {
        let view = try label()
        let document = try XCTUnwrap(view.document)
        for width: CGFloat in [90, 210, 300] {
            let controller = UIHostingController(rootView: LYGlyphTextView(document: document).frame(width: width))
            controller.loadViewIfNeeded()
            let fitting = controller.sizeThatFits(in: CGSize(width: width, height: 10000))
            let expected = view.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
            let scale = max(controller.traitCollection.displayScale, 1)
            XCTAssertEqual(fitting.height, expected.height, accuracy: 1 / scale)
        }
    }

    func testSwiftUIIdealZeroWidthAndDocumentReplacement() throws {
        let view = try label()
        let controller = UIHostingController(rootView: LYGlyphTextView(document: view.document))
        controller.loadViewIfNeeded()
        let initial = controller.sizeThatFits(in: CGSize(width: 180, height: 10000))
        controller.rootView = try LYGlyphTextView(document: LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "短文本", attributes: [.font: UIFont.systemFont(ofSize: 20)])
        ))
        let short = controller.sizeThatFits(in: CGSize(width: 180, height: 10000))
        XCTAssertLessThan(short.height, initial.height)
        controller.rootView = LYGlyphTextView(document: nil)
        let empty = controller.sizeThatFits(in: CGSize(width: 180, height: 10000))
        XCTAssertEqual(empty.height, 0)

        let idealHost = UIHostingController(rootView: LYGlyphTextView(document: view.document).fixedSize())
        let ideal = idealHost.sizeThatFits(in: CGSize(width: 80, height: 10000))
        XCTAssertEqual(
            ideal.height,
            view.sizeThatFits(CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).height,
            accuracy: 1
        )
        let zeroHost = UIHostingController(rootView: LYGlyphTextView(document: view.document).frame(width: 0))
        let zero = zeroHost.sizeThatFits(in: CGSize(width: 0, height: 10000))
        XCTAssertEqual(zero.width, 0)
        XCTAssertTrue(zero.height.isFinite)
    }

    func testDefaultFontRespondsToContentSizeCategoryWhileExplicitFontStaysFixed() throws {
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "默认 body"))
        let normal = ResolvedText(document: document, traits: UITraitCollection(preferredContentSizeCategory: .large))
        let large = ResolvedText(
            document: document,
            traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        XCTAssertGreaterThan(
            large.layout(width: 500, insets: .zero, scale: 2).size.height,
            normal.layout(width: 500, insets: .zero, scale: 2).size.height
        )
        let fixed = try label().document
        let fixedNormal = ResolvedText(document: fixed, traits: UITraitCollection(preferredContentSizeCategory: .large))
        let fixedLarge = ResolvedText(
            document: fixed,
            traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )
        XCTAssertEqual(
            fixedNormal.layout(width: 200, insets: .zero, scale: 2).size,
            fixedLarge.layout(width: 200, insets: .zero, scale: 2).size
        )
    }
}
