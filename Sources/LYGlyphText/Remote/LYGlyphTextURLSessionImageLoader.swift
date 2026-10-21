import ImageIO
import UIKit

/// 只使用 URLSession、NSCache 与 ImageIO 的轻量加载器：内存缓存、同尺寸请求合并、按目标尺寸降采样，
/// 多帧 GIF 生成动画图片。没有磁盘缓存；宿主需要磁盘缓存或其他格式时可桥接自己的图片库。
///
/// 实例由宿主创建并在多个 Label 间共享；释放加载器会取消其进行中的请求。
@MainActor
public final class LYGlyphTextURLSessionImageLoader: LYGlyphTextImageLoading {
    private final class Waiter: LYGlyphTextImageLoadingTask {
        weak var loader: LYGlyphTextURLSessionImageLoader?
        let key: String
        let completion: @MainActor (Result<UIImage, any Error>) -> Void
        var isActive = true

        init(
            loader: LYGlyphTextURLSessionImageLoader?, key: String,
            completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
        ) {
            self.loader = loader
            self.key = key
            self.completion = completion
        }

        func cancel() {
            guard isActive else { return }
            isActive = false
            loader?.remove(self)
        }
    }

    private struct Request {
        let task: URLSessionDataTask
        var waiters: [Waiter]
    }

    private let session: URLSession
    private let cache = NSCache<NSString, UIImage>()
    private var requests: [String: Request] = [:]
    /// 同时最多解码的 GIF 帧数，超出部分不加载，避免异常大动图占满内存。
    private let maximumFrameCount: Int

    /// 进行中的网络请求数量，用于诊断请求合并与取消。
    var activeRequestCount: Int {
        requests.count
    }

    /// 创建加载器。
    /// - Parameters:
    ///   - configuration: URLSession 配置，默认 `.default`；测试可注入自定义 URLProtocol。
    ///   - memoryCacheCountLimit: 内存缓存的最大图片数，默认 100；0 表示不限制数量。
    ///   - maximumFrameCount: 动图最多保留的帧数，默认 300。
    public init(
        configuration: URLSessionConfiguration = .default, memoryCacheCountLimit: Int = 100,
        maximumFrameCount: Int = 300
    ) {
        session = URLSession(configuration: configuration)
        cache.countLimit = max(0, memoryCacheCountLimit)
        self.maximumFrameCount = max(1, maximumFrameCount)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let pixels = max(targetSize.width, targetSize.height) * scale
        let maxPixelSize = pixels.isFinite && pixels > 0 ? Int(pixels.rounded(.up)) : 0
        let key = "\(maxPixelSize)|\(url.absoluteString)"
        let waiter = Waiter(loader: self, key: key, completion: completion)
        if let cached = cache.object(forKey: key as NSString) {
            waiter.isActive = false
            completion(.success(cached))
            return waiter
        }
        if requests[key] != nil {
            requests[key]?.waiters.append(waiter)
            return waiter
        }
        let frameLimit = maximumFrameCount
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            let result = Self.decode(
                data: data, response: response, error: error, scale: scale, maxPixelSize: maxPixelSize,
                frameLimit: frameLimit
            )
            Task { @MainActor in
                self?.finish(key: key, result: result)
            }
        }
        requests[key] = Request(task: task, waiters: [waiter])
        task.resume()
        return waiter
    }

    private func remove(_ waiter: Waiter) {
        guard var request = requests[waiter.key] else { return }
        request.waiters.removeAll { $0 === waiter }
        if request.waiters.isEmpty {
            request.task.cancel()
            requests[waiter.key] = nil
        } else {
            requests[waiter.key] = request
        }
    }

    private func finish(key: String, result: Result<UIImage, any Error>) {
        guard let request = requests.removeValue(forKey: key) else { return }
        if case let .success(image) = result { cache.setObject(image, forKey: key as NSString) }
        for waiter in request.waiters where waiter.isActive {
            waiter.isActive = false
            waiter.completion(result)
        }
    }

    nonisolated static func decode(
        data: Data?, response: URLResponse?, error: (any Error)?, scale: CGFloat, maxPixelSize: Int,
        frameLimit: Int
    ) -> Result<UIImage, any Error> {
        if let error { return .failure(error) }
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            return .failure(LYGlyphTextImageLoadingError.unacceptableStatusCode(http.statusCode))
        }
        guard let data, let image = decode(data, scale: scale, maxPixelSize: maxPixelSize, frameLimit: frameLimit)
        else { return .failure(LYGlyphTextImageLoadingError.undecodableData) }
        return .success(image)
    }

    /// 单帧按最大像素降采样并应用 EXIF 方向；多帧按 GIF 延时组成动画，过短延时按 0.1 秒处理。
    nonisolated static func decode(_ data: Data, scale: CGFloat, maxPixelSize: Int, frameLimit: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        )
        else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if maxPixelSize > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        func frame(_ index: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        }
        if count == 1 {
            return frame(0).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
        }
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0 ..< min(count, frameLimit) {
            guard let cgImage = frame(index) else { continue }
            images.append(UIImage(cgImage: cgImage, scale: scale, orientation: .up))
            duration += frameDelay(source, index: index)
        }
        guard !images.isEmpty else { return nil }
        return images.count == 1 ? images[0] : UIImage.animatedImage(with: images, duration: duration)
    }

    private nonisolated static func frameDelay(_ source: CGImageSource, index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay.isFinite && delay >= 0.011 ? delay : 0.1
    }
}
