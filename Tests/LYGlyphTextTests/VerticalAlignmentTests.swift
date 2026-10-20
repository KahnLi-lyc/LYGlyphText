@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class VerticalAlignmentTests: XCTestCase {
    private let insets = UIEdgeInsets(top: 7, left: 9, bottom: 11, right: 13)

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func rect(for channel: Int) -> CGRect? {
            var points: [(Int, Int)] = []
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let index = (y * width + x) * 4
                    let rgb = Array(bytes[index ..< index + 3])
                    if rgb[channel] > 180, rgb[(channel + 1) % 3] < 100, rgb[(channel + 2) % 3] < 100 {
                        points.append((x, y))
                    }
                }
            }
            guard let minX = points.map(\.0).min(), let maxX = points.map(\.0).max(),
                  let minY = points.map(\.1).min(), let maxY = points.map(\.1).max() else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    private func pixels(in view: UIView) throws -> Pixels {
        let size = CGSize(width: 320, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            view.layer.render(in: renderer.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        return Pixels(bytes: bytes, width: width, height: height)
    }

    private func document() throws -> LYGlyphTextDocument {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        return try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "AA \u{FFFC} \u{FFFC}", attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: UIColor.blue
            ]),
            attachments: [3: .init(id: "image", image: image, size: CGSize(width: 20, height: 20))],
            viewAttachments: [5: .init(
                id: "view", viewID: "button", size: CGSize(width: 30, height: 20), isInteractive: true
            )]
        )
    }

    private func findLabel(_ view: UIView) -> LYGlyphTextLabel? {
        (view as? LYGlyphTextLabel) ?? view.subviews.lazy.compactMap { self.findLabel($0) }.first
    }

    func testSwiftUIExplicitDisplayHeightActuallyEnlargesUnderlyingLabelAtProposedWidth() throws {
        let document = try document()
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = document
        label.configuration.textContainerInset = insets
        let natural = label.sizeThatFits(CGSize(width: 240, height: CGFloat.infinity)).height
        let controller = UIHostingController(rootView: LYGlyphTextView(
            document: document, configuration: label.configuration, displayHeight: natural + 60
        ).frame(width: 240))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let underlying = try XCTUnwrap(findLabel(controller.view))
        XCTAssertEqual(underlying.bounds.width, 240, accuracy: 0.01)
        XCTAssertEqual(underlying.bounds.height, natural + 60, accuracy: 0.01)
    }

    func testSwiftUIDisplayHeightUpdatesSupportsCompressionZeroAndInvalidFallbackWithoutChangingNaturalMeasurement()
        throws
    {
        let document = try document()
        let configuration = LYGlyphTextConfiguration(textContainerInset: insets, verticalAlignment: .bottom)
        let measure = LYGlyphTextLabel(frame: .zero)
        measure.document = document
        measure.configuration = configuration
        let natural = measure.sizeThatFits(CGSize(width: 240, height: 1)).height
        var calls = 0
        let provider = LYGlyphTextAttachmentViewProvider { _ in calls += 1
            return UIView()
        }
        let controller = UIHostingController(rootView: LYGlyphTextView(
            document: document, configuration: configuration, viewProvider: provider
        ).frame(width: 240))
        let fitting = controller.sizeThatFits(in: CGSize(width: 240, height: 10000))
        XCTAssertEqual(fitting.height, natural, accuracy: 1 / max(controller.traitCollection.displayScale, 1))
        for height: CGFloat? in [natural + 60, 20, 0, -1, .nan, .infinity, nil] {
            controller.rootView = LYGlyphTextView(
                document: document, configuration: configuration, viewProvider: provider, displayHeight: height
            ).frame(width: 240)
            let expected = height.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? natural
            XCTAssertEqual(controller.sizeThatFits(in: CGSize(width: 240, height: 10000)).height, expected)
        }
        XCTAssertEqual(calls, 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let underlying = try XCTUnwrap(findLabel(controller.view))
        underlying.setContentHuggingPriority(UILayoutPriority(271), for: .vertical)
        underlying.setContentCompressionResistancePriority(UILayoutPriority(819), for: .horizontal)
        for height: CGFloat? in [natural + 60, 20, 0, -1, .nan, .infinity, -.infinity, nil] {
            controller.rootView = LYGlyphTextView(
                document: document, configuration: configuration, viewProvider: provider, displayHeight: height
            ).frame(width: 240)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let expected = height.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? natural
            XCTAssertTrue(findLabel(controller.view) === underlying)
            XCTAssertEqual(underlying.bounds.width, 240, accuracy: 0.01)
            XCTAssertEqual(underlying.bounds.height, expected, accuracy: 0.01)
            XCTAssertEqual(underlying.sizeThatFits(CGSize(width: 240, height: 1)).height, natural)
            XCTAssertEqual(underlying.contentHuggingPriority(for: .vertical).rawValue, 271)
            XCTAssertEqual(underlying.contentCompressionResistancePriority(for: .horizontal).rawValue, 819)
            let geometry = try XCTUnwrap(DisplayGeometry(
                bounds: underlying.bounds, layoutSize: underlying.measuredLayout(width: 240).size,
                configuration: configuration
            ))
            XCTAssertEqual(geometry.translation.y, max(0, expected - natural), accuracy: 0.01)
        }
    }

    func testSwiftUIDisplayHeightAndWidthRoundTripsReuseLabelProviderAndContinuouslyVisibleView() throws {
        let document = try document()
        let configuration = LYGlyphTextConfiguration(textContainerInset: insets, verticalAlignment: .center)
        let measure = LYGlyphTextLabel(frame: .zero)
        measure.document = document
        measure.configuration = configuration
        let natural = measure.sizeThatFits(CGSize(width: 240, height: 1)).height
        var calls = 0
        var removed = 0
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in calls += 1
            return UIView()
        }, onUnmount: {
            _, _ in removed += 1
        })
        let controller = UIHostingController(rootView: LYGlyphTextView(
            document: document, configuration: configuration, viewProvider: provider
        ).frame(width: 240))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let original = try XCTUnwrap(findLabel(controller.view))
        let attachedView = try XCTUnwrap(original.subviews.first?.subviews.first)
        for (width, height): (CGFloat, CGFloat?) in [(240, natural + 60), (160, 150), (240, nil)] {
            controller.rootView = LYGlyphTextView(
                document: document, configuration: configuration, viewProvider: provider, displayHeight: height
            ).frame(width: width)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            original.layoutIfNeeded()
            XCTAssertTrue(findLabel(controller.view) === original)
            XCTAssertTrue(original.viewProvider === provider)
            XCTAssertTrue(original.subviews.first?.subviews.first === attachedView)
            XCTAssertEqual(original.bounds.width, width)
            XCTAssertEqual(original.bounds.height, height ?? natural)
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(removed, 0)
        }
    }

    func testLayoutCacheRetainsTwoWidthsAndDisplayGeometryDoesNotCreateAnotherLayout() throws {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document()
        let first = try XCTUnwrap(label.measuredLayout(width: 240).lines.first?.text)
        _ = label.measuredLayout(width: 180)
        let reused = try XCTUnwrap(label.measuredLayout(width: 240).lines.first?.text)
        XCTAssertTrue(first === reused)
        _ = DisplayGeometry(
            bounds: CGRect(x: 17, y: 23, width: 240, height: 200),
            layoutSize: label.measuredLayout(width: 240).size, configuration: label.configuration
        )
        XCTAssertTrue(first === label.measuredLayout(width: 240).lines.first?.text)
        _ = label.measuredLayout(width: 120)
        let afterEviction = try XCTUnwrap(label.measuredLayout(width: 240).lines.first?.text)
        XCTAssertFalse(first === afterEviction)
    }

    func testViewAttachmentActuallyMovesByZeroThirtySixtyWithoutRemounting() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document()
        label.configuration.textContainerInset = insets
        var calls = 0
        let button = UIButton(type: .system)
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            calls += 1
            return button
        }
        let natural = label.sizeThatFits(CGSize(width: 240, height: 1))
        let placement = try XCTUnwrap(label.measuredLayout(width: 240).viewAttachments.first)
        XCTAssertEqual(calls, 0)
        label.frame = CGRect(x: 0, y: 0, width: 240, height: natural.height + 60)
        label.bounds.origin = CGPoint(x: 17, y: 23)
        controller.view.addSubview(label)
        for (alignment, offset): (LYGlyphTextConfiguration.VerticalAlignment, CGFloat) in [
            (.top, 0), (.center, 30), (.bottom, 60)
        ] {
            label.configuration.verticalAlignment = alignment
            label.layoutIfNeeded()
            let actual = button.convert(button.bounds, to: label)
            XCTAssertEqual(actual.minY, placement.rect.minY + label.bounds.minY + offset, accuracy: 0.01)
            XCTAssertEqual(label.sizeThatFits(CGSize(width: 240, height: 1)), natural)
        }
        XCTAssertEqual(calls, 1)
    }

    func testActualTextImageAndViewPixelsMoveTogetherAndBoundsOriginDoesNotMoveVisibleContent() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document()
        label.configuration.textContainerInset = insets
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            let view = UIView()
            view.backgroundColor = .green
            return view
        }
        let natural = label.sizeThatFits(CGSize(width: 240, height: 1))
        label.frame = CGRect(x: 0, y: 0, width: 240, height: natural.height + 60)
        controller.view.addSubview(label)
        label.layoutIfNeeded()
        let top = try pixels(in: controller.view)
        let initialRects = try (0 ..< 3).map { try XCTUnwrap(top.rect(for: $0)) }
        for (alignment, offset): (LYGlyphTextConfiguration.VerticalAlignment, CGFloat) in [
            (.top, 0), (.center, 30), (.bottom, 60)
        ] {
            label.configuration.verticalAlignment = alignment
            label.layoutIfNeeded()
            let actual = try pixels(in: controller.view)
            for channel in 0 ..< 3 {
                let rect = try XCTUnwrap(actual.rect(for: channel))
                let expected = initialRects[channel].offsetBy(dx: 0, dy: offset)
                XCTAssertEqual(rect.minX, expected.minX, accuracy: 0.01)
                XCTAssertEqual(rect.minY, expected.minY, accuracy: 0.01)
                // 固定 clip 与抗锯齿边界可改变最外侧一个采样像素，不能改变内容位置。
                XCTAssertEqual(rect.width, expected.width, accuracy: 1)
                XCTAssertEqual(rect.height, expected.height, accuracy: 1)
            }
            label.bounds.origin = CGPoint(x: 17, y: 23)
            label.layoutIfNeeded()
            XCTAssertEqual(try pixels(in: controller.view).bytes, actual.bytes)
            label.bounds.origin = .zero
        }
    }

    func testAlignmentDoesNotChangeMeasurementsPrioritiesOrCreateViews() throws {
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 200))
        label.document = try document()
        label.configuration.textContainerInset = insets
        label.setContentHuggingPriority(UILayoutPriority(273), for: .vertical)
        label.setContentCompressionResistancePriority(UILayoutPriority(821), for: .horizontal)
        var calls = 0
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in calls += 1
            return UIView()
        }
        let expected = label.sizeThatFits(CGSize(width: 240, height: 1))
        let ideal = label.intrinsicContentSize
        for alignment in [LYGlyphTextConfiguration.VerticalAlignment.top, .center, .bottom] {
            label.configuration.verticalAlignment = alignment
            XCTAssertEqual(label.sizeThatFits(CGSize(width: 240, height: 1)), expected)
            XCTAssertEqual(label.intrinsicContentSize, ideal)
            XCTAssertEqual(label.systemLayoutSizeFitting(
                CGSize(width: 240, height: 1), withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height, expected.height)
            _ = label.measuredLayout(width: 240).visibleTextFragments(
                in: NSRange(location: 0, length: 6), source: label.document?.string ?? ""
            )
            _ = DisplayGeometry(bounds: label.bounds, layoutSize: expected, configuration: label.configuration)
            XCTAssertEqual(label.contentHuggingPriority(for: .vertical).rawValue, 273)
            XCTAssertEqual(label.contentCompressionResistancePriority(for: .horizontal).rawValue, 821)
        }
        XCTAssertEqual(calls, 0)
    }

    func testCompressionKeepsTopTransformAndContentClipFixedForEveryAlignment() throws {
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 25))
        label.document = try document()
        label.configuration.textContainerInset = insets
        label.bounds.origin = CGPoint(x: 17, y: 23)
        let layout = label.measuredLayout(width: 240)
        XCTAssertGreaterThan(layout.size.height, label.bounds.height)
        for alignment in [LYGlyphTextConfiguration.VerticalAlignment.top, .center, .bottom] {
            label.configuration.verticalAlignment = alignment
            let geometry = try XCTUnwrap(DisplayGeometry(
                bounds: label.bounds, layoutSize: layout.size, configuration: label.configuration
            ))
            XCTAssertEqual(geometry.translation, label.bounds.origin)
            XCTAssertEqual(geometry.contentClip, CGRect(x: 26, y: 30, width: 218, height: 7))
        }
    }

    func testWidthRoundTripUsesCurrentLayoutAndKeepsVisibleViewInstance() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 170))
        label.document = try document()
        label.configuration = .init(textContainerInset: insets, verticalAlignment: .bottom)
        var calls = 0
        let view = UIView()
        label.viewProvider = .init { _ in calls += 1
            return view
        }
        controller.view.addSubview(label)
        var first: CGRect?
        for width: CGFloat in [240, 120, 240] {
            label.bounds.size.width = width
            label.layoutIfNeeded()
            let layout = label.measuredLayout(width: width)
            let placement = try XCTUnwrap(layout.viewAttachments.first)
            let expected = placement.rect.offsetBy(dx: 0, dy: max(0, label.bounds.height - layout.size.height))
            let actual = view.convert(view.bounds, to: label)
            XCTAssertEqual(actual, expected)
            if first == nil { first = actual }
        }
        XCTAssertEqual(view.convert(view.bounds, to: label), first)
        XCTAssertEqual(calls, 1)
    }

    func testPartiallyVisibleBottomAlignedAttachmentClipsAndOnlyVisibleAreaReceivesHit() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.maximumLineHeight = 18
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "\u{FFFC}", attributes: [.font: UIFont.systemFont(ofSize: 16), .paragraphStyle: paragraph]
        ), viewAttachments: [0: .init(
            id: "tall", viewID: "button", size: CGSize(width: 40, height: 60), isInteractive: true
        )])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 160, height: 100))
        label.document = document
        label.configuration = .init(textContainerInset: insets, verticalAlignment: .bottom)
        label.bounds.origin = CGPoint(x: 17, y: 23)
        let button = UIButton(type: .system)
        var calls = 0
        label.viewProvider = .init { _ in calls += 1
            return button
        }
        controller.view.addSubview(label)
        label.layoutIfNeeded()
        let layout = label.measuredLayout(width: 160)
        let geometry = try XCTUnwrap(DisplayGeometry(
            bounds: label.bounds, layoutSize: layout.size, configuration: label.configuration
        ))
        let rect = button.convert(button.bounds, to: label)
        let visible = rect.intersection(geometry.contentClip)
        XCTAssertFalse(visible.isEmpty)
        XCTAssertLessThan(visible.height, rect.height)
        XCTAssertEqual(button.superview?.frame, geometry.contentClip)
        XCTAssertTrue(label.hitTest(CGPoint(x: visible.midX, y: visible.midY), with: nil) === button)
        XCTAssertFalse(label.hitTest(CGPoint(x: rect.midX, y: geometry.contentClip.minY - 1), with: nil) === button)
        XCTAssertEqual(calls, 1)
    }
}
