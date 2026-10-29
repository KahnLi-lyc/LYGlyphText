import Kingfisher
import LYGlyphText
import UIKit

/// 把 Kingfisher 桥接为 LYGlyphText 的图片加载器，复用其内存／磁盘缓存、格式支持与降采样。
///
/// 只有 Demo 依赖 Kingfisher，组件本身不依赖任何图片库；宿主可以把本文件复制到自己的工程。
@MainActor
final class KingfisherImageLoader: LYGlyphTextImageLoading {
    private final class Task: LYGlyphTextImageLoadingTask {
        var download: DownloadTask?
        private(set) var isCancelled = false

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            download?.cancel()
        }
    }

    func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask {
        let task = Task()
        let options: KingfisherOptionsInfo = [
            .processor(DownsamplingImageProcessor(size: targetSize)),
            .scaleFactor(scale),
            .cacheOriginalImage,
            .callbackQueue(.mainCurrentOrAsync)
        ]
        task.download = KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            MainActor.assumeIsolated {
                // Kingfisher 取消后仍以 taskCancelled 回调；协议要求取消后不再调用 completion。
                guard !task.isCancelled else { return }
                completion(result.map(\.image).mapError { $0 as any Error })
            }
        }
        return task
    }
}
