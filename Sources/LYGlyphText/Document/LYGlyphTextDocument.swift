import UIKit

/// 文档输入校验错误，位置与范围均使用原文 UTF-16 单位。
public enum LYGlyphTextDocumentError: Error, Equatable {
    /// 输入带有标准 attachment 属性，范围使用 UTF-16 单位。
    case unsupportedAttachment(range: NSRange)
    /// 输入包含未提供附件描述的 U+FFFC，位置使用 UTF-16 单位。
    case unsupportedObjectReplacementCharacter(location: Int)
    /// 附件位置越界，或未指向一个独立的 U+FFFC。
    case invalidAttachmentLocation(location: Int)
    /// 图片与视图描述同时使用了同一个 UTF-16 位置。
    case conflictingAttachmentLocation(location: Int)
    /// 同一文档使用了重复的附件 ID。
    case duplicateAttachmentID(id: String)
    /// 附件尺寸非有限，或任一边不大于 0。
    case invalidAttachmentSize(id: String)
    /// 动作标识为空；范围使用原文 UTF-16 单位。
    case emptyActionID(range: NSRange)
    /// 动作范围为负、为空、越界或溢出。
    case invalidActionRange(range: NSRange)
    /// 动作范围切开了原文中的组合字符。
    case actionRangeSplitsComposedCharacter(range: NSRange)
    /// 两个动作范围重叠；按原文位置排序，相同位置保留输入顺序。
    case overlappingActionRanges(first: NSRange, second: NSRange)
    /// 文档中没有该 ID 的远程图片附件。
    case unknownAttachmentID(id: String)
}

/// 在主线程构造的不可变富文本快照，不持有视图或业务回调。
///
/// 保存白名单字符样式、完整逻辑段落值，以及显式描述的图片／视图附件。
/// 未知属性忽略；显式字体保持固定，缺省字体使用动态 body。
@MainActor
public final class LYGlyphTextDocument {
    struct StyleRun {
        let range: NSRange
        let font: UIFont?
        let color: UIColor?
        let background: UIColor?
        let kern: CGFloat?
        let baselineOffset: CGFloat
        let underlineStyle: Int
        let underlineColor: UIColor?
        let strikethroughStyle: Int
        let strikethroughColor: UIColor?
        let ligature: Int
        let shadow: TextShadow?
        let backgroundStyle: LYGlyphTextBackgroundStyle?
        let strokeWidth: CGFloat
        let strokeColor: UIColor?
        let paragraph: ParagraphStyle
        var alignment: NSTextAlignment {
            paragraph.alignment
        }

        var writingDirection: NSWritingDirection {
            paragraph.writingDirection
        }
    }

    let string: String
    let styleRuns: [StyleRun]
    let attachments: [Int: LYGlyphTextAttachment]
    let viewAttachments: [Int: LYGlyphTextViewAttachment]
    /// 远程图片按附件 ID 保存；其排版与挂载占位同时以不可交互视图描述存放在 viewAttachments。
    let remoteImages: [String: LYGlyphTextRemoteImageAttachment]
    let actions: [LYGlyphTextAction]

    /// 远程图片在内部视图描述中使用的保留种类标识；宿主工厂不会收到这些描述。
    static let remoteImageViewID = "LYGlyphText.remoteImage"

