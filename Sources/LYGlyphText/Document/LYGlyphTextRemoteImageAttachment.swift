import UIKit

/// MainActor 上的不可变远程图片附件描述；尺寸由文档声明，加载结果不改变排版。
///
/// 组件在附件可见时用宿主注入的 `LYGlyphTextImageLoading` 加载，先显示占位图，
/// 失败时显示 failureImage（为 nil 时保留占位图）。没有加载器时只显示占位图。
@MainActor
public struct LYGlyphTextRemoteImageAttachment {
    /// 文档内唯一的附件标识，与图片、视图附件共用唯一性校验。
    public let id: String
    /// 图片地址。
    public let url: URL
    /// 参与排版的 point 尺寸，宽高必须为正的有限值。
    public let size: CGSize
    /// 相对占位字体区域的垂直对齐，默认 bottom。
    public let alignment: LYGlyphTextAttachmentAlignment
    /// 图片在声明尺寸内的填充方式，默认 scaleAspectFill 并裁切。
    public let contentMode: UIView.ContentMode
    /// 加载前显示的图片，默认 nil。
    public let placeholder: UIImage?
    /// 加载失败后显示的图片；nil 时保留占位图。
    public let failureImage: UIImage?
    /// VoiceOver 读出的替代文本；nil 或空白时不朗读。
    public let alternativeText: String?

    /// 创建远程图片附件描述，不发起请求。
    public init(
        id: String, url: URL, size: CGSize, alignment: LYGlyphTextAttachmentAlignment = .bottom,
        contentMode: UIView.ContentMode = .scaleAspectFill, placeholder: UIImage? = nil,
        failureImage: UIImage? = nil, alternativeText: String? = nil
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.alignment = alignment
        self.contentMode = contentMode
        self.placeholder = placeholder
        self.failureImage = failureImage
        self.alternativeText = alternativeText
    }
}
