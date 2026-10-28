import UIKit

/// 文本识别规则：识别链接、@提及、#话题或自定义模式并生成动作，或把表情短码替换为图片附件。
@MainActor
public struct LYGlyphTextParseRule {
    enum Kind {
        case actions(
            matcher: (NSString) -> [NSRange], attributes: [NSAttributedString.Key: Any],
            pressedStyle: LYGlyphTextPressedStyle, actionID: (String) -> String
        )
        case emoticons(images: [String: UIImage], size: CGSize, alignment: LYGlyphTextAttachmentAlignment)
        case markdownLinks(attributes: [NSAttributedString.Key: Any], pressedStyle: LYGlyphTextPressedStyle)
        case markdownEmphasis
    }

    let kind: Kind

    /// 用 NSDataDetector 识别网址；actionID 为识别到的 URL absoluteString。
    public static func links(
        attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.link],
        pressedStyle: LYGlyphTextPressedStyle = .init()
    ) -> Self {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return .init(kind: .actions(matcher: { source in
            detector?.matches(in: source as String, range: NSRange(location: 0, length: source.length))
                .map(\.range) ?? []
        }, attributes: attributes, pressedStyle: pressedStyle, actionID: { matched in
            detector?.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length))?
                .url?.absoluteString ?? matched
        }))
    }

    /// 识别 `@名称`（字母、数字、下划线，包含中文等 Unicode 字母）；actionID 为 `mention:` 加去掉 @ 的名称。
    public static func mentions(
        attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.link],
        pressedStyle: LYGlyphTextPressedStyle = .init()
    ) -> Self {
        pattern(
            "@[\\p{L}\\p{N}_]+", attributes: attributes, pressedStyle: pressedStyle,
            actionID: { "mention:" + $0.dropFirst() }
        )
    }

    /// 识别 `#话题#`（成对井号，中间不含井号和换行）；actionID 为 `topic:` 加话题文字。
    public static func topics(
        attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.link],
        pressedStyle: LYGlyphTextPressedStyle = .init()
    ) -> Self {
        pattern(
            "#[^#\\n]+#", attributes: attributes, pressedStyle: pressedStyle,
            actionID: { "topic:" + $0.dropFirst().dropLast() }
        )
    }

    /// 以正则表达式识别；模式无效时该规则不产生匹配。actionID 由完整匹配文字生成，空字符串的匹配被忽略。
    public static func pattern(
        _ pattern: String, options: NSRegularExpression.Options = [],
        attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.link],
        pressedStyle: LYGlyphTextPressedStyle = .init(), actionID: @escaping (String) -> String
    ) -> Self {
        let expression = try? NSRegularExpression(pattern: pattern, options: options)
        return .init(kind: .actions(matcher: { source in
            expression?.matches(in: source as String, range: NSRange(location: 0, length: source.length))
                .map(\.range) ?? []
        }, attributes: attributes, pressedStyle: pressedStyle, actionID: actionID))
    }

    /// 把 `[文字](链接)` 显示为“文字”并生成动作，actionID 为链接原文；文字为空、链接含空白或文字含附件时保留原样。
    /// 在表情替换与强调处理之后、其他动作规则之前执行，识别出的范围不再参与其他规则。
    public static func markdownLinks(
        attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.link],
        pressedStyle: LYGlyphTextPressedStyle = .init()
    ) -> Self {
        .init(kind: .markdownLinks(attributes: attributes, pressedStyle: pressedStyle))
    }

    /// 处理 `**粗体**`、`*斜体*` 与 `` `代码` ``：去掉标记，按所在位置的字体派生粗体、斜体或等宽字体。
    ///
    /// 不支持嵌套、跨行与转义；没有配对的标记保留原样。所在位置没有字体时以 body 字体派生，
    /// 派生后的字体为显式字体，不再随动态字号变化。
    public static func markdownEmphasis() -> Self {
        .init(kind: .markdownEmphasis)
    }

    /// 把出现的短码（如 `[微笑]`）替换为图片附件，附件替代文本为短码本身；尺寸单位 point。
    public static func emoticons(
        _ images: [String: UIImage], size: CGSize, alignment: LYGlyphTextAttachmentAlignment = .center
    ) -> Self {
        .init(kind: .emoticons(images: images, size: size, alignment: alignment))
    }
}

/// 按规则把富文本转换为文档。先替换表情短码，再按规则顺序识别动作；与已识别范围重叠的后续匹配被忽略。
@MainActor
public struct LYGlyphTextParser {
    /// 规则按数组顺序生效。
    public let rules: [LYGlyphTextParseRule]

    /// 创建解析器。
    public init(rules: [LYGlyphTextParseRule]) {
        self.rules = rules
    }