    /// 复制文本与支持的样式，隔离调用方随后对可变字符串及段落样式的修改。
    /// - Parameter attachments: 以原文 UTF-16 位置关联单个 U+FFFC 的图片描述，默认无附件。
    /// - Parameter viewAttachments: 以原文 UTF-16 位置关联单个 U+FFFC 的视图描述，默认无附件。
    /// - Parameter remoteImages: 以原文 UTF-16 位置关联单个 U+FFFC 的远程图片描述，默认无附件；
    ///   与图片、视图附件共用位置、ID 与尺寸校验。
    /// - Parameter actions: 原文 UTF-16 动作范围；保持输入顺序，默认无动作。
    /// - Parameter linkPressedStyle: 非 nil 时把 `.link` 属性（URL 或非空 String）的最长连续范围
    ///   追加为动作，actionID 为 URL 的 absoluteString 或该字符串，使用此按下样式；默认 nil 忽略 `.link`。
    /// - Throws: 先校验附件，再按输入顺序校验动作标识与范围，最后拒绝重叠动作（包括链接与显式动作重叠）。
    public init(
        attributedText: NSAttributedString, attachments: [Int: LYGlyphTextAttachment] = [:],
        viewAttachments: [Int: LYGlyphTextViewAttachment] = [:],
        remoteImages: [Int: LYGlyphTextRemoteImageAttachment] = [:], actions: [LYGlyphTextAction] = [],
        linkPressedStyle: LYGlyphTextPressedStyle? = nil
    ) throws {
        var actions = actions
        var viewAttachments = viewAttachments
        for (location, remote) in remoteImages.sorted(by: { $0.key < $1.key }) {
            guard viewAttachments[location] == nil else {
                throw LYGlyphTextDocumentError.conflictingAttachmentLocation(location: location)
            }
            viewAttachments[location] = LYGlyphTextViewAttachment(
                id: remote.id, viewID: Self.remoteImageViewID, size: remote.size, alignment: remote.alignment,
                alternativeText: remote.alternativeText
            )
        }
        if let linkPressedStyle {
            attributedText.enumerateAttribute(
                .link, in: NSRange(location: 0, length: attributedText.length), options: []
            ) { value, range, _ in
                let id = (value as? URL)?.absoluteString ?? (value as? String)
                guard let id, !id.isEmpty else { return }
                actions.append(LYGlyphTextAction(actionID: id, range: range, pressedStyle: linkPressedStyle))
            }
        }
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
        let sourceString = attributedText.string
        let source = sourceString as NSString
        var ids: Set<String> = []
        if let collision = Set(attachments.keys).intersection(viewAttachments.keys).sorted().first {
            throw LYGlyphTextDocumentError.conflictingAttachmentLocation(location: collision)
        }
        for location in Set(attachments.keys).union(viewAttachments.keys).sorted() {
            guard location >= 0, location < source.length, source.character(at: location) == 0xFFFC,
                  source.rangeOfComposedCharacterSequence(at: location) == NSRange(location: location, length: 1)
            else { throw LYGlyphTextDocumentError.invalidAttachmentLocation(location: location) }
            guard let id = attachments[location]?.id ?? viewAttachments[location]?.id,
                  let size = attachments[location]?.size ?? viewAttachments[location]?.size
            else { continue }
            guard ids.insert(id).inserted else {
                throw LYGlyphTextDocumentError.duplicateAttachmentID(id: id)
            }
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0
            else { throw LYGlyphTextDocumentError.invalidAttachmentSize(id: id) }
        }
        for location in 0 ..< source.length where source.character(at: location) == 0xFFFC {
            guard attachments[location] != nil || viewAttachments[location] != nil else {
                throw LYGlyphTextDocumentError.unsupportedObjectReplacementCharacter(location: location)
            }
        }
        // NSString 的组合序列在当前系统可将 CRLF 分开，额外使用 Swift Character 边界。
        let characterBoundaries: Set<String.Index> = actions.isEmpty
            ? [] : Set(sourceString.indices).union([sourceString.endIndex])
        for action in actions {
            let range = action.range
            guard !action.actionID.isEmpty else {
                throw LYGlyphTextDocumentError.emptyActionID(range: range)
            }
            // 先验证数值，再做范围转换或求末端，避免 NSNotFound 与加法溢出。
            guard range.location >= 0, range.length > 0, range.location <= source.length,
                  range.length <= source.length - range.location
            else { throw LYGlyphTextDocumentError.invalidActionRange(range: range) }
            guard let stringRange = Range(range, in: sourceString),
                  characterBoundaries.contains(stringRange.lowerBound),
                  characterBoundaries.contains(stringRange.upperBound),
                  source.rangeOfComposedCharacterSequences(for: range) == range
            else { throw LYGlyphTextDocumentError.actionRangeSplitsComposedCharacter(range: range) }
        }
        // 排序仅用于重叠校验；动作存储仍保留输入顺序，重复 ID 不合并。
        let orderedActions = actions.enumerated().sorted {
            if $0.element.range.location == $1.element.range.location { return $0.offset < $1.offset }
            return $0.element.range.location < $1.element.range.location
        }
        for (first, second) in zip(orderedActions, orderedActions.dropFirst()) {
            let firstRange = first.element.range
            let secondRange = second.element.range
            if firstRange.location + firstRange.length > secondRange.location {
                throw LYGlyphTextDocumentError.overlappingActionRanges(first: firstRange, second: secondRange)
            }
        }
        self.attachments = attachments
        self.viewAttachments = viewAttachments
        var remoteByID: [String: LYGlyphTextRemoteImageAttachment] = [:]
        for remote in remoteImages.values {
            remoteByID[remote.id] = remote
        }
        self.remoteImages = remoteByID
        self.actions = actions

        // 不保留 NSParagraphStyle 对象。属性字符串可能合并相等的属性对象，
        // 因而即使 copy 之后再存储，也不能依赖可变输入的对象身份隔离。
        string = sourceString
        var runs: [StyleRun] = []
        var cursor = 0
        while cursor < source.length {
            let paragraphRange = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            let paragraph = ParagraphStyle(attributedText.attribute(
                .paragraphStyle, at: paragraphRange.location, effectiveRange: nil
            ) as? NSParagraphStyle)
            attributedText.enumerateAttributes(in: paragraphRange) { attributes, range, _ in
                runs.append(StyleRun(
                    range: range,
                    font: attributes[.font] as? UIFont,
                    color: attributes[.foregroundColor] as? UIColor,
                    background: attributes[.backgroundColor] as? UIColor,
                    kern: StyleNumber.scalar(attributes[.kern]),
                    baselineOffset: StyleNumber.scalar(attributes[.baselineOffset]) ?? 0,
                    underlineStyle: StyleNumber.decoration(attributes[.underlineStyle]),
                    underlineColor: attributes[.underlineColor] as? UIColor,
                    strikethroughStyle: StyleNumber.decoration(attributes[.strikethroughStyle]),
                    strikethroughColor: attributes[.strikethroughColor] as? UIColor,
                    ligature: StyleNumber.integer(attributes[.ligature], allowed: 0 ... 2) ?? 1,
                    shadow: (attributes[.shadow] as? NSShadow).flatMap(TextShadow.init),
                    backgroundStyle: (attributes[.lyGlyphTextBackground] as? LYGlyphTextBackgroundStyle)
                        .flatMap { $0.isVisible ? $0 : nil },
                    strokeWidth: StyleNumber.scalar(attributes[.strokeWidth]) ?? 0,
                    strokeColor: attributes[.strokeColor] as? UIColor,
                    paragraph: paragraph
                ))
            }
            cursor = NSMaxRange(paragraphRange)
        }
        styleRuns = runs
    }

