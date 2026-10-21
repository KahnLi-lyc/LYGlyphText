import UIKit

/// MainActor 上的顺序文档片段；文档初始化时才对文本和支持的属性建立快照。
///
/// 每个带 actionID 的片段生成一个独立动作；跨片段动作请使用 attributedText 与 actions 初始化入口。
@MainActor
public enum LYGlyphTextSegment {
    /// 追加富文本；actionID 非 nil 时覆盖整个片段，空标识或空范围会被拒绝。
    /// 显式传入按下样式；省略样式时使用同名 MainActor 便利方法。
    case text(
        NSAttributedString, actionID: String? = nil,
        pressedStyle: LYGlyphTextPressedStyle
    )
    /// 追加一个 U+FFFC 图片占位符，并将 attributes 应用于该占位符。
    /// 显式传入按下样式；省略样式时使用同名 MainActor 便利方法。
    case image(
        LYGlyphTextAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil, pressedStyle: LYGlyphTextPressedStyle
    )
    /// 追加一个 U+FFFC 视图占位符；仅保存描述，不调用工厂或创建视图。
    /// 显式传入按下样式；省略样式时使用同名 MainActor 便利方法。
    case view(
        LYGlyphTextViewAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil, pressedStyle: LYGlyphTextPressedStyle
    )
    /// 追加一个 U+FFFC 远程图片占位符；仅保存描述，不发起请求。
    /// 显式传入按下样式；省略样式时使用同名 MainActor 便利方法。
    case remoteImage(
        LYGlyphTextRemoteImageAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil, pressedStyle: LYGlyphTextPressedStyle
    )

    /// Swift 6 的枚举 case 默认值不继承全局 actor，故在 MainActor 方法内创建默认样式。
    /// 追加使用默认按下样式的富文本片段。
    public static func text(_ text: NSAttributedString, actionID: String? = nil) -> Self {
        .text(text, actionID: actionID, pressedStyle: .init())
    }

    /// 追加使用默认按下样式的图片片段；attributes 默认空字典。
    public static func image(
        _ attachment: LYGlyphTextAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil
    ) -> Self {
        .image(attachment, attributes: attributes, actionID: actionID, pressedStyle: .init())
    }

    /// 追加使用默认按下样式的视图片段；仅保存描述，不创建 UIView。
    public static func view(
        _ attachment: LYGlyphTextViewAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil
    ) -> Self {
        .view(attachment, attributes: attributes, actionID: actionID, pressedStyle: .init())
    }

    /// 追加使用默认按下样式的远程图片片段；仅保存描述，不发起请求。
    public static func remoteImage(
        _ attachment: LYGlyphTextRemoteImageAttachment, attributes: [NSAttributedString.Key: Any] = [:],
        actionID: String? = nil
    ) -> Self {
        .remoteImage(attachment, attributes: attributes, actionID: actionID, pressedStyle: .init())
    }
}
