import LYGlyphText
import UIKit

/// 本地生成图片的演示加载器：延迟后返回 120×60pt 的纯色图片并按 URL 缓存，不访问网络。
@MainActor
final class DemoImageLoader: LYGlyphTextImageLoading {
    private final class Task: LYGlyphTextImageLoadingTask {
        var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var loadedCount = 0
    private var cache: [URL: UIImage] = [:]
    var onLoad: (() -> Void)?

    func loadImage(
        from url: URL, targetSize: CGSize, scale: CGFloat,
        completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
    ) -> any LYGlyphTextImageLoadingTask {
        let task = Task()
        if let cached = cache[url] {
            completion(.success(cached))
            return task
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard !task.isCancelled else { return }
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let size = CGSize(width: 120, height: 60)
                let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                }
                self?.cache[url] = image
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
    private let capsule = LYGlyphTextLabel(frame: .zero)
    private let modeControl = UISegmentedControl(items: ["tail", "head", "middle"])
    private let modeLabel = LYGlyphTextLabel(frame: .zero)
    private let markdown = LYGlyphTextLabel(frame: .zero)
    private let markdownStatus = UILabel()
    private let debugSwitch = UISwitch()
    private let remoteSizeStatus = UILabel()
    private var remoteFitted = false

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

        remoteSizeStatus.text = "等待真实尺寸"
        remoteSizeStatus.accessibilityIdentifier = "remoteSizeStatus"
        remote.onRemoteImageLoad = { [weak self] id, size in
            // 只按真实宽高比重建一次（宽度不超过 120pt），避免重建后再次回调形成循环。
            guard let self, !remoteFitted, let document = remote.document, size.width > 0 else { return }
            remoteFitted = true
            let width = min(size.width, 120)
            let fitted = CGSize(width: width, height: width * size.height / size.width)
            remote.document = try? document.replacingRemoteImageSize(id: id, size: fitted)
            remoteSizeStatus.text = "按真实尺寸 \(Int(fitted.width))×\(Int(fitted.height))"
        }

        capsule.accessibilityIdentifier = "capsuleLabel"
        let capsuleStyle = LYGlyphTextBackgroundStyle(
            fillColor: .systemBlue.withAlphaComponent(0.12), strokeColor: .systemBlue, strokeWidth: 1,
            cornerRadius: 6, padding: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
        )
        capsule.document = try? LYGlyphTextParser(rules: [
            .topics(attributes: [.lyGlyphTextBackground: capsuleStyle, .foregroundColor: UIColor.systemBlue])
        ]).document(from: NSAttributedString(string: "参与 #春日摄影# 和 #城市漫步# 话题", attributes: [.font: body]))

        modeControl.accessibilityIdentifier = "truncationModeControl"
        modeControl.selectedSegmentIndex = 0
        modeControl.addAction(UIAction { [weak self] _ in self?.updateTruncationMode() }, for: .valueChanged)
        modeLabel.accessibilityIdentifier = "modeLabel"
        modeLabel.configuration.numberOfLines = 1
        modeLabel.document = try? LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "开头部分" + String(repeating: "很长的中间内容", count: 8) + "全文结束",
            attributes: [.font: body]
        ))

        markdown.accessibilityIdentifier = "markdownLabel"
        markdown.document = try? LYGlyphTextParser(rules: [.markdownEmphasis(), .markdownLinks()])
            .document(from: NSAttributedString(
                string: "**粗体**、*斜体*、`code` 和 [查看文档](https://example.invalid/docs)", attributes: [.font: body]
            ))
        markdown.onAction = { [weak self] event in self?.markdownStatus.text = "链接：\(event.actionID)" }
        markdownStatus.text = "未点击链接"
        markdownStatus.accessibilityIdentifier = "markdownStatus"

        debugSwitch.accessibilityIdentifier = "debugSwitch"
        debugSwitch.accessibilityLabel = "调试叠加"
        debugSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let options: LYGlyphTextDebugOptions = debugSwitch.isOn ? .all : []
            for label in [selectable, truncated, remote, tappable, capsule, modeLabel, markdown] {
                label.debugOptions = options
            }
        }, for: .valueChanged)
        let debugRow = UIStackView(arrangedSubviews: [UILabel.caption("调试叠加"), debugSwitch])
        debugRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [
            selectable, selectionStatus, truncated, tokenStatus, remote, remoteStatus, remoteSizeStatus, tappable,
            tapStatus, capsule, modeControl, modeLabel, markdown, markdownStatus, debugRow
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func updateTruncationMode() {
        modeLabel.configuration.truncationMode = switch modeControl.selectedSegmentIndex {
        case 1: .head
        case 2: .middle
        default: .tail
        }
    }

    @objc private func pasteboardChanged() {
        selectionStatus.text = "已拷贝：\(UIPasteboard.general.string ?? "")"
    }
}

private extension UILabel {
    static func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        return label
    }
}
