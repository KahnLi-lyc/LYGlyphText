@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class ActionTests: XCTestCase {
    private func document(_ string: String, _ actions: [LYGlyphTextAction]) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(attributedText: NSAttributedString(string: string), actions: actions)
    }

    private func assertError(
        _ string: String, actions: [LYGlyphTextAction], expected: LYGlyphTextDocumentError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try document(string, actions),
            "\(string.debugDescription) \(actions.map(\.range))",
            file: file,
            line: line
        ) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, expected, file: file, line: line)
        }
    }

    func testPressedStyleDefaultsAndExplicitColors() {
        let style = LYGlyphTextPressedStyle()
        XCTAssertNil(style.foregroundColor)
        XCTAssertEqual(style.backgroundColor, .tertiarySystemFill)
        let explicit = LYGlyphTextPressedStyle(foregroundColor: .systemRed, backgroundColor: nil)
        XCTAssertEqual(explicit.foregroundColor, .systemRed)
        XCTAssertNil(explicit.backgroundColor)
    }

    func testRepeatedIDsAdjacentRangesAndInputOrderArePreserved() throws {
        let second = LYGlyphTextAction(actionID: "repeat", range: NSRange(location: 2, length: 2))
        let first = LYGlyphTextAction(
            actionID: "repeat", range: NSRange(location: 0, length: 2),
            pressedStyle: .init(foregroundColor: .systemOrange, backgroundColor: nil)
        )
        let result = try document("abcd", [second, first])
        XCTAssertEqual(result.actions.map(\.actionID), ["repeat", "repeat"])
        XCTAssertEqual(result.actions.map(\.range), [second.range, first.range])
        XCTAssertEqual(result.actions[1].pressedStyle.foregroundColor, .systemOrange)
        XCTAssertNil(result.actions[1].pressedStyle.backgroundColor)
    }

    func testWhitespaceAndCaseSensitiveIDsAreAcceptedWithoutNormalization() throws {
        let actions = [" ", "A", "a"].enumerated().map {
            LYGlyphTextAction(actionID: $0.element, range: NSRange(location: $0.offset, length: 1))
        }
        XCTAssertEqual(try document("abc", actions).actions.map(\.actionID), [" ", "A", "a"])
    }

    func testEmptyIDPrecedesNumericValidationForThatAction() {
        let range = NSRange(location: Int.max, length: Int.max)
        assertError("a", actions: [.init(actionID: "", range: range)], expected: .emptyActionID(range: range))
    }

    func testInvalidNumericRangesAreRejectedWithoutOverflow() {
        for range in [
            NSRange(location: -1, length: 1), NSRange(location: 0, length: -1),
            NSRange(location: 0, length: 0), NSRange(location: 1, length: 0),
            NSRange(location: 2, length: 1), NSRange(location: 1, length: 1),
            NSRange(location: 0, length: 2), NSRange(location: NSNotFound, length: 1),
            NSRange(location: Int.max, length: Int.max), NSRange(location: 1, length: Int.max),
            NSRange(location: 0, length: Int.max), NSRange(location: Int.min, length: 1)
        ] {
            assertError(
                "a",
                actions: [.init(actionID: "tap", range: range)],
                expected: .invalidActionRange(range: range)
            )
        }
        let emptyRange = NSRange(location: 0, length: 1)
        assertError(
            "",
            actions: [.init(actionID: "tap", range: emptyRange)],
            expected: .invalidActionRange(range: emptyRange)
        )
    }

    func testPartialComposedCharactersAreRejected() {
        for string in ["😀", "👨‍👩‍👧‍👦", "👍🏽", "🇨🇳", "e\u{301}", "\r\n"] {
            let length = (string as NSString).length
            for range in [NSRange(location: 0, length: 1), NSRange(location: 1, length: length - 1)] {
                assertError(
                    string, actions: [.init(actionID: "tap", range: range)],
                    expected: .actionRangeSplitsComposedCharacter(range: range)
                )
            }
        }
    }

    func testWholeComposedCharactersAndMixedScriptsAreAccepted() throws {
        for string in ["😀", "👨‍👩‍👧‍👦", "👍🏽", "🇨🇳", "e\u{301}", "\r\n", "中 English مرحبا"] {
            let range = NSRange(location: 0, length: (string as NSString).length)
            XCTAssertEqual(try document(string, [.init(actionID: "tap", range: range)]).actions.first?.range, range)
        }
    }

    func testStylesMaySplitGraphemeWithoutSplittingActionRange() throws {
        let input = NSMutableAttributedString(string: "e\u{301}", attributes: [
            .font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.systemRed
        ])
        input.addAttributes([
            .font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.systemBlue
        ], range: NSRange(location: 1, length: 1))
        let wholeCluster = NSRange(location: 0, length: 2)
        for actions: [LYGlyphTextAction] in [[], [.init(actionID: "whole", range: wholeCluster)]] {
            let document = try LYGlyphTextDocument(attributedText: input, actions: actions)
            XCTAssertEqual(document.string, "e\u{301}")
            XCTAssertEqual(document.styleRuns.map(\.range), [
                NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)
            ])
            XCTAssertEqual(document.styleRuns.map { $0.font?.pointSize }, [20, 32])
            XCTAssertEqual(document.styleRuns.map(\.color), [.systemRed, .systemBlue])
            XCTAssertEqual(document.actions.map(\.range), actions.map(\.range))
        }
    }

    func testInputOrderValidationPrecedesOverlapCheck() {
        let partial = NSRange(location: 2, length: 1)
        assertError("ab😀", actions: [
            .init(actionID: "one", range: NSRange(location: 0, length: 2)),
            .init(actionID: "two", range: NSRange(location: 1, length: 1)),
            .init(actionID: "three", range: partial)
        ], expected: .actionRangeSplitsComposedCharacter(range: partial))
        let invalid = NSRange(location: 8, length: 1)
        assertError("a", actions: [
            .init(actionID: "first", range: invalid),
            .init(actionID: "", range: NSRange(location: 0, length: 1))
        ], expected: .invalidActionRange(range: invalid))
    }

    func testEqualIncludedAndIntersectingRangesFailEvenWithRepeatedID() {
        for ranges in [
            [NSRange(location: 0, length: 2), NSRange(location: 0, length: 2)],
            [NSRange(location: 0, length: 4), NSRange(location: 1, length: 1)],
            [NSRange(location: 0, length: 3), NSRange(location: 2, length: 2)],
            [NSRange(location: 0, length: 1), NSRange(location: 0, length: 3)]
        ] {
            assertError(
                "abcd",
                actions: ranges.map { .init(actionID: "same", range: $0) },
                expected: .overlappingActionRanges(
                    first: ranges[0], second: ranges[1]
                )
            )
        }
    }

    func testOverlapErrorUsesLocationOrderAndStableInputTies() {
        let left = NSRange(location: 1, length: 3)
        let right = NSRange(location: 3, length: 2)
        assertError("abcdef", actions: [
            .init(actionID: "right", range: right), .init(actionID: "left", range: left)
        ], expected: .overlappingActionRanges(first: left, second: right))
        let shorter = NSRange(location: 1, length: 1)
        assertError("abcdef", actions: [
            .init(actionID: "shorter", range: shorter), .init(actionID: "left", range: left)
        ], expected: .overlappingActionRanges(first: shorter, second: left))
    }

    func testAttachmentValidationPrecedesActionValidation() {
        let invalid = LYGlyphTextAction(actionID: "", range: NSRange(location: 0, length: 0))
        assertError("\u{FFFC}", actions: [invalid], expected: .unsupportedObjectReplacementCharacter(location: 0))
        let input = NSAttributedString(string: "a", attributes: [.attachment: NSTextAttachment()])
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: input, actions: [invalid])) {
            XCTAssertEqual(
                $0 as? LYGlyphTextDocumentError,
                .unsupportedAttachment(range: NSRange(location: 0, length: 1))
            )
        }
    }

    func testOneActionCanSpanTextAndBothAttachmentKinds() throws {
        let image = LYGlyphTextAttachment(id: "image", image: UIImage(), size: CGSize(width: 10, height: 20))
        let view = LYGlyphTextViewAttachment(id: "view", viewID: "badge", size: CGSize(width: 20, height: 10))
        let range = NSRange(location: 0, length: 4)
        let result = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "a\u{FFFC}b\u{FFFC}"),
            attachments: [1: image], viewAttachments: [3: view], actions: [.init(actionID: "all", range: range)]
        )
        XCTAssertEqual(result.actions.first?.range, range)
    }

    func testExistingInitializerVariantsKeepDefaultEmptyActions() throws {
        let empty = NSAttributedString(string: "")
        let documents = try [
            LYGlyphTextDocument(attributedText: empty),
            LYGlyphTextDocument(attributedText: empty, attachments: [:]),
            LYGlyphTextDocument(attributedText: empty, viewAttachments: [:]),
            LYGlyphTextDocument(attributedText: empty, attachments: [:], viewAttachments: [:])
        ]
        XCTAssertTrue(documents.allSatisfy(\.actions.isEmpty))
    }
}