    private init(
        string: String, styleRuns: [StyleRun], attachments: [Int: LYGlyphTextAttachment],
        viewAttachments: [Int: LYGlyphTextViewAttachment], remoteImages: [String: LYGlyphTextRemoteImageAttachment],
        actions: [LYGlyphTextAction]
    ) {
        self.string = string
        self.styleRuns = styleRuns
        self.attachments = attachments
        self.viewAttachments = viewAttachments
        self.remoteImages = remoteImages
        self.actions = actions
    }

    /// 返回只把指定远程图片的排版尺寸替换为 size 的新文档；文字、样式、动作和其他附件保持不变，原文档不变。
    ///
    /// 典型用法：在 `onRemoteImageLoad` 得到图片真实尺寸后按比例计算新尺寸，替换文档并刷新列表行高。
    /// - Throws: 没有该 ID 的远程图片时抛出 `unknownAttachmentID`；尺寸非有限或不大于 0 时抛出 `invalidAttachmentSize`。
    public func replacingRemoteImageSize(id: String, size: CGSize) throws -> LYGlyphTextDocument {
        guard let remote = remoteImages[id],
              let location = viewAttachments.first(where: { $0.value.id == id })?.key
        else { throw LYGlyphTextDocumentError.unknownAttachmentID(id: id) }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw LYGlyphTextDocumentError.invalidAttachmentSize(id: id)
        }
        let resized = LYGlyphTextRemoteImageAttachment(
            id: remote.id, url: remote.url, size: size, alignment: remote.alignment, contentMode: remote.contentMode,
            placeholder: remote.placeholder, failureImage: remote.failureImage, alternativeText: remote.alternativeText
        )
        var views = viewAttachments
        views[location] = LYGlyphTextViewAttachment(
            id: id, viewID: Self.remoteImageViewID, size: size, alignment: remote.alignment,
            alternativeText: remote.alternativeText
        )
        var remotes = remoteImages
        remotes[id] = resized
        return LYGlyphTextDocument(
            string: string, styleRuns: styleRuns, attachments: attachments, viewAttachments: views,
            remoteImages: remotes, actions: actions
        )
    }

    /// 依次连接文本和附件，在初始化时建立快照并复用完整文档校验。
    /// - Parameter segments: 顺序片段；相邻且标识相同的动作仍保持独立。
    /// - Throws: 与 attributedText 初始化入口相同；空动作或跨片段切开组合字符也会失败。
    public convenience init(segments: [LYGlyphTextSegment]) throws {
        let text = NSMutableAttributedString(string: "")
        var attachments: [Int: LYGlyphTextAttachment] = [:]
        var viewAttachments: [Int: LYGlyphTextViewAttachment] = [:]
        var remoteImages: [Int: LYGlyphTextRemoteImageAttachment] = [:]
        var actions: [LYGlyphTextAction] = []
        for segment in segments {
            let location = text.length
            let actionID: String?
            let pressedStyle: LYGlyphTextPressedStyle
            switch segment {
            case let .text(value, id, style):
                text.append(value)
                actionID = id
                pressedStyle = style
            case let .image(attachment, attributes, id, style):
                attachments[location] = attachment
                text.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                actionID = id
                pressedStyle = style
            case let .view(attachment, attributes, id, style):
                viewAttachments[location] = attachment
                text.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                actionID = id
                pressedStyle = style
            case let .remoteImage(attachment, attributes, id, style):
                remoteImages[location] = attachment
                text.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                actionID = id
                pressedStyle = style
            }
            if let actionID {
                actions.append(LYGlyphTextAction(
                    actionID: actionID, range: NSRange(location: location, length: text.length - location),
                    pressedStyle: pressedStyle
                ))
            }
        }
        try self.init(
            attributedText: text,
            attachments: attachments,
            viewAttachments: viewAttachments,
            remoteImages: remoteImages,
            actions: actions
        )
    }
}
