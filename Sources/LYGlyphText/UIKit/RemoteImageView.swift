import UIKit

/// Label 内部持有的远程图片视图；挂载时开始加载，卸载或重新加载时取消，不对宿主公开。
@MainActor
final class RemoteImageView: UIImageView {
    private(set) var descriptor: LYGlyphTextRemoteImageAttachment
    private var task: (any LYGlyphTextImageLoadingTask)?
    private var activeGeneration: Int?
    private(set) var loadCount = 0

    init(descriptor: LYGlyphTextRemoteImageAttachment) {
        self.descriptor = descriptor
        super.init(frame: .zero)
        contentMode = descriptor.contentMode
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        image = descriptor.placeholder
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(descriptor:)")
    }

    /// 取消旧请求后开始新请求；同步完成的缓存结果立即显示，迟到或已取消的回调被忽略。
    /// - Parameter onLoaded: 成功得到图片时在 MainActor 调用，参数为图片 point 尺寸；取消或失败不调用。
    func load(
        using loader: (any LYGlyphTextImageLoading)?, scale: CGFloat,
        onLoaded: @escaping @MainActor (CGSize) -> Void = { _ in }
    ) {
        cancel()
        image = descriptor.placeholder
        guard let loader else { return }
        loadCount += 1
        let generation = loadCount
        activeGeneration = generation
        let task = loader
            .loadImage(from: descriptor.url, targetSize: descriptor.size, scale: scale) { [weak self] result in
                guard let self, activeGeneration == generation else { return }
                activeGeneration = nil
                self.task = nil
                switch result {
                case let .success(image):
                    self.image = image
                    onLoaded(image.size)
                case .failure: image = descriptor.failureImage ?? descriptor.placeholder
                }
            }
        if activeGeneration == generation { self.task = task }
    }

    func cancel() {
        activeGeneration = nil
        task?.cancel()
        task = nil
    }
}
