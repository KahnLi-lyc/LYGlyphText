import UIKit

/// 文档输入校验错误，位置与范围均使用原文 UTF-16 单位。
public enum LYGlyphTextDocumentError: Error, Equatable {
    /// 输入带有标准 attachment 属性，范围使用 UTF-16 单位。
    case unsupportedAttachment(range: NSRange)
    /// 输入包含未提供附件描述的 U+FFFC，位置使用 UTF-16 单位。
    case unsupportedObjectReplacementCharacter(location: Int)
    /// 附件位置越界，或未指向一个独立的 U+FFFC。
    case invalidAttachmentLocation(location: Int)
    /// 同一文档使用了重复的附件 ID。
    case duplicateAttachmentID(id: String)
    /// 附件尺寸非有限，或任一边不大于 0。
    case invalidAttachmentSize(id: String)
}

/// 在主线程构造的不可变富文本快照，不持有视图或业务回调。
///
/// 当前解释 font、foregroundColor、段落对齐和基本书写方向，以及显式描述的图片附件。
/// 其他装饰属性不参与显示；显式字体保持固定，缺省字体使用动态 body。
@MainActor
public final class LYGlyphTextDocument {
    struct StyleRun {
        let range: NSRange
        let font: UIFont?
        let color: UIColor?
        let alignment: NSTextAlignment
        let writingDirection: NSWritingDirection
    }

    let string: String
    let styleRuns: [StyleRun]
    let attachments: [Int: LYGlyphTextAttachment]

    /// 复制文本与支持的样式，隔离调用方随后对可变字符串及段落样式的修改。
    /// - Parameter attachments: 以原文 UTF-16 位置关联单个 U+FFFC 的图片描述，默认无附件。
    /// - Throws: 标准附件属性、未描述的 U+FFFC、非法位置／尺寸或重复 ID。
    public init(attributedText: NSAttributedString, attachments: [Int: LYGlyphTextAttachment] = [:]) throws {
        var attachmentRange: NSRange?
        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.attachment, in: fullRange) { value, range, stop in
            if value != nil {
                attachmentRange = range
                stop.pointee = true
            }
        }
        if let attachmentRange {
            throw LYGlyphTextDocumentError.unsupportedAttachment(range: attachmentRange)
        }
        let source = attributedText.string as NSString
        var ids: Set<String> = []
        for location in attachments.keys.sorted() {
            guard location >= 0, location < source.length, source.character(at: location) == 0xFFFC,
                  source.rangeOfComposedCharacterSequence(at: location) == NSRange(location: location, length: 1)
            else { throw LYGlyphTextDocumentError.invalidAttachmentLocation(location: location) }
            guard let attachment = attachments[location] else { continue }
            guard ids.insert(attachment.id).inserted else {
                throw LYGlyphTextDocumentError.duplicateAttachmentID(id: attachment.id)
            }
            guard attachment.size.width.isFinite, attachment.size.height.isFinite,
                  attachment.size.width > 0, attachment.size.height > 0
            else { throw LYGlyphTextDocumentError.invalidAttachmentSize(id: attachment.id) }
        }
        for location in 0 ..< source.length where source.character(at: location) == 0xFFFC {
            guard attachments[location] != nil else {
                throw LYGlyphTextDocumentError.unsupportedObjectReplacementCharacter(location: location)
            }
        }
        self.attachments = attachments

        // 不保留 NSParagraphStyle 对象。属性字符串可能合并相等的属性对象，
        // 因而即使 copy 之后再存储，也不能依赖可变输入的对象身份隔离。
        string = attributedText.string
        var runs: [StyleRun] = []
        attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            runs.append(StyleRun(
                range: range,
                font: attributes[.font] as? UIFont,
                color: attributes[.foregroundColor] as? UIColor,
                alignment: paragraph?.alignment ?? .natural,
                writingDirection: paragraph?.baseWritingDirection ?? .natural
            ))
        }
        styleRuns = runs
    }
}
