import UIKit

/// 可取消的远程图片加载任务。
@MainActor
public protocol LYGlyphTextImageLoadingTask: AnyObject {
    /// 取消后不得再调用对应的 completion；重复调用必须安全。
    func cancel()
}

/// 远程图片加载器协议，由宿主注入；组件不提供全局默认实例。
///
/// 组件只在附件可见并挂载时于 MainActor 请求，离屏、复用、替换文档或移出 window 时取消。
/// 实现可以在任意线程下载与解码，但必须在 MainActor 调用 completion，且每个任务至多一次；
/// 已有缓存时可以在返回任务之前同步调用。可桥接 Kingfisher、SDWebImage 等宿主已有的图片库。
@MainActor
public protocol LYGlyphTextImageLoading: AnyObject {
    /// 加载图片。
    /// - Parameters:
    ///   - url: 附件描述中的地址。
    ///   - targetSize: 附件声明尺寸，单位 point，可用于降采样。
    ///   - scale: 当前显示比例。
    ///   - completion: MainActor 回调；取消后不调用。
    /// - Returns: 用于取消本次请求的任务。
    func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask
}

/// 内置加载器的失败原因。
public enum LYGlyphTextImageLoadingError: Error, Equatable {
    /// HTTP 响应状态不在 200...299，关联实际状态码。
    case unacceptableStatusCode(Int)
    /// 数据无法解码为图片。
    case undecodableData
}
