import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class StyleTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)

    private func layout(
        _ string: String,
        attributes: [NSAttributedString.Key: Any] = [:],
        width: CGFloat = 180,
        limit: Int = 0
    ) throws -> LYGlyphTextLayout {
        var attributes = attributes
        attributes[.font] = attributes[.font] ?? font
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: string,
            attributes: attributes
        ))
        return ResolvedText(document: document, traits: UITraitCollection()).layout(
            width: width, insets: .zero, scale: 2, numberOfLines: limit
        )
    }

    func testNativeLineSeparatorPreservesContinuationIndentAndSpacing() {
        func frame(_ separator: String, spacing: CGFloat) -> TextFrame {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 28
            style.headIndent = 6
            style.lineSpacing = spacing
            let text = NSAttributedString(
                string: "first\(separator)second",
                attributes: [.font: font, .paragraphStyle: style]
            )
            return TextFrame(framesetter: CTFramesetterCreateWithAttributedString(text), width: 300, scale: 2)
        }
        let soft = frame("\u{2028}", spacing: 12)
        let plain = frame("\u{2028}", spacing: 0)
        let hard = frame("\n", spacing: 12)
        XCTAssertEqual(soft.lines.count, 2)
        XCTAssertEqual(soft.origins[0].x, 28, accuracy: 0.01)
        XCTAssertEqual(soft.origins[1].x, 6, accuracy: 0.01)
        XCTAssertEqual(hard.origins[1].x, 28, accuracy: 0.01)
        XCTAssertEqual(
            (soft.origins[0].y - soft.origins[1].y) - (plain.origins[0].y - plain.origins[1].y),
            12,
            accuracy: 0.01
        )
    }

    func testKernChangesAdvanceAndBreaks() throws {
        let text = "MMMMMMMMMMMM"
        let normal = try layout(text, width: 110)
        let wide = try layout(text, attributes: [.kern: 2], width: 110)
        XCTAssertGreaterThan(wide.lines.count, normal.lines.count)
        let a = try layout("MMMM", width: 400)
        let b = try layout("MMMM", attributes: [.kern: 2], width: 400)
        XCTAssertGreaterThan(b.size.width, a.size.width)
        let negative = try layout("MMMM", attributes: [.kern: -2], width: 400)
        XCTAssertLessThan(negative.size.width, a.size.width)
    }

    func testParagraphSpacingAndIndentAffectActualGeometry() throws {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 28
        style.headIndent = 6
        style.lineSpacing = 12
        let base = try layout("one two three four five six seven eight nine", width: 100)
        let styled = try layout(
            "one two three four five six seven eight nine",
            attributes: [.paragraphStyle: style],
            width: 100
        )
        XCTAssertEqual(styled.lines[0].baseline.x, 28, accuracy: 0.01)
        XCTAssertEqual(styled.lines[1].baseline.x, 6, accuracy: 0.01)
        XCTAssertGreaterThan(
            styled.lines[1].baseline.y - styled.lines[0].baseline.y,
            base.lines[1].baseline.y - base.lines[0].baseline.y + 10
        )
    }

    func testImmutableSnapshotSplitsWholeParagraphsAndUsesFirstCharacterStyle() throws {
        let first = NSMutableParagraphStyle()
        first.lineSpacing = -12
        first.headIndent = -12
        first.firstLineHeadIndent = 12
        first.tailIndent = -12
        first.minimumLineHeight = 32
        first.maximumLineHeight = 20
        let conflicting = NSMutableParagraphStyle()
        conflicting.lineSpacing = 77
        let second = NSMutableParagraphStyle()
        second.lineSpacing = 12
        let text = NSMutableAttributedString(string: "ab\ncd\n", attributes: [
            .paragraphStyle: first, .kern: -2, .baselineOffset: -8,
            .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.byWord.rawValue,
            .strikethroughStyle: NSUnderlineStyle.double.rawValue, .backgroundColor: UIColor.red,
            .underlineColor: UIColor.green, .strikethroughColor: UIColor.blue, .ligature: 0
        ])
        text.addAttribute(.paragraphStyle, value: conflicting, range: NSRange(location: 1, length: 2))
        text.addAttribute(.paragraphStyle, value: second, range: NSRange(location: 3, length: 3))
        let doc = try LYGlyphTextDocument(attributedText: text)
        first.lineSpacing = 99
        second.lineSpacing = 98
        text.setAttributes([:], range: NSRange(location: 0, length: text.length))
        XCTAssertEqual(
            doc.styleRuns.map(\.range),
            [NSRange(location: 0, length: 1), NSRange(location: 1, length: 2), NSRange(location: 3, length: 3)]
        )
        for run in doc.styleRuns.prefix(2) {
            XCTAssertEqual(run.paragraph.lineSpacing, -12)
            XCTAssertEqual(run.paragraph.headIndent, -12)
            XCTAssertEqual(run.paragraph.firstLineHeadIndent, 12)
            XCTAssertEqual(run.paragraph.tailIndent, -12)
            XCTAssertEqual(run.paragraph.minimumLineHeight, 32)
            XCTAssertEqual(run.paragraph.maximumLineHeight, 0)
            XCTAssertEqual(run.kern, -2)
            XCTAssertEqual(run.baselineOffset, -8)
            XCTAssertEqual(run.ligature, 0)
            XCTAssertEqual(run.background, .red)
            XCTAssertEqual(run.underlineColor, .green)
            XCTAssertEqual(run.strikethroughColor, .blue)
        }
        XCTAssertEqual(doc.styleRuns.last?.paragraph.lineSpacing, 12)
        let sameAttributes = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "a\nb"))
        XCTAssertEqual(
            sameAttributes.styleRuns.map(\.range),
            [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1)]
        )
    }

    func testNumericDefaultsAndStandardDecorationBits() throws {
        for invalid: Any in ["2", CGFloat.nan, CGFloat.infinity, -CGFloat.infinity, CGFloat.greatestFiniteMagnitude] {
            let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "x", attributes: [
                .underlineStyle: invalid, .strikethroughStyle: invalid, .ligature: invalid
            ]))
            XCTAssertEqual(doc.styleRuns[0].underlineStyle, 0)
            XCTAssertEqual(doc.styleRuns[0].strikethroughStyle, 0)
            XCTAssertEqual(doc.styleRuns[0].ligature, 1)
        }
        for value in [3, 4, 8, 0x500, 0x1000, 0x10000, -1] {
            XCTAssertEqual(StyleNumber.decoration(value), 0)
        }
        for base in [0, 1, 2, 9] {
            for pattern in [0, 0x100, 0x200, 0x300, 0x400] {
                for byWord in [0, 0x8000] {
                    let raw = base | pattern | byWord
                    XCTAssertEqual(StyleNumber.decoration(raw), raw)
                }
            }
        }
        for invalid: Any in ["2", CGFloat.nan, CGFloat.infinity, -CGFloat.infinity] {
            let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "x", attributes: [
                .kern: invalid, .baselineOffset: invalid
            ]))
            XCTAssertNil(doc.styleRuns[0].kern)
            XCTAssertEqual(doc.styleRuns[0].baselineOffset, 0)
        }
        for raw in [0, 1, 2] {
            XCTAssertEqual(StyleNumber.integer(raw, allowed: 0 ... 2), raw)
        }
        XCTAssertNil(StyleNumber.integer(0.5, allowed: 0 ... 2))
    }

    func testNativeParagraphMetricsMatchResolvedBaselinesAndHeight() throws {
        for spacing in [-12.0, 12.0] {
            for string in ["one two three four five six seven eight nine", "one\ntwo\nthree\n"] {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = spacing
                style.paragraphSpacing = spacing
                style.paragraphSpacingBefore = spacing
                style.firstLineHeadIndent = 12
                style.headIndent = -12
                style.tailIndent = -12
                style.minimumLineHeight = 28
                style.lineHeightMultiple = 1.4
                let actual = try layout(string, attributes: [.paragraphStyle: style], width: 105)
                let nativeString = string.hasSuffix("\n") ? string + "\u{200B}" : string
                let native = TextFrame(framesetter: CTFramesetterCreateWithAttributedString(NSAttributedString(
                    string: nativeString, attributes: [.font: font, .paragraphStyle: style]
                )), width: 105, scale: 2)
                XCTAssertEqual(actual.lines.count, native.lines.count)
                XCTAssertEqual(actual.size.height, LayoutNumber.pixelCeil(native.contentHeight, scale: 2))
                for (line, origin) in zip(actual.lines, native.origins) {
                    XCTAssertEqual(line.baseline.x, origin.x, accuracy: 0.01)
                    XCTAssertEqual(line.baseline.y, native.height - origin.y, accuracy: 0.01)
                }
            }
        }
    }

    func testExplicitMaximumLineHeightAllowsNativeOverlap() throws {
        let style = NSMutableParagraphStyle()
        style.maximumLineHeight = 8
        let actual = try layout("A\nB\nC", attributes: [.paragraphStyle: style])
        XCTAssertEqual(actual.lines.count, 3)
        XCTAssertEqual(actual.lines[1].baseline.y - actual.lines[0].baseline.y, 8, accuracy: 0.01)
        XCTAssertLessThan(actual.size.height, font.lineHeight * 2)
    }

    func testBaselineOffsetMovesGlyphsAndAttachmentGeometry() throws {
        let base = try layout("xx")
        for shift in [-8.0, 8.0] {
            let shifted = try layout("xx", attributes: [.baselineOffset: shift])
            let run = (CTLineGetGlyphRuns(shifted.lines[0].text) as! [CTRun])[0]
            var point = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &point)
            XCTAssertEqual(point.y, shift, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(shifted.size.height, base.size.height)
        }
    }

    func testLigatureZeroAndOneShapeDifferentlyAndDefaultKernIsOmitted() throws {
        let georgia = try XCTUnwrap([
            "TimesNewRomanPSMT",
            "Baskerville",
            "HoeflerText-Regular",
            "Palatino-Roman",
            "HelveticaNeue"
        ].compactMap { UIFont(name: $0, size: 28) }.first { font in
            let off = CTLineCreateWithAttributedString(NSAttributedString(
                string: "fi",
                attributes: [.font: font, .ligature: 0]
            ))
            let on = CTLineCreateWithAttributedString(NSAttributedString(
                string: "fi",
                attributes: [.font: font, .ligature: 1]
            ))
            return CTLineGetGlyphCount(off) > CTLineGetGlyphCount(on)
        })
        XCTAssertEqual(georgia.fontName, "Baskerville")
        let off = try layout("fi", attributes: [.font: georgia, .ligature: 0])
        let on = try layout("fi", attributes: [.font: georgia, .ligature: 1])
        XCTAssertGreaterThan(CTLineGetGlyphCount(off.lines[0].text), CTLineGetGlyphCount(on.lines[0].text))
        for kern: CGFloat? in [nil, 0, -2, 2] {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if let kern { attrs[.kern] = kern }
            let measured = try layout("AV", attributes: attrs)
            let run = (CTLineGetGlyphRuns(measured.lines[0].text) as! [CTRun])[0]
            let stored = (CTRunGetAttributes(run) as NSDictionary)[kCTKernAttributeName] as? NSNumber
            XCTAssertEqual(stored?.doubleValue, kern.map(Double.init))
        }
    }

    func testWrappingConfigurationOverridesParagraphModeAndInvalidatesLabel() throws {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        let text = NSAttributedString(string: "aa aaaaaa aa aaaaaa", attributes: [.font: font, .paragraphStyle: style])
        let view = LYGlyphTextLabel(frame: .zero)
        view.document = try LYGlyphTextDocument(attributedText: text)
        let word = view.measuredLayout(width: 88)
        view.configuration.wrapping = .character
        let character = view.measuredLayout(width: 88)
        XCTAssertGreaterThan(word.lines.count, 1)
        XCTAssertGreaterThan(character.lines.count, 1)
        XCTAssertNotEqual(word.lines.map(\.visibleSourceRanges), character.lines.map(\.visibleSourceRanges))
        XCTAssertEqual(LYGlyphTextConfiguration().verticalAlignment, .top)
    }

    func testUnconstrainedPositiveIndentDoesNotCauseWrapping() throws {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 40
        style.headIndent = 20
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "one two three",
            attributes: [.font: font, .paragraphStyle: style]
        ))
        let result = ResolvedText(document: doc, traits: UITraitCollection()).layout(
            width: nil,
            insets: .zero,
            scale: 2
        )
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].baseline.x, 40, accuracy: 0.01)
    }

    func testExtremeFiniteMetricsFallbackBeforeCoreTextAndKeepDocumentSnapshot() throws {
        for extreme in [
            CGFloat.greatestFiniteMagnitude,
            -CGFloat.greatestFiniteMagnitude,
            CGFloat(Float.greatestFiniteMagnitude),
            -CGFloat(Float.greatestFiniteMagnitude),
            CGFloat(Float.greatestFiniteMagnitude) / 4,
            -CGFloat(Float.greatestFiniteMagnitude) / 4
        ] {
            for key in [NSAttributedString.Key.kern, .baselineOffset] {
                let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
                    string: "one two three",
                    attributes: [.font: font, key: extreme]
                ))
                let resolved = ResolvedText(document: doc, traits: UITraitCollection())
                let actual = resolved.layout(width: 120, insets: .zero, scale: 2)
                let normal = try layout("one two three", width: 120)
                XCTAssertEqual(actual.size, normal.size)
                XCTAssertEqual(doc.styleRuns[0].kern, key == .kern ? extreme : nil)
                XCTAssertEqual(doc.styleRuns[0].baselineOffset, key == .baselineOffset ? extreme : 0)
            }
            let setters: [(NSMutableParagraphStyle, CGFloat) -> Void] = [
                { $0.lineSpacing = $1 }, { $0.paragraphSpacing = $1 }, { $0.paragraphSpacingBefore = $1 },
                { $0.firstLineHeadIndent = $1 }, { $0.headIndent = $1 }, { $0.tailIndent = $1 },
                { $0.minimumLineHeight = $1 }, { $0.maximumLineHeight = $1 }, { $0.lineHeightMultiple = $1 }
            ]
            for set in setters {
                let style = NSMutableParagraphStyle()
                set(style, extreme)
                let actual = try layout("one two three\nfour", attributes: [.paragraphStyle: style], width: 120)
                let normal = try layout("one two three\nfour", width: 120)
                XCTAssertEqual(actual.size, normal.size)
                XCTAssertTrue(actual.lines.allSatisfy { $0.baseline.x.isFinite && $0.baseline.y.isFinite })
            }
        }
    }

    func testOverflowingInsetWidthAndScaleNeverEscapeAsNonfiniteGeometry() throws {
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(string: "text", attributes: [.font: font]))
        let resolved = ResolvedText(document: doc, traits: UITraitCollection())
        let extreme = CGFloat.greatestFiniteMagnitude
        for width: CGFloat? in [nil, extreme, .infinity, .nan] {
            let actual = resolved.layout(
                width: width,
                insets: UIEdgeInsets(top: extreme, left: extreme, bottom: extreme, right: extreme),
                scale: extreme
            )
            XCTAssertTrue(actual.size.width.isFinite && actual.size.height.isFinite)
            XCTAssertTrue(actual.lines.allSatisfy { $0.baseline.x.isFinite && $0.baseline.y.isFinite })
        }
    }

    func testBaselineOffsetMovesImageAndViewUsingFinalRunPosition() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { $0.fill(CGRect(
            x: 0,
            y: 0,
            width: 10,
            height: 10
        )) }
        for shift: CGFloat in [-8, 8] {
            let doc = try LYGlyphTextDocument(
                attributedText: NSAttributedString(
                    string: "A\u{FFFC}B\u{FFFC}",
                    attributes: [.font: font, .baselineOffset: shift]
                ),
                attachments: [1: LYGlyphTextAttachment(id: "image", image: image, size: CGSize(width: 10, height: 10))],
                viewAttachments: [3: LYGlyphTextViewAttachment(
                    id: "view",
                    viewID: "test",
                    size: CGSize(width: 10, height: 10)
                )]
            )
            let result = ResolvedText(document: doc, traits: UITraitCollection()).layout(
                width: 180,
                insets: .zero,
                scale: 2
            )
            let baseline = try XCTUnwrap(result.lines.first).baseline.y
            XCTAssertEqual(
                try XCTUnwrap(result.attachments.first).rect.maxY,
                baseline - shift - font.descender,
                accuracy: 0.01
            )
            XCTAssertEqual(
                try XCTUnwrap(result.viewAttachments.first).rect.maxY,
                baseline - shift - font.descender,
                accuracy: 0.01
            )
        }
    }

    func testTrailingEmptyLineInheritsDelimiterParagraphAndStyle() throws {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 48
        style.firstLineHeadIndent = 12
        let result = try layout("one\n", attributes: [.paragraphStyle: style])
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[1].baseline.y - result.lines[0].baseline.y, 48, accuracy: 0.01)
        XCTAssertEqual(result.lines[1].baseline.x, 12, accuracy: 0.01)
    }

    func testLargeRepresentableMetricsProduceFiniteGeometryOrSingleSafeRetry() throws {
        for value: CGFloat in [1e20, -1e20] {
            let setters: [(NSMutableParagraphStyle, CGFloat) -> Void] = [
                { $0.lineSpacing = $1 }, { $0.paragraphSpacing = $1 }, { $0.paragraphSpacingBefore = $1 },
                { $0.firstLineHeadIndent = $1 }, { $0.headIndent = $1 }, { $0.tailIndent = $1 },
                { $0.minimumLineHeight = $1 }, { $0.maximumLineHeight = $1 }, { $0.lineHeightMultiple = $1 }
            ]
            for (index, set) in setters.enumerated() {
                let style = NSMutableParagraphStyle()
                set(style, value)
                let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
                    string: "one two three\nfour",
                    attributes: [.font: font, .paragraphStyle: style]
                ))
                let resolved = ResolvedText(document: doc, traits: UITraitCollection())
                let actual = resolved.layout(width: 120, insets: .zero, scale: 2, numberOfLines: 2)
                XCTAssertLessThanOrEqual(resolved.fallbackCount, 1)
                XCTAssertEqual(resolved.fallbackCount, 0)
                let normal = try layout("one two three\nfour", width: 120, limit: 2)
                XCTAssertEqual(actual.size, normal.size)
                XCTAssertEqual(doc.styleRuns[0].paragraph.lineSpacing, index == 0 ? value : 0)
                XCTAssertTrue(actual.size.width.isFinite && actual.size.height.isFinite)
                XCTAssertTrue(actual.lines.allSatisfy { $0.baseline.x.isFinite && $0.baseline.y.isFinite })
            }
            for key in [NSAttributedString.Key.kern, .baselineOffset] {
                let actual = try layout("one two three\nfour", attributes: [key: value], width: 120, limit: 2)
                XCTAssertTrue(actual.size.width.isFinite && actual.size.height.isFinite)
                XCTAssertTrue(actual.lines.allSatisfy { $0.baseline.x.isFinite && $0.baseline.y.isFinite })
            }
        }
    }

    func testNonfiniteParagraphValuesAndNegativeHeightValuesNormalizeDeterministically() {
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = value
            style.paragraphSpacing = value
            style.paragraphSpacingBefore = value
            style.firstLineHeadIndent = value
            style.headIndent = value
            style.tailIndent = value
            style.minimumLineHeight = value
            style.maximumLineHeight = value
            style.lineHeightMultiple = value
            let snapshot = ParagraphStyle(style)
            XCTAssertEqual([
                snapshot.lineSpacing,
                snapshot.paragraphSpacing,
                snapshot.paragraphSpacingBefore,
                snapshot.firstLineHeadIndent,
                snapshot.headIndent,
                snapshot.tailIndent,
                snapshot.minimumLineHeight,
                snapshot.maximumLineHeight,
                snapshot.lineHeightMultiple
            ], Array(
                repeating: 0,
                count: 9
            ))
        }
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = -12
        style.maximumLineHeight = -12
        style.lineHeightMultiple = -12
        let snapshot = ParagraphStyle(style)
        XCTAssertEqual(snapshot.minimumLineHeight, 0)
        XCTAssertEqual(snapshot.maximumLineHeight, 0)
        XCTAssertEqual(snapshot.lineHeightMultiple, 0)
    }

    func testExtremeStyleMeasurementNeverCallsViewProvider() throws {
        var calls = 0
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 1e20
        let view = LYGlyphTextLabel(frame: .zero)
        view.viewProvider = LYGlyphTextAttachmentViewProvider { _ in calls += 1
            return UIView()
        }
        view.document = try LYGlyphTextDocument(
            attributedText: NSAttributedString(
                string: "one\n\u{FFFC}\nthree",
                attributes: [.font: font, .paragraphStyle: style]
            ),
            viewAttachments: [4: .init(id: "view", viewID: "fixture", size: CGSize(width: 20, height: 30))]
        )
        view.configuration.numberOfLines = 2
        let result = view.measuredLayout(width: 120)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertTrue(result.viewAttachments
            .allSatisfy {
                $0.rect.minX.isFinite && $0.rect.minY.isFinite && $0.rect.maxX.isFinite && $0.rect.maxY.isFinite
            })
    }

    func testInvalidNativeFrameRetriesOnlyOnceWithoutChangingSnapshot() throws {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = -100
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "one two three four five six seven eight nine",
            attributes: [.font: font, .paragraphStyle: style]
        ))
        let resolved = ResolvedText(document: doc, traits: UITraitCollection())
        let actual = resolved.layout(width: 80, insets: .zero, scale: 2)
        XCTAssertEqual(resolved.fallbackCount, 1)
        let normal = try layout("one two three four five six seven eight nine", width: 80)
        XCTAssertEqual(actual.size, normal.size)
        XCTAssertEqual(actual.lines.map(\.baseline), normal.lines.map(\.baseline))
        XCTAssertEqual(doc.styleRuns[0].paragraph.lineSpacing, -100)
        XCTAssertTrue(actual.size.width.isFinite && actual.size.height.isFinite)
    }

    func testExtremeMetricsAreNormalizedInResolvedAttributesBeforeFrameCreation() throws {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1e20
        style.paragraphSpacing = 1e20
        style.paragraphSpacingBefore = 1e20
        style.firstLineHeadIndent = 1e20
        style.headIndent = 1e20
        style.tailIndent = 1e20
        style.minimumLineHeight = 1e20
        style.maximumLineHeight = 1e20
        style.lineHeightMultiple = 1e20
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "test",
            attributes: [.font: font, .paragraphStyle: style, .kern: 1e20, .baselineOffset: -1e20]
        ))
        let resolved = ResolvedText(document: doc, traits: UITraitCollection())
        let line = CTTypesetterCreateLine(
            CTFramesetterGetTypesetter(resolved.framesetter),
            CFRange(location: 0, length: 4)
        )
        let run = try XCTUnwrap(try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first))
        let attrs = CTRunGetAttributes(run) as NSDictionary
        XCTAssertNil(attrs[kCTKernAttributeName])
        XCTAssertEqual((attrs[kCTBaselineOffsetAttributeName] as? NSNumber)?.doubleValue, 0)
        let paragraphValue = try XCTUnwrap(attrs[kCTParagraphStyleAttributeName])
        // Core Foundation 类型不支持条件 downcast；值来自明确的 Core Text 属性键。
        // swiftformat:disable:next noForceUnwrapInTests
        let paragraph = paragraphValue as! CTParagraphStyle
        for spec: CTParagraphStyleSpecifier in [
            .lineSpacingAdjustment,
            .paragraphSpacing,
            .paragraphSpacingBefore,
            .firstLineHeadIndent,
            .headIndent,
            .tailIndent,
            .minimumLineHeight,
            .maximumLineHeight,
            .lineHeightMultiple
        ] {
            var value: CGFloat = -1
            CTParagraphStyleGetValueForSpecifier(paragraph, spec, MemoryLayout<CGFloat>.size, &value)
            XCTAssertEqual(value, 0)
        }
        XCTAssertEqual(resolved.fallbackCount, 0)
        XCTAssertEqual(doc.styleRuns[0].kern, 1e20)
        XCTAssertEqual(doc.styleRuns[0].baselineOffset, -1e20)
    }

    func testNaturalWidthDoesNotCombineIndentFromDifferentParagraph() throws {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 50
        let text = NSMutableAttributedString(string: "x\nMMMMMMMMMMMM", attributes: [.font: font])
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: 2))
        let doc = try LYGlyphTextDocument(attributedText: text)
        let result = ResolvedText(document: doc, traits: UITraitCollection()).layout(
            width: nil,
            insets: .zero,
            scale: 2
        )
        let native = CTLineCreateWithAttributedString(NSAttributedString(
            string: "MMMMMMMMMMMM",
            attributes: [.font: font]
        ))
        XCTAssertEqual(
            result.size.width,
            LayoutNumber.pixelCeil(CGFloat(CTLineGetTypographicBounds(native, nil, nil, nil)), scale: 2)
        )
        XCTAssertEqual(result.lines.count, 2)
    }

    func testOrdinarySignedMetricSnapshotsAndResolvedParagraphValuesDoNotClamp() throws {
        for value: CGFloat in [-12, 12] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = value
            style.paragraphSpacing = value
            style.paragraphSpacingBefore = value
            style.firstLineHeadIndent = value
            style.headIndent = value
            style.tailIndent = value
            let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: "MM",
                attributes: [.font: font, .paragraphStyle: style]
            ))
            let snapshot = doc.styleRuns[0].paragraph
            XCTAssertEqual(
                [
                    snapshot.lineSpacing,
                    snapshot.paragraphSpacing,
                    snapshot.paragraphSpacingBefore,
                    snapshot.firstLineHeadIndent,
                    snapshot.headIndent,
                    snapshot.tailIndent
                ],
                Array(repeating: value, count: 6)
            )
            let resolved = ResolvedText(document: doc, traits: UITraitCollection())
            let line = CTTypesetterCreateLine(
                CTFramesetterGetTypesetter(resolved.framesetter),
                CFRange(location: 0, length: 2)
            )
            let run = try XCTUnwrap(try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first))
            let paragraph =
                try XCTUnwrap(
                    (CTRunGetAttributes(run) as NSDictionary)[kCTParagraphStyleAttributeName]
                ) as! CTParagraphStyle
            for spec: CTParagraphStyleSpecifier in [
                .lineSpacingAdjustment,
                .paragraphSpacing,
                .paragraphSpacingBefore,
                .firstLineHeadIndent,
                .headIndent,
                .tailIndent
            ] {
                var actual: CGFloat = 0
                CTParagraphStyleGetValueForSpecifier(paragraph, spec, MemoryLayout<CGFloat>.size, &actual)
                XCTAssertEqual(actual, value)
            }
        }
    }
}
