import UIKit

/// MainActor 上的不可变行内视图描述；文档不持有 UIView 或业务闭包。
@MainActor
public struct LYGlyphTextViewAttachment {
    /// 图片和视图附件共用的文档内唯一标识。
    public let id: String
    /// 宿主工厂识别视图种类的标识。
    public let viewID: String
    /// 明确的排版尺寸，单位 point，须有限且大于零；工厂尺寸不反馈到排版。
    public let size: CGSize
    /// 相对于占位字符字体区域的垂直对齐。
    public let alignment: LYGlyphTextAttachmentAlignment
    /// 保存的替代文本；当前不提供完整的 VoiceOver 行内语义。
    public let alternativeText: String?
    /// 是否允许原生视图接收触摸；默认 false。
    public let isInteractive: Bool

    /// 创建描述，位置、尺寸与 ID 在文档构造时校验。
    public init(
        id: String, viewID: String, size: CGSize,
        alignment: LYGlyphTextAttachmentAlignment = .bottom, alternativeText: String? = nil,
        isInteractive: Bool = false
    ) {
        self.id = id
        self.viewID = viewID
        self.size = size
        self.alignment = alignment
        self.alternativeText = alternativeText
        self.isInteractive = isInteractive
    }
}
