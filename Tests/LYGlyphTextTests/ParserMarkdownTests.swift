import CoreText
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

    /// 真斜体字形或合成倾斜矩阵都算倾斜。
    private func isSlanted(_ font: UIFont?) -> Bool {
        guard let font else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.traitItalic) || CTFontGetMatrix(font as CTFont).c != 0
    }

    private func png(_ doc: LYGlyphTextDocument) throws -> Data {
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        label.document = doc
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(label.bounds)
            label.layer.render(in: context.cgContext)
        }
        return try XCTUnwrap(image.pngData())
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
        XCTAssertTrue(isSlanted(font(doc, at: 2)))
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

    func testChineseItalicIsRecognizedAndSlanted() throws {
        let doc = try LYGlyphTextParser(rules: [.markdownEmphasis()]).document(from: text("我*很*好"))
        XCTAssertEqual(doc.string, "我很好")
        XCTAssertTrue(isSlanted(font(doc, at: 1)))
        XCTAssertEqual(font(doc, at: 1)?.pointSize, 17)
        XCTAssertFalse(isSlanted(font(doc, at: 0)))
        // 倾斜必须真正画出来，而不是只改了字体描述。
        let plain = try LYGlyphTextDocument(attributedText: text("我很好"))
        XCTAssertNotEqual(try png(doc), try png(plain))
    }

    func testLatinItalicKeepsRealItalicFont() throws {
        let doc = try LYGlyphTextParser(rules: [.markdownEmphasis()]).document(from: text("a *word* b"))
        XCTAssertEqual(doc.string, "a word b")
        let italic = try XCTUnwrap(font(doc, at: 2))
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertEqual(CTFontGetMatrix(italic as CTFont).c, 0)
    }

    func testMarkersNextToSpacesOrAsciiWordsStayLiteral() throws {
        let parser = LYGlyphTextParser(rules: [.markdownEmphasis()])
        for literal in ["a * b * c", "2*3*4", "snake*case*x", "** 粗 **"] {
            XCTAssertEqual(try parser.document(from: text(literal)).string, literal)
        }
    }

    func testCodeSpansAndLinkURLsAreNotEmphasized() throws {
        let parser = LYGlyphTextParser(rules: [.markdownEmphasis(), .markdownLinks()])
        let doc = try parser.document(from: text("`a**b**c` [文档](https://x.com/*a*) [**粗**](u)"))
        XCTAssertEqual(doc.string, "a**b**c 文档 粗")
        let code = try XCTUnwrap(font(doc, at: 1))
        XCTAssertTrue(code.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        XCTAssertFalse(code.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(doc.actions.map(\.actionID), ["https://x.com/*a*", "u"])
        let source = doc.string as NSString
        XCTAssertEqual(source.substring(with: doc.actions[1].range), "粗")
        XCTAssertTrue(try XCTUnwrap(font(doc, at: doc.actions[1].range.location)).fontDescriptor.symbolicTraits
            .contains(.traitBold))
    }
}
