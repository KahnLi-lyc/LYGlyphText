@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class ParserTests: XCTestCase {
    private let smile = UIImage(systemName: "face.smiling")!

    private func text(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: 17)])
    }

    func testLinksMentionsAndTopicsBecomeActionsInSourceOrder() throws {
        let parser = LYGlyphTextParser(rules: [.links(), .mentions(), .topics()])
        let doc = try parser.document(from: text("@小明 看 #春天# 详情 https://example.com/a?b=1 。"))
        XCTAssertEqual(doc.actions.map(\.actionID), ["mention:小明", "topic:春天", "https://example.com/a?b=1"])
        let source = doc.string as NSString
        XCTAssertEqual(
            doc.actions.map { source.substring(with: $0.range) },
            ["@小明", "#春天#", "https://example.com/a?b=1"]
        )
        let color = doc.styleRuns.first { NSLocationInRange(doc.actions[0].range.location, $0.range) }?.color
        XCTAssertEqual(color, UIColor.link)
    }

    func testEarlierRulesWinOverlapsAndMatchesKeepComposedCharacters() throws {
        let parser = LYGlyphTextParser(rules: [.links(), .topics()])
        let doc = try parser.document(from: text("访问 https://example.com/#a#b 结束"))
        XCTAssertEqual(doc.actions.count, 1)
        XCTAssertTrue(doc.actions[0].actionID.hasPrefix("https://example.com/"))
        let combining = try LYGlyphTextParser(rules: [.mentions()]).document(from: text("@e\u{301} 你好"))
        XCTAssertEqual(combining.actions.map(\.actionID), ["mention:e\u{301}"])
        let custom = try LYGlyphTextParser(rules: [.pattern("\\d{3}", actionID: { "code:" + $0 })])
            .document(from: text("编号 123 和 45"))
        XCTAssertEqual(custom.actions.map(\.actionID), ["code:123"])
        let invalid = try LYGlyphTextParser(rules: [.pattern("(", actionID: { $0 })]).document(from: text("(x"))
        XCTAssertTrue(invalid.actions.isEmpty)
        let empty = try LYGlyphTextParser(rules: [.pattern("x", actionID: { _ in "" })]).document(from: text("x"))
        XCTAssertTrue(empty.actions.isEmpty)
    }

    func testEmoticonsBecomeImageAttachmentsBeforeActions() throws {
        let parser = LYGlyphTextParser(rules: [
            .mentions(), .emoticons(["[微笑]": smile, "[笑]": smile], size: CGSize(width: 18, height: 18))
        ])
        let doc = try parser.document(from: text("[微笑]你好 @朋友 [笑][未知]"))
        let source = doc.string as NSString
        XCTAssertEqual(doc.string, "\u{FFFC}你好 @朋友 \u{FFFC}[未知]")
        XCTAssertEqual(Set(doc.attachments.keys), [0, source.range(of: "\u{FFFC}", options: .backwards).location])
        XCTAssertEqual(doc.attachments[0]?.alternativeText, "[微笑]")
        XCTAssertEqual(doc.attachments[0]?.size, CGSize(width: 18, height: 18))
        XCTAssertEqual(Set(doc.attachments.values.map(\.id)).count, 2)
        XCTAssertEqual(doc.actions.map(\.actionID), ["mention:朋友"])
        XCTAssertEqual(source.substring(with: doc.actions[0].range), "@朋友")
    }

    func testTopicContainingEmoticonIsNotAnAction() throws {
        let parser = LYGlyphTextParser(rules: [
            .topics(),
            .emoticons(["[笑]": smile], size: CGSize(width: 10, height: 10))
        ])
        let doc = try parser.document(from: text("#话题[笑]# 和 #普通#"))
        XCTAssertEqual(doc.actions.map(\.actionID), ["topic:普通"])
    }

    func testInputObjectReplacementCharacterStillThrows() {
        XCTAssertThrowsError(try LYGlyphTextParser(rules: [.mentions()]).document(from: text("a\u{FFFC}"))) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 1))
        }
    }
}
