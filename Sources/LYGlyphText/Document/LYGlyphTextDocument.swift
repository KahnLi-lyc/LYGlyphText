import UIKit

/// 文档输入校验错误；当前版本不接受行内附件。
public enum LYGlyphTextDocumentError: Error, Equatable {
    /// 输入带有标准 attachment 属性，范围使用 UTF-16 单位。
    case unsupportedAttachment(range: NSRange)
    /// 输入包含 U+FFFC 对象替换字符，位置使用 UTF-16 单位。
    case unsupportedObjectReplacementCharacter(location: Int)
}

/// 在主线程构造的不可变富文本快照，不持有视图或业务回调。
///
/// 当前仅解释 font、foregroundColor 以及段落对齐和基本书写方向。
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

    /// 复制文本与支持的样式，隔离调用方随后对可变字符串及段落样式的修改。
    /// - Throws: 输入包含标准附件属性或 U+FFFC 时抛出 `LYGlyphTextDocumentError`。
    public init(attributedText: NSAttributedString) throws {
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
        let replacement = (attributedText.string as NSString).range(of: "\u{FFFC}")
        if replacement.location != NSNotFound {
            throw LYGlyphTextDocumentError.unsupportedObjectReplacementCharacter(location: replacement.location)
        }

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
