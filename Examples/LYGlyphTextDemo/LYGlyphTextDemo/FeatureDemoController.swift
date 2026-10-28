import LYGlyphText
import UIKit

/// 本地生成图片的演示加载器：延迟后返回纯色头像，不访问网络。
@MainActor
final class DemoImageLoader: LYGlyphTextImageLoading {
    private final class Task: LYGlyphTextImageLoadingTask {
        var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var loadedCount = 0
    var onLoad: (() -> Void)?

    func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask {
        let task = Task()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard !task.isCancelled else { return }
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let image = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(origin: .zero, size: targetSize))
                }
                completion(.success(image))
                self?.loadedCount += 1
                self?.onLoad?()
            }
        }
        return task
    }
}

/// 2.x Label 能力：可点击截断 token、网络图片附件、长按选择与拷贝。
@MainActor
final class FeatureDemoController: UIViewController {
    private let loader = DemoImageLoader()
    private let selectable = LYGlyphTextLabel(frame: .zero)
    private let selectionStatus = UILabel()
    private let truncated = LYGlyphTextLabel(frame: .zero)
    private let tokenStatus = UILabel()
    private let remote = LYGlyphTextLabel(frame: .zero)
    private let remoteStatus = UILabel()
    private let tappable = LYGlyphTextLabel(frame: .zero)
    private let tapStatus = UILabel()
    private var tapCount = 0

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "2.x 能力"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init()")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let body = UIFont.preferredFont(forTextStyle: .body)

        selectable.isSelectable = true
        selectable.accessibilityIdentifier = "selectableLabel"
        selectable.document = try? LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "长按选择这段文字，然后在系统菜单中拷贝 Select and copy",
            attributes: [.font: body]
        ))
        selectable.onSelectionChange = { [weak self] range in
            self?.selectionStatus.text = range == nil ? "未选择" : "已选：\(self?.selectable.selectedText ?? "")"
        }
        selectionStatus.text = "未选择"
        selectionStatus.accessibilityIdentifier = "selectionStatus"
        // selector 观察者随控制器释放自动移除。
        NotificationCenter.default.addObserver(
            self, selector: #selector(pasteboardChanged), name: UIPasteboard.changedNotification, object: nil
        )

        truncated.accessibilityIdentifier = "tokenLabel"
        truncated.configuration.numberOfLines = 2
        truncated.configuration.truncationToken = LYGlyphTextTruncationToken(
            text: "…展开全文", foregroundColor: .systemBlue, actionID: "expand", pressedCornerRadius: 4
        )
        truncated.document = try? LYGlyphTextDocument(attributedText: NSAttributedString(
            string: String(repeating: "超过两行的动态内容会在末尾显示可点击的展开按钮。", count: 6),
            attributes: [.font: body]
        ))
        truncated.onAction = { [weak self] event in
            guard event.isTruncationToken else { return }
            self?.truncated.configuration.numberOfLines = 0
            self?.tokenStatus.text = "已展开"
        }
        tokenStatus.text = "未展开"
        tokenStatus.accessibilityIdentifier = "tokenStatus"

        remote.accessibilityIdentifier = "remoteLabel"
        remote.imageLoader = loader
        if let url = URL(string: "https://example.invalid/avatar.png") {
            remote.document = try? LYGlyphTextDocument(segments: [
                .remoteImage(.init(
                    id: "avatar", url: url, size: CGSize(width: 28, height: 28), alignment: .center,
                    placeholder: UIImage(systemName: "person.circle"), alternativeText: "头像"
                )),
                .text(NSAttributedString(string: " 作者头像来自加载器", attributes: [.font: body]))
            ])
        }
        loader.onLoad = { [weak self] in
            self?.remoteStatus.text = "已加载 \(self?.loader.loadedCount ?? 0) 张"
        }
        remoteStatus.text = "加载中"
        remoteStatus.accessibilityIdentifier = "remoteStatus"

        tappable.accessibilityIdentifier = "tapLabel"
        if let document = try? LYGlyphTextDocument(
            // 动作放在首行中间，避免跨行后无障碍框中心落在两行之间。
            attributedText: NSAttributedString(string: "「作者」发布了这张卡片，点击任意文字打开详情", attributes: [.font: body]),
            actions: [.init(actionID: "author", range: NSRange(location: 1, length: 2))]
        ) {
            tappable.document = document
        }
        tappable.onAction = { [weak self] event in self?.tapStatus.text = "动作：\(event.actionID)" }
        tappable.onTap = { [weak self] _ in
            guard let self else { return }
            tapCount += 1
            tapStatus.text = "整段点击 \(tapCount) 次"
        }
        tapStatus.text = "未点击"
        tapStatus.accessibilityIdentifier = "tapStatus"

        let stack = UIStackView(arrangedSubviews: [
            selectable, selectionStatus, truncated, tokenStatus, remote, remoteStatus, tappable, tapStatus
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }

    @objc private func pasteboardChanged() {
        selectionStatus.text = "已拷贝：\(UIPasteboard.general.string ?? "")"
    }
}
