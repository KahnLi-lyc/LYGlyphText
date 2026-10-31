import CoreText
@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class EnvironmentTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]
    private let canvas = CGSize(width: 360, height: 240)

    func testDefaultBodyTracksContentSizeCategory() throws {
        let fixture = UIKitFixture()
        defer { fixture.close() }
        fixture.label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "Default body wraps as the environment grows."
        ))
        var heights: [CGFloat] = []
        for category in categories + [.large] {
            fixture.apply(category: category)
            let layout = fixture.label.measuredLayout(width: 180)
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: fixture.label.traitCollection)
            let runs = try fonts(in: layout)
            XCTAssertFalse(runs.isEmpty)
            for actual in runs {
                XCTAssertEqual(CTFontGetSize(actual), font.pointSize, accuracy: 0.001)
                XCTAssertEqual(CTFontGetSymbolicTraits(actual).rawValue, font.fontDescriptor.symbolicTraits.rawValue)
            }
            heights.append(layout.size.height)
            XCTAssertLessThanOrEqual(fixture.label.layoutMeasurementSnapshot.cachedLayoutCount, 2)
            print("A1a body \(category.rawValue): font=\(font.pointSize), height=\(layout.size.height)")
        }
        XCTAssertGreaterThan(heights[1], heights[0])
        XCTAssertGreaterThan(heights[2], heights[1])
        XCTAssertEqual(heights[3], heights[0])
    }

    func testExplicitFixedFontDoesNotScale() throws {
        let baseTraits = UITraitCollection(preferredContentSizeCategory: .large)
        let fonts = [
            UIFont.systemFont(ofSize: 19, weight: .semibold),
            UIFont.preferredFont(forTextStyle: .body, compatibleWith: baseTraits),
            UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 21), compatibleWith: baseTraits)
        ]
        let fixture = UIKitFixture()
        defer { fixture.close() }
        for font in fonts {
            fixture.label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: "Fixed snapshot font remains unchanged.", attributes: [
                    .font: font,
                    .kern: 1.25,
                    .baselineOffset: 2.5
                ]
            ))
            var sizes: [CGSize] = []
            for category in categories {
                fixture.apply(category: category)
                let layout = fixture.label.measuredLayout(width: 180)
                for actual in try self.fonts(in: layout) {
                    XCTAssertEqual(CTFontGetSize(actual), font.pointSize, accuracy: 0.001)
                    XCTAssertEqual(
                        CTFontGetSymbolicTraits(actual).rawValue,
                        font.fontDescriptor.symbolicTraits.rawValue
                    )
                }
                sizes.append(layout.size)
            }
            XCTAssertTrue(sizes.allSatisfy { $0 == sizes[0] })
        }
    }

    func testAttachmentAlignmentTracksDefaultFontWithoutResizing() throws {
        let fixture = UIKitFixture()
        defer { fixture.close() }
        let alignments: [LYGlyphTextAttachmentAlignment] = [.top, .center, .bottom]
        let size = CGSize(width: 18, height: 10)
        fixture.label.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "A\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}"),
            attachments: Dictionary(uniqueKeysWithValues: alignments.enumerated().map { index, alignment in
                (index + 1, .init(id: "image-\(index)", image: image(), size: size, alignment: alignment))
            }),
            viewAttachments: Dictionary(uniqueKeysWithValues: alignments.enumerated().map { index, alignment in
                (index + 4, .init(id: "view-\(index)", viewID: "badge", size: size, alignment: alignment))
            })
        )
        for category in categories {
            fixture.apply(category: category)
            let layout = fixture.label.measuredLayout(width: 360)
            XCTAssertEqual(layout.attachments.count, 3)
            XCTAssertEqual(layout.viewAttachments.count, 3)
            let baseline = try XCTUnwrap(layout.lines.first).baseline.y
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: fixture.label.traitCollection)
            let placements = layout.attachments.map { ($0.sourceLocation, $0.rect) }
                + layout.viewAttachments.map { ($0.sourceLocation, $0.rect) }
            for (location, rect) in placements {
                let expectedTop: CGFloat = switch alignments[(location - 1) % 3] {
                case .top: baseline - font.ascender
                case .center: baseline - (font.ascender + font.descender + size.height) / 2
                case .bottom: baseline - font.descender - size.height
                }
                XCTAssertEqual(rect.minY, expectedTop, accuracy: 0.001)
                XCTAssertEqual(rect.size, size)
            }
            print("A1a attachment \(category.rawValue): baseline=\(baseline), rects=\(layout.attachments.map(\.rect))")
        }
    }

    func testSemanticColorsResolveForLightAndDark() throws {
        let fixture = UIKitFixture()
        defer { fixture.close() }
        fixture.label.document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "MMMM",
            attributes: [
                .font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.label,
                .backgroundColor: UIColor.secondarySystemBackground,
                .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: UIColor.systemRed,
                .strikethroughStyle: NSUnderlineStyle.thick.rawValue, .strikethroughColor: UIColor.systemBlue
            ]
        ), actions: [.init(actionID: "semantic", range: NSRange(location: 0, length: 4), pressedStyle: .init(
            foregroundColor: .systemGreen, backgroundColor: .systemYellow
        ))])
        var signatures: [[UInt8]] = []
        for style in [UIUserInterfaceStyle.light, .dark, .light] {
            fixture.apply(style: style)
            let layout = fixture.label.measuredLayout(width: 340)
            let traits = fixture.label.traitCollection
            let glyphs = try render { layout.preparedDrawing.drawGlyphs(in: $0, pressed: nil) }
            let backgrounds = try render { layout.preparedDrawing.drawBackgrounds(in: $0, pressed: nil) }
            let strokes = try render { layout.preparedDrawing.drawStrokes(in: $0, pressed: nil) }
            let pressedGlyphs = try render { layout.preparedDrawing.drawGlyphs(in: $0, pressed: 0) }
            let pressedBackgrounds = try render { layout.preparedDrawing.drawBackgrounds(in: $0, pressed: 0) }
            for (name, pixels, color) in [
                ("foreground", glyphs, UIColor.label),
                ("background", backgrounds, .secondarySystemBackground),
                ("underline", strokes, .systemRed), ("strikethrough", strokes, .systemBlue),
                ("pressedForeground", pressedGlyphs, .systemGreen),
                ("pressedBackground", pressedBackgrounds, .systemYellow)
            ] {
                let expected = rgb(color.resolvedColor(with: traits))
                let count = pixels.count { zip($0, expected).allSatisfy { abs(Int($0) - Int($1)) <= 3 } }
                XCTAssertGreaterThan(count, 5, "\(style.rawValue) \(name) expected=\(expected)")
                print("A1a color style=\(style.rawValue) \(name) rgb=\(expected) pixels=\(count)")
            }
            signatures.append(glyphs.bytes + backgrounds.bytes + strokes.bytes + pressedGlyphs.bytes)
        }
        XCTAssertNotEqual(signatures[0], signatures[1])
        XCTAssertEqual(signatures[0], signatures[2])
    }

    func testRTLHostPreservesSourceMappingAndImageOrientation() throws {
        let fixture = UIKitFixture()
        defer { fixture.close() }
        let source = "אב A😀\u{FFFC}\u{FFFC}ب"
        let location = (source as NSString).range(of: "\u{FFFC}").location
        let nativeView = UIView()
        fixture.label.viewProvider = .init { _ in nativeView }
        for explicitDirection in [NSWritingDirection.natural, .leftToRight, .rightToLeft] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.baseWritingDirection = explicitDirection
            fixture.label.document = try LYGlyphTextDocument(
                attributedText: NSAttributedString(
                    string: source, attributes: [.font: UIFont.systemFont(ofSize: 24), .paragraphStyle: paragraph]
                ),
                attachments: [location: .init(id: "direction", image: image(), size: CGSize(width: 40, height: 40))],
                viewAttachments: [location + 1: .init(
                    id: "native-direction",
                    viewID: "badge",
                    size: CGSize(width: 20, height: 20)
                )],
                actions: [.init(actionID: "all", range: NSRange(location: 0, length: source.utf16.count))]
            )
            for direction in [UITraitEnvironmentLayoutDirection.leftToRight, .rightToLeft] {
                fixture.apply(direction: direction)
                fixture.label
                    .semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
                XCTAssertEqual(
                    fixture.label.effectiveUserInterfaceLayoutDirection,
                    direction == .rightToLeft ? .rightToLeft : .leftToRight
                )
                let layout = fixture.label.measuredLayout(width: 340)
                XCTAssertEqual(fixture.label.traitCollection.layoutDirection, direction)
                XCTAssertNotNil(nativeView.superview)
                XCTAssertEqual(
                    nativeView.effectiveUserInterfaceLayoutDirection,
                    fixture.label.effectiveUserInterfaceLayoutDirection
                )
                let geometry = try XCTUnwrap(layout.sourceGeometry)
                XCTAssertEqual(geometry.cells.count, source.count)
                let ranges = geometry.cells.map(\.range).sorted { $0.location < $1.location }
                var offset = 0
                for character in source {
                    let expected = NSRange(location: offset, length: String(character).utf16.count)
                    XCTAssertTrue(ranges.contains(expected), "missing logical grapheme \(expected)")
                    offset = NSMaxRange(expected)
                }
                XCTAssertEqual(
                    try XCTUnwrap(layout.actionIndex.first).action.range,
                    NSRange(location: 0, length: source.utf16.count)
                )
                let placement = try XCTUnwrap(layout.attachments.first)
                XCTAssertEqual(placement.sourceLocation, location)
                let actual = try render { layout.draw(in: $0) }
                let expected = try render { context in
                    UIGraphicsPushContext(context)
                    image().draw(in: placement.rect)
                    UIGraphicsPopContext()
                }
                for x in [0.2, 0.8] {
                    for y in [0.2, 0.8] {
                        let point = CGPoint(x: placement.rect.minX + 40 * x, y: placement.rect.minY + 40 * y)
                        XCTAssertEqual(actual.color(at: point), expected.color(at: point))
                    }
                }
                let run = try XCTUnwrap((CTLineGetGlyphRuns(layout.lines[0].text) as? [CTRun])?.first)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let styleValue = try XCTUnwrap(attributes[kCTParagraphStyleAttributeName])
                // swiftformat:disable:next noForceUnwrapInTests
                let style = styleValue as! CTParagraphStyle
                var actualDirection = CTWritingDirection.natural
                XCTAssertTrue(CTParagraphStyleGetValueForSpecifier(
                    style, .baseWritingDirection, MemoryLayout<CTWritingDirection>.size, &actualDirection
                ))
                XCTAssertEqual(Int(actualDirection.rawValue), explicitDirection.rawValue)
            }
        }
    }

    func testSwiftUIEnvironmentReachesLabelAndMatchesUIKit() throws {
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "Body 环境 😀 مرحبا wraps across several lines with the shared layout."
        ))
        let configuration = LYGlyphTextConfiguration(textContainerInset: .init(top: 3, left: 5, bottom: 7, right: 11))
        let controller = UIHostingController(rootView: AnyView(EmptyView()))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 1000))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let fixture = UIKitFixture()
        defer { fixture.close() }
        fixture.label.document = document
        fixture.label.configuration = configuration
        for (category, dynamicSize) in zip(categories, [DynamicTypeSize.large, .xxxLarge, .accessibility5]) {
            for dark in [false, true] {
                for rtl in [false, true] {
                    controller.rootView = AnyView(LYGlyphTextView(document: document, configuration: configuration)
                        .frame(width: 180)
                        .dynamicTypeSize(dynamicSize)
                        .preferredColorScheme(dark ? .dark : .light)
                        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
                    fixture.apply(
                        category: category,
                        style: dark ? .dark : .light,
                        direction: rtl ? .rightToLeft : .leftToRight
                    )
                    let (label, uikitSize) = try waitForEnvironment(
                        in: controller.view, category: category, style: dark ? .dark : .light,
                        direction: rtl ? .rightToLeft : .leftToRight, uikitLabel: fixture.label
                    )
                    XCTAssertEqual(label.traitCollection.preferredContentSizeCategory, category)
                    XCTAssertEqual(label.traitCollection.userInterfaceStyle, dark ? .dark : .light)
                    XCTAssertEqual(label.effectiveUserInterfaceLayoutDirection, rtl ? .rightToLeft : .leftToRight)
                    XCTAssertEqual(label.bounds.width, 180, accuracy: 1 / label.contentScaleFactor)
                    XCTAssertEqual(label.bounds.height, uikitSize.height, accuracy: 1 / label.contentScaleFactor)
                    let expected = UIFont.preferredFont(
                        forTextStyle: .body,
                        compatibleWith: fixture.label.traitCollection
                    )
                    let actualFonts = try fonts(in: label.measuredLayout(width: 180))
                    XCTAssertFalse(actualFonts.isEmpty)
                    for font in actualFonts {
                        XCTAssertEqual(CTFontGetSize(font), expected.pointSize, accuracy: 0.001)
                    }
                    print(
                        "A1a SwiftUI \(category.rawValue) dark=\(dark) rtl=\(rtl) height=\(label.bounds.height) UIKit=\(uikitSize.height) scale=\(label.contentScaleFactor)"
                    )
                }
            }
        }
    }

    func testEnvironmentMeasurementDoesNotMountAttachments() throws {
        let document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "A\u{FFFC} body"),
            viewAttachments: [1: .init(id: "view", viewID: "badge", size: CGSize(width: 30, height: 20))]
        )
        for category in categories {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let fixture = UIKitFixture()
                defer { fixture.close() }
                // 先让空宿主完成 trait 传播；安装文档后只允许测量，不触发展示布局。
                let categoryBeforeLayout = fixture.label.traitCollection.preferredContentSizeCategory
                fixture.apply(category: category, style: style, direction: .rightToLeft)
                print(
                    "A1a empty host trait propagation: before=\(categoryBeforeLayout.rawValue) afterLayout=\(fixture.label.traitCollection.preferredContentSizeCategory.rawValue) expected=\(category.rawValue)"
                )
                let label = fixture.label
                XCTAssertEqual(label.traitCollection.preferredContentSizeCategory, category)
                XCTAssertEqual(label.traitCollection.userInterfaceStyle, style)
                XCTAssertEqual(label.traitCollection.layoutDirection, .rightToLeft)
                label.document = document
                var factoryCount = 0
                label.viewProvider = .init { _ in
                    factoryCount += 1
                    return UIView()
                }
                label.translatesAutoresizingMaskIntoConstraints = false
                let width = label.widthAnchor.constraint(equalToConstant: 222)
                width.identifier = "host-width"
                let height = label.heightAnchor.constraint(greaterThanOrEqualToConstant: 11)
                height.priority = .init(749)
                height.identifier = "host-minimum-height"
                let inactiveHeight = label.heightAnchor.constraint(equalToConstant: 800)
                inactiveHeight.priority = .defaultLow
                inactiveHeight.identifier = "host-inactive-height"
                NSLayoutConstraint.activate([width, height])
                let trackedConstraints = [width, height, inactiveHeight]
                let constraints = label.constraints.map(ConstraintSnapshot.init)
                let trackedStates = trackedConstraints.map(ConstraintSnapshot.init)
                XCTAssertFalse(constraints.isEmpty)
                let frame = label.frame
                let before = label.layoutMeasurementSnapshot
                _ = label.intrinsicContentSize
                _ = label.sizeThatFits(CGSize(width: 180, height: CGFloat.infinity))
                _ = label.systemLayoutSizeFitting(CGSize(width: 200, height: 1))
                _ = label.systemLayoutSizeFitting(
                    CGSize(width: 240, height: 0),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                _ = LYGlyphTextView.measuredSize(
                    proposal: .init(width: 160, height: nil), displayHeight: nil, label: label
                )
                XCTAssertEqual(factoryCount, 0)
                XCTAssertTrue(label.subviews.isEmpty)
                XCTAssertEqual(label.frame, frame)
                XCTAssertEqual(label.constraints.map(ConstraintSnapshot.init), constraints)
                XCTAssertEqual(trackedConstraints.map(ConstraintSnapshot.init), trackedStates)
                XCTAssertEqual(
                    label.layoutMeasurementSnapshot.intrinsicInvalidationCount,
                    before.intrinsicInvalidationCount
                )
                XCTAssertLessThanOrEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, 2)
            }
        }
    }

    private struct ConstraintSnapshot: Equatable {
        let identity: ObjectIdentifier
        let firstItem: ObjectIdentifier?
        let secondItem: ObjectIdentifier?
        let firstAttribute: NSLayoutConstraint.Attribute
        let secondAttribute: NSLayoutConstraint.Attribute
        let relation: NSLayoutConstraint.Relation
        let multiplier: CGFloat
        let constant: CGFloat
        let priority: Float
        let isActive: Bool
        let identifier: String?

        @MainActor
        init(_ constraint: NSLayoutConstraint) {
            identity = ObjectIdentifier(constraint)
            firstItem = constraint.firstItem.map(ObjectIdentifier.init)
            secondItem = constraint.secondItem.map(ObjectIdentifier.init)
            firstAttribute = constraint.firstAttribute
            secondAttribute = constraint.secondAttribute
            relation = constraint.relation
            multiplier = constraint.multiplier
            constant = constraint.constant
            priority = constraint.priority.rawValue
            isActive = constraint.isActive
            identifier = constraint.identifier
        }
    }

    private func fonts(in layout: LYGlyphTextLayout) throws -> [CTFont] {
        try layout.lines.flatMap { line in
            try (CTLineGetGlyphRuns(line.text) as! [CTRun]).map { run in
                try XCTUnwrap((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName]) as! CTFont
            }
        }
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { context in
            for (rect, color) in [
                (CGRect(x: 0, y: 0, width: 10, height: 10), UIColor.red),
                (CGRect(x: 10, y: 0, width: 10, height: 10), .green),
                (CGRect(x: 0, y: 10, width: 10, height: 10), .blue),
                (CGRect(x: 10, y: 10, width: 10, height: 10), .yellow)
            ] {
                color.setFill()
                context.fill(rect)
            }
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func color(at point: CGPoint) -> [UInt8] {
            let offset = (Int(point.y) * width + Int(point.x)) * 4
            return Array(bytes[offset ..< offset + 3])
        }

        func count(_ predicate: ([UInt8]) -> Bool) -> Int {
            stride(from: 0, to: bytes.count, by: 4).reduce(0) { total, offset in
                total + (predicate(Array(bytes[offset ..< offset + 3])) ? 1 : 0)
            }
        }
    }

    private func render(_ draw: (CGContext) -> Void) throws -> Pixels {
        let width = Int(canvas.width), height = Int(canvas.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(UIColor.magenta.cgColor)
            context.fill(CGRect(origin: .zero, size: canvas))
            context.translateBy(x: 0, y: canvas.height)
            context.scaleBy(x: 1, y: -1)
            draw(context)
        }
        return Pixels(bytes: bytes, width: width)
    }

    private func rgb(_ color: UIColor) -> [UInt8] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { UInt8((max(0, min(1, $0)) * 255).rounded()) }
    }

    private struct EnvironmentWaitTimeout: Error, CustomStringConvertible {
        let description: String
    }

    private func waitForEnvironment(
        in view: UIView,
        category: UIContentSizeCategory,
        style: UIUserInterfaceStyle,
        direction: UIUserInterfaceLayoutDirection,
        uikitLabel: LYGlyphTextLabel
    ) throws -> (LYGlyphTextLabel, CGSize) {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var actualState = "no underlying Label"
        repeat {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            if let label = findLabel(in: view) {
                let traits = label.traitCollection
                let scale = max(1, label.contentScaleFactor)
                let pixel = 1 / scale
                uikitLabel.contentScaleFactor = label.contentScaleFactor
                let expected = uikitLabel.sizeThatFits(CGSize(width: 180, height: CGFloat.infinity))
                let actualDirection = label.effectiveUserInterfaceLayoutDirection
                actualState = "category=\(traits.preferredContentSizeCategory.rawValue), style=\(traits.userInterfaceStyle.rawValue), direction=\(actualDirection.rawValue), bounds=\(label.bounds), UIKitHeight=\(expected.height), scale=\(scale)"
                if traits.preferredContentSizeCategory == category,
                   traits.userInterfaceStyle == style,
                   actualDirection == direction,
                   abs(label.bounds.width - 180) <= pixel,
                   abs(label.bounds.height - expected.height) <= pixel
                {
                    return (label, expected)
                }
            }
            // 每次仅推进一个主 RunLoop 事件；是否继续由当前环境和几何决定。
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw EnvironmentWaitTimeout(description:
            "Timed out waiting for category=\(category.rawValue), style=\(style.rawValue), direction=\(direction.rawValue), width=180 and UIKit height; actual: \(actualState)"
        )
    }

    private func findLabel(in view: UIView) -> LYGlyphTextLabel? {
        if let label = view as? LYGlyphTextLabel { return label }
        return view.subviews.lazy.compactMap(findLabel).first
    }

    func testOnlyLayoutRelevantTraitChangesInvalidateLayout() throws {
        let fixture = UIKitFixture()
        defer { fixture.close() }
        fixture.label.document = try LYGlyphTextDocument(text: "尺寸类别变化不需要重新排版。")
        fixture.apply()
        _ = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        fixture.label.resetLayoutMeasurementCounts()
        MeasurementCounters.reset()
        // 尺寸类别不在排版环境中：不清空缓存，绘制与测量命中原布局。
        fixture.parent.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            .init(preferredContentSizeCategory: .large), .init(userInterfaceStyle: .light),
            .init(layoutDirection: .leftToRight), .init(horizontalSizeClass: .compact)
        ]), forChild: fixture.child)
        fixture.parent.view.layoutIfNeeded()
        XCTAssertEqual(fixture.label.traitCollection.horizontalSizeClass, .compact)
        _ = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        XCTAssertEqual(MeasurementCounters.traitInvalidations, 0)
        XCTAssertEqual(fixture.label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        // 明暗变化影响动态颜色解析：仍然重新排版。
        fixture.apply(style: .dark)
        _ = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        XCTAssertEqual(MeasurementCounters.traitInvalidations, 1)
        XCTAssertEqual(fixture.label.layoutMeasurementSnapshot.layoutBuildCount, 1)
    }

    @MainActor
    private final class UIKitFixture {
        let parent = UIViewController()
        let child = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 1000))
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 360, height: 800))

        init() {
            parent.addChild(child)
            parent.view.addSubview(child.view)
            child.didMove(toParent: parent)
            child.view.addSubview(label)
            window.rootViewController = parent
            window.makeKeyAndVisible()
        }

        func apply(
            category: UIContentSizeCategory = .large,
            style: UIUserInterfaceStyle = .light,
            direction: UITraitEnvironmentLayoutDirection = .leftToRight
        ) {
            parent.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
                .init(preferredContentSizeCategory: category), .init(userInterfaceStyle: style),
                .init(layoutDirection: direction)
            ]), forChild: child)
            parent.view.layoutIfNeeded()
            label.layoutIfNeeded()
        }

        func close() {
            window.isHidden = true
        }
    }
}
