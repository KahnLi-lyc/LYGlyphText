@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class DocumentTests: XCTestCase {
    func testSnapshotIsolatesMutableStringAndParagraph() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let input = NSMutableAttributedString(string: "原文 👨‍👩‍👧‍👦", attributes: [.paragraphStyle: paragraph])
        let document = try LYGlyphTextDocument(attributedText: input)
        input.mutableString.setString("已替换")
        paragraph.alignment = .left
        XCTAssertEqual(document.string, "原文 👨‍👩‍👧‍👦")
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = document
        let layout = label.measuredLayout(width: 350)
        XCTAssertGreaterThan(try XCTUnwrap(layout.lines.first).baseline.x, 100)
    }

    func testStandardAttachmentFailsExplicitly() {
        let input = NSAttributedString(string: "x", attributes: [.attachment: NSTextAttachment()])
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: input)) {
            XCTAssertEqual(
                $0 as? LYGlyphTextDocumentError,
                .unsupportedAttachment(range: NSRange(location: 0, length: 1))
            )
        }
    }

    func testObjectReplacementCharacterFailsWithUTF16Location() {
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: NSAttributedString(string: "😀\u{FFFC}"))) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 2))
        }
    }

    func testMixedStylesAreRetained() throws {
        let input = NSMutableAttributedString(string: "Hello你好😀", attributes: [.font: UIFont.systemFont(ofSize: 18)])
        input.addAttributes(
            [.font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.systemRed],
            range: NSRange(location: 5, length: 2)
        )
        let document = try LYGlyphTextDocument(attributedText: input)
        XCTAssertEqual(document.styleRuns.first(where: { NSLocationInRange(5, $0.range) })?.font?.pointSize, 30)
        XCTAssertEqual(
            document.styleRuns.first(where: { NSLocationInRange(5, $0.range) })?.color,
            .systemRed
        )
        XCTAssertEqual((document.string as NSString).length, 9)
    }

    func testPlainTextInitializerMatchesEquivalentAttributedText() throws {
        let font = UIFont.systemFont(ofSize: 18)
        let plain = try LYGlyphTextDocument(text: "Hello 你好 😀", font: font, foregroundColor: .systemRed)
        let attributed = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "Hello 你好 😀", attributes: [.font: font, .foregroundColor: UIColor.systemRed]
        ))
        XCTAssertEqual(plain.string, attributed.string)
        XCTAssertEqual(plain.styleRuns.map(\.range), attributed.styleRuns.map(\.range))
        XCTAssertEqual(plain.styleRuns.first?.font, font)
        XCTAssertEqual(plain.styleRuns.first?.color, .systemRed)
        XCTAssertTrue(plain.attachments.isEmpty && plain.viewAttachments.isEmpty && plain.actions.isEmpty)
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = plain
        let plainSize = label.measuredLayout(width: 120).size
        label.document = attributed
        XCTAssertEqual(plainSize, label.measuredLayout(width: 120).size)
    }

    func testPlainTextInitializerDefaultsToDynamicBodyAndLabelColor() throws {
        let document = try LYGlyphTextDocument(text: "默认样式")
        // 未设置的字体与颜色快照为 nil，与无属性 NSAttributedString 相同，排版时取动态 body 与 label 色；
        // 动态字号跟随环境的行为由 EnvironmentTests 覆盖。
        XCTAssertNil(document.styleRuns.first?.font)
        XCTAssertNil(document.styleRuns.first?.color)
        XCTAssertNoThrow(try LYGlyphTextDocument(text: ""))
    }

    func testPlainTextInitializerRejectsObjectReplacementCharacter() {
        XCTAssertThrowsError(try LYGlyphTextDocument(text: "😀\u{FFFC}")) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 2))
        }
    }
}