    /// 解析富文本并构造文档；匹配范围扩展到完整组合字符，属性叠加在原有样式之上。
    /// - Throws: 与 `LYGlyphTextDocument` 初始化相同的校验错误，例如输入包含未描述的 U+FFFC。
    public func document(from text: NSAttributedString) throws -> LYGlyphTextDocument {
        let output = NSMutableAttributedString(attributedString: text)
        var attachments: [Int: LYGlyphTextAttachment] = [:]
        for rule in rules {
            guard case let .emoticons(images, size, alignment) = rule.kind else { continue }
            replaceEmoticons(in: output, images: images, size: size, alignment: alignment, into: &attachments)
        }
        if rules.contains(where: { if case .markdownEmphasis = $0.kind { true } else { false } }) {
            applyEmphasis(in: output, attachments: &attachments)
        }
        var taken: [NSRange] = []
        var actions: [LYGlyphTextAction] = []
        for rule in rules {
            guard case let .markdownLinks(attributes, pressedStyle) = rule.kind else { continue }
            for link in replaceLinks(in: output, attachments: &attachments) {
                output.addAttributes(attributes, range: link.range)
                taken.append(link.range)
                actions.append(LYGlyphTextAction(actionID: link.url, range: link.range, pressedStyle: pressedStyle))
            }
        }
        let source = output.string as NSString
        for rule in rules {
            guard case let .actions(matcher, attributes, pressedStyle, makeID) = rule.kind else { continue }
            for match in matcher(source) where match.length > 0 && match.location != NSNotFound {
                let range = source.rangeOfComposedCharacterSequences(for: match)
                guard !taken.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                      !containsAttachment(source, range) else { continue }
                let id = makeID(source.substring(with: range))
                guard !id.isEmpty else { continue }
                taken.append(range)
                output.addAttributes(attributes, range: range)
                actions.append(LYGlyphTextAction(actionID: id, range: range, pressedStyle: pressedStyle))
            }
        }
        actions.sort { $0.range.location < $1.range.location }
        return try LYGlyphTextDocument(attributedText: output, attachments: attachments, actions: actions)
    }

    /// 用新内容替换一个范围，并平移其后的附件位置；被替换范围内含附件时不应调用。
    private func replace(
        _ range: NSRange, with replacement: NSAttributedString, in text: NSMutableAttributedString,
        attachments: inout [Int: LYGlyphTextAttachment]
    ) {
        let delta = replacement.length - range.length
        attachments = Dictionary(uniqueKeysWithValues: attachments.map { location, attachment in
            (location >= NSMaxRange(range) ? location + delta : location, attachment)
        })
        text.replaceCharacters(in: range, with: replacement)
    }

    private func applyEmphasis(in text: NSMutableAttributedString, attachments: inout [Int: LYGlyphTextAttachment]) {
        let patterns: [(String, (UIFont) -> UIFont)] = [
            ("\\*\\*([^*\\n]+?)\\*\\*", { Self.font($0, adding: .traitBold) }),
            ("`([^`\\n]+)`", { UIFont.monospacedSystemFont(ofSize: $0.pointSize, weight: .regular) }),
            ("(?<![*\\w])\\*([^*\\n]+?)\\*(?![*\\w])", { Self.font($0, adding: .traitItalic) })
        ]
        for (pattern, derive) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(in: text.string, range: NSRange(location: 0, length: text.length))
            for match in matches.reversed() {
                let inner = match.range(at: 1)
                guard !containsAttachment(text.string as NSString, match.range) else { continue }
                let content = NSMutableAttributedString(attributedString: text.attributedSubstring(from: inner))
                content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, range, _ in
                    let base = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                    content.addAttribute(.font, value: derive(base), range: range)
                }
                replace(match.range, with: content, in: text, attachments: &attachments)
            }
        }
    }

    private static func font(_ font: UIFont, adding trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// 从后向前替换链接；已记录的后方链接随前方替换平移，返回最终范围与链接原文。
    private func replaceLinks(
        in text: NSMutableAttributedString, attachments: inout [Int: LYGlyphTextAttachment]
    ) -> [(range: NSRange, url: String)] {
        guard let expression = try? NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
        else { return [] }
        var links: [(range: NSRange, url: String)] = []
        let matches = expression.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let source = text.string as NSString
            let label = match.range(at: 1)
            let url = source.substring(with: match.range(at: 2))
            guard !containsAttachment(source, match.range),
                  !source.substring(with: label).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let content = text.attributedSubstring(from: label)
            let delta = content.length - match.range.length
            replace(match.range, with: content, in: text, attachments: &attachments)
            links = links.map { (
                $0.range.location >= NSMaxRange(match.range)
                    ? NSRange(location: $0.range.location + delta, length: $0.range.length) : $0.range,
                $0.url
            ) }
            links.append((NSRange(location: match.range.location, length: content.length), url))
        }
        return links.sorted { $0.range.location < $1.range.location }
    }

    private func containsAttachment(_ source: NSString, _ range: NSRange) -> Bool {
        source.substring(with: range).unicodeScalars.contains { $0 == "\u{FFFC}" }
    }

    /// 从后向前替换，已有附件位置随替换长度平移；短码按最长优先匹配。
    private func replaceEmoticons(
        in text: NSMutableAttributedString, images: [String: UIImage], size: CGSize,
        alignment: LYGlyphTextAttachmentAlignment, into attachments: inout [Int: LYGlyphTextAttachment]
    ) {
        let codes = images.keys.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !codes.isEmpty else { return }
        let pattern = codes.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = expression.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        var counter = attachments.count
        for match in matches.reversed() {
            let code = (text.string as NSString).substring(with: match.range)
            guard let image = images[code] else { continue }
            let delta = 1 - match.range.length
            attachments = Dictionary(uniqueKeysWithValues: attachments.map { location, attachment in
                (location > match.range.location ? location + delta : location, attachment)
            })
            let attributes = text.attributes(at: match.range.location, effectiveRange: nil)
            text.replaceCharacters(
                in: match.range, with: NSAttributedString(string: "\u{FFFC}", attributes: attributes)
            )
            counter += 1
            attachments[match.range.location] = LYGlyphTextAttachment(
                id: "emoticon-\(counter)", image: image, size: size, alignment: alignment, alternativeText: code
            )
        }
    }
}
