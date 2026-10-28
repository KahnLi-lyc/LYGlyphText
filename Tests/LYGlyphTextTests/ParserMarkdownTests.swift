@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class ParserMarkdownTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 17)

    private func text(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font])
    }

    private func font(_ doc: LYGlyphTextDocument, at location: Int) -> UIFont? {
        doc.styleRuns.first { NSLocationInRange(location, $0.range) }?.font
    }

    func testLinksReplaceMarkupAndCreateActionsInOrder() throws {
        let parser = LYGlyphTextParser(rules: [.markdownLinks(), .mentions()])
        let doc = try parser.document(from: text("看[官网](https://example.com/a) 和 [帮助](help) @小明"))
        XCTAssertEqual(doc.string, "看官网 和 帮助 @小明")
        XCTAssertEqual(doc.actions.map(\.actionID), ["https://example.com/a", "help", "mention:小明"])
        let source = doc.string as NSString
        XCTAssertEqual(doc.actions.map { source.substring(with: $0.range) }, ["官网", "帮助", "@小明"])
        XCTAssertEqual(doc.styleRuns.first { NSLocationInRange(1, $0.range) }?.color, UIColor.link)
    }

    func testEmphasisDerivesFontsAndKeepsUnpairedMarkers() throws {
        let doc = try LYGlyphTextParser(rules: [.markdownEmphasis()])
            .document(from: text("**粗** *斜* `code` 2*3 **未闭合"))
        XCTAssertEqual(doc.string, "粗 斜 code 2*3 **未闭合")
        XCTAssertTrue(try XCTUnwrap(font(doc, at: 0)).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(try XCTUnwrap(font(doc, at: 2)).fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertTrue(try XCTUnwrap(font(doc, at: 4)).fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        XCTAssertEqual(font(doc, at: 4)?.pointSize, 17)
        XCTAssertFalse(try XCTUnwrap(font(doc, at: 9)).fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testMarkdownWithEmoticonsShiftsAttachmentsAndSkipsAttachmentLinks() throws {
        let smile = try XCTUnwrap(UIImage(systemName: "face.smiling"))
        let parser = LYGlyphTextParser(rules: [
            .emoticons(["[笑]": smile], size: CGSize(width: 16, height: 16)), .markdownEmphasis(), .markdownLinks()
        ])
        let doc = try parser.document(from: text("**加粗**[笑][链接](u) [[笑]](x) [笑]"))
        let source = doc.string as NSString
        XCTAssertEqual(doc.string, "加粗\u{FFFC}链接 [\u{FFFC}](x) \u{FFFC}")
        XCTAssertEqual(doc.actions.map(\.actionID), ["u"])
        XCTAssertEqual(source.substring(with: doc.actions[0].range), "链接")
        for location in doc.attachments.keys {
            XCTAssertEqual(source.character(at: location), 0xFFFC)
        }
        XCTAssertEqual(doc.attachments.count, 3)
    }

    func testEmptyLinkTextAndComposedCharactersAreSafe() throws {
        let doc = try LYGlyphTextParser(rules: [.markdownLinks()])
            .document(from: text("[ ](a) [e\u{301}👨‍👩‍👧‍👦](b)"))
        XCTAssertEqual(doc.string, "[ ](a) e\u{301}👨‍👩‍👧‍👦")
        XCTAssertEqual(doc.actions.map(\.actionID), ["b"])
        XCTAssertEqual(doc.actions.first?.range.length, ("e\u{301}👨‍👩‍👧‍👦" as NSString).length)
    }
}
