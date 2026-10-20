import UIKit

/// 附件相对于占位字符字体 ascender／descender 区域的垂直对齐。
public enum LYGlyphTextAttachmentAlignment: Equatable {
    /// 附件顶部对齐字体区域顶部。
    case top
    /// 附件中心对齐字体区域中心。
    case center
    /// 附件底部对齐字体区域底部。
    case bottom
}

/// MainActor 上的不可变行内图片描述，不创建或持有 UIView。
@MainActor
public struct LYGlyphTextAttachment {
    /// 文档内唯一的附件标识。
    public let id: String
    /// 由宿主提供的本地图片，不负责下载或动画播放。
    public let image: UIImage
    /// 排版和绘制使用的明确尺寸，单位为 point，必须有限且大于 0。
    public let size: CGSize
    /// 相对于占位字符字体区域的对齐方式。
    public let alignment: LYGlyphTextAttachmentAlignment
    /// 保存的替代文本；当前不提供完整的 VoiceOver 行内语义。
    public let alternativeText: String?

    /// 创建附件描述。尺寸和文档内 ID 唯一性在文档初始化时校验。
    /// 图片填充声明尺寸，保留 UIImage 方向；超宽部分裁切，不自动缩小尺寸。
    public init(
        id: String, image: UIImage, size: CGSize,
        alignment: LYGlyphTextAttachmentAlignment = .bottom, alternativeText: String? = nil
    ) {
        self.id = id
        self.image = image
        self.size = size
        self.alignment = alignment
        self.alternativeText = alternativeText
    }
}
