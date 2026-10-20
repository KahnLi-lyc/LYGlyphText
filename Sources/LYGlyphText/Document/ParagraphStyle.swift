import UIKit

/// 完整逻辑段落的不可变数值快照；不保留调用方的段落对象。
struct ParagraphStyle {
    let alignment: NSTextAlignment
    let writingDirection: NSWritingDirection
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let paragraphSpacingBefore: CGFloat
    let firstLineHeadIndent: CGFloat
    let headIndent: CGFloat
    let tailIndent: CGFloat
    let minimumLineHeight: CGFloat
    let maximumLineHeight: CGFloat
    let lineHeightMultiple: CGFloat

    init(_ style: NSParagraphStyle? = nil) {
        func finite(_ value: CGFloat) -> CGFloat {
            value.isFinite ? value : 0
        }
        alignment = style?.alignment ?? .natural
        writingDirection = style?.baseWritingDirection ?? .natural
        lineSpacing = finite(style?.lineSpacing ?? 0)
        paragraphSpacing = finite(style?.paragraphSpacing ?? 0)
        paragraphSpacingBefore = finite(style?.paragraphSpacingBefore ?? 0)
        firstLineHeadIndent = finite(style?.firstLineHeadIndent ?? 0)
        headIndent = finite(style?.headIndent ?? 0)
        tailIndent = finite(style?.tailIndent ?? 0)
        minimumLineHeight = max(0, finite(style?.minimumLineHeight ?? 0))
        let maximum = max(0, finite(style?.maximumLineHeight ?? 0))
        maximumLineHeight = maximum != 0 && maximum < minimumLineHeight ? 0 : maximum
        lineHeightMultiple = max(0, finite(style?.lineHeightMultiple ?? 0))
    }
}

/// 数字只接受 Foundation 可桥接数值，先验证再转换整数，避免越界陷阱。
enum StyleNumber {
    static func scalar(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        let value = CGFloat(number.doubleValue)
        return value.isFinite ? value : nil
    }

    static func integer(_ value: Any?, allowed: ClosedRange<Int>) -> Int? {
        guard let number = scalar(value), number >= CGFloat(allowed.lowerBound),
              number <= CGFloat(allowed.upperBound), number.rounded(.towardZero) == number
        else { return nil }
        return Int(number)
    }

    static func decoration(_ value: Any?) -> Int {
        guard let raw = integer(value, allowed: 0 ... 0xFFFF),
              raw & ~0x8F0F == 0, [0, 1, 2, 9].contains(raw & 0xF),
              [0, 0x100, 0x200, 0x300, 0x400].contains(raw & 0xF00)
        else { return 0 }
        return raw
    }
}
