import Kingfisher
import LYGlyphText
import os
import UIKit

/// 仅 Demo 使用的业务风格图文列表：每行 100—300 字、3—5 个表情、@／#／链接与带图标的截断 token。
///
/// 数据到达后在后台预排版，cell 直接采用预排版结果；`--feed-profile` 启动时自动往返滚动 45 秒（默认 2800pt/s，
/// 可用启动参数 `-feedScrollSpeed 800` 调整），供 Instruments 的 Animation Hitches 与 Time Profiler 录制。
/// 启动参数 `-feedUseUILabel YES` 改用系统 UILabel（相同文字与 NSTextAttachment 表情）作为对照组。
/// 自动滚动区间记录为 os_signpost “FeedScroll”。默认只使用本地生成的表情图片，不访问网络。
///
/// 启动参数 `-feedRemoteImages YES` 让每行带 1—2 张网络图片附件（公网 PNG，查询参数区分 270 个地址），
/// `-feedImageLoader kingfisher` 改用 Demo 的 Kingfisher 桥接，默认内置 `LYGlyphTextURLSessionImageLoader`。
/// 该模式启动时清空所用加载器的内存与磁盘缓存。自动滚动期间每秒记录一次进程 RSS，结束后与图片加载计数
/// 一起写入本 App 沙盒 Documents 的 `feed-profile.json`。
@MainActor
final class FeedPerformanceController: UIViewController, UITableViewDataSource {
    fileprivate static let horizontalInset: CGFloat = 16
    private static let rowCount = 180
    private static let signposter = OSSignposter(subsystem: "dev.lyglyphtext.demo", category: "Performance")
    let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let shouldProfile: Bool
    private let usesUILabel: Bool
    private let imageLoader: (any LYGlyphTextImageLoading)?
    private let loaderName: String
    private var loadedImageCount = 0
    private var memorySamples: [[String: Double]] = []
    private var lastMemorySample: UInt64 = 0
    private let speed: CGFloat = {
        let value = UserDefaults.standard.double(forKey: "feedScrollSpeed")
        return value > 0 ? value : 2800
    }()

    private let inputs: [NSAttributedString]
    private var documents: [LYGlyphTextDocument] = []
    private var plainTexts: [NSAttributedString] = []
    private var prepared: [Int: LYGlyphTextPreparedLayout] = [:]
    private let configuration: LYGlyphTextConfiguration
    private var displayLink: CADisplayLink?
    private var scrollInterval: OSSignpostIntervalState?
    private var profileStart: UInt64 = 0
    private var lastTick: UInt64 = 0
    private var direction: CGFloat = 1
    private var hasPrepared = false
    /// 预排版完成并刷新列表后为 true，供基准测试等待。
    private(set) var isReady = false

    /// - Parameter usesUILabel: nil 时读取启动参数 `-feedUseUILabel`。
    /// - Parameter remoteImages: nil 时读取启动参数 `-feedRemoteImages`；UILabel 对照组忽略。
    init(profile: Bool = false, usesUILabel: Bool? = nil, remoteImages: Bool? = nil) throws {
        shouldProfile = profile
        self.usesUILabel = usesUILabel ?? UserDefaults.standard.bool(forKey: "feedUseUILabel")
        let usesRemoteImages = !self.usesUILabel
            && (remoteImages ?? UserDefaults.standard.bool(forKey: "feedRemoteImages"))
        if !usesRemoteImages {
            imageLoader = nil
            loaderName = "无"
        } else if UserDefaults.standard.string(forKey: "feedImageLoader") == "kingfisher" {
            KingfisherManager.shared.cache.clearMemoryCache()
            KingfisherManager.shared.cache.clearDiskCache()
            imageLoader = KingfisherImageLoader()
            loaderName = "Kingfisher"
        } else {
            let loader = LYGlyphTextURLSessionImageLoader()
            loader.removeAllCachedImages()
            imageLoader = loader
            loaderName = "内置加载器"
        }
        let chevron = UIImage(systemName: "chevron.down")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        configuration = LYGlyphTextConfiguration(
            numberOfLines: 5,
            truncationToken: .init(
                pieces: [.text("…"), .text("全文", foregroundColor: .systemBlue)]
                    + (chevron.map { [.image($0, size: CGSize(width: 12, height: 8))] } ?? []),
                actionID: "expand"
            )
        )
        let images = Self.emoticonImages()
        inputs = Self.makeInputs(names: images.keys.sorted())
        super.init(nibName: nil, bundle: nil)
        title = "业务图文 · 180 行"
        if self.usesUILabel {
            plainTexts = inputs.map { Self.systemText($0, images: images) }
        } else if usesRemoteImages {
            documents = try inputs.enumerated().map { try Self.remoteDocument($1, row: $0, images: images) }
        } else {
            let parser = LYGlyphTextParser(rules: [
                .emoticons(images, size: CGSize(width: 20, height: 20)),
                .links(), .mentions(), .topics()
            ])
            documents = try inputs.map { try parser.document(from: $0) }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(profile:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "feedStatus"
        tableView.accessibilityIdentifier = "feedTable"
        tableView.register(FeedCell.self, forCellReuseIdentifier: FeedCell.reuseID)
        tableView.register(SystemFeedCell.self, forCellReuseIdentifier: SystemFeedCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 140
        tableView.dataSource = self
        let stack = UIStackView(arrangedSubviews: [statusLabel, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        statusLabel.text = usesUILabel ? "UILabel 对照组" : "预排版中…"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPrepared else { return }
        hasPrepared = true
        // 预排版宽度必须等于 Label 实际宽度，否则 Label 会回到普通排版路径。
        let width = tableView.bounds.width - Self.horizontalInset * 2
        Task { await prepareAll(width: width) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        finishProfile()
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        usesUILabel ? plainTexts.count : documents.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if usesUILabel {
            let cell = tableView.dequeueReusableCell(withIdentifier: SystemFeedCell.reuseID, for: indexPath)
            (cell as? SystemFeedCell)?.bind(plainTexts[indexPath.row])
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: FeedCell.reuseID, for: indexPath)
        (cell as? FeedCell)?.bind(
            document: documents[indexPath.row], configuration: configuration, prepared: prepared[indexPath.row],
            imageLoader: imageLoader
        ) { [weak self] in
            self?.loadedImageCount += 1
        }
        return cell
    }

    /// 模拟数据到达后在后台逐行预排版，再一次性刷新列表；UILabel 对照组没有预排版。
    private func prepareAll(width: CGFloat) async {
        let start = DispatchTime.now().uptimeNanoseconds
        let traits = traitCollection
        for (index, document) in documents.enumerated() {
            prepared[index] = await LYGlyphTextPreparedLayout.prepare(
                document: document, configuration: configuration, width: width, traitCollection: traits
            )
        }
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        statusLabel.text = String(
            format: "%@ · 180 行 · %.0fpt · 5 行截断 · 预排版 %.0fms · %.0fpt/s · 网络图片：%@",
            usesUILabel ? "UILabel" : "LYGlyphText", width, milliseconds, speed, loaderName
        )
        tableView.reloadData()
        isReady = true
        if shouldProfile { startProfile() }
    }

    private func startProfile() {
        profileStart = DispatchTime.now().uptimeNanoseconds
        lastTick = profileStart
        recordMemory(now: profileStart)
        scrollInterval = Self.signposter.beginInterval("FeedScroll")
        let target = FeedDisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(FeedDisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func finishProfile() {
        displayLink?.invalidate()
        displayLink = nil
        if let scrollInterval {
            Self.signposter.endInterval("FeedScroll", scrollInterval)
            self.scrollInterval = nil
            statusLabel.text = (statusLabel.text ?? "") + " · 自动滚动结束 · 已加载图片 \(loadedImageCount) 次"
            writeProfileSummary()
        }
    }

    private func recordMemory(now: UInt64) {
        lastMemorySample = now
        guard let bytes = PerformanceListController.residentSize() else { return }
        memorySamples.append([
            "elapsedSeconds": Double(now - profileStart) / 1_000_000_000, "residentSizeBytes": Double(bytes)
        ])
    }

    /// 只写入本 App 沙盒的 Documents，供真机取回核对内存曲线与图片确实经网络加载。
    private func writeProfileSummary() {
        recordMemory(now: DispatchTime.now().uptimeNanoseconds)
        let summary: [String: Any] = [
            "implementation": usesUILabel ? "UILabel" : "LYGlyphText",
            "speedPointsPerSecond": speed,
            "memorySource": "mach_task_basic_info.resident_size (process RSS bytes; not a leak verdict)",
            "memorySamples": memorySamples,
            "loader": loaderName,
            "loadedImageCallbacks": loadedImageCount,
            "remoteImageCount": imageLoader == nil ? 0
                : documents.indices.reduce(0) { $0 + Self.remoteImageCount(row: $1) },
            "elapsedSeconds": Double(DispatchTime.now().uptimeNanoseconds - profileStart) / 1_000_000_000
        ]
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: directory.appendingPathComponent("feed-profile.json"), options: .atomic)
    }

    fileprivate func profileTick() {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - profileStart < 45_000_000_000 else {
            finishProfile()
            return
        }
        let delta = min(Double(now - lastTick) / 1_000_000_000, 0.1)
        lastTick = now
        let maximum = max(0, tableView.contentSize.height - tableView.bounds.height)
        var offset = tableView.contentOffset.y + direction * speed * delta
        if offset >= maximum {
            offset = maximum
            direction = -1
        } else if offset <= 0 {
            offset = 0
            direction = 1
        }
        tableView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if now - lastMemorySample >= 1_000_000_000 { recordMemory(now: now) }
    }

    private static func emoticonImages() -> [String: UIImage] {
        let names = ["[微笑]", "[点赞]", "[鼓掌]", "[爱心]", "[太阳]"]
        let colors: [UIColor] = [.systemYellow, .systemOrange, .systemPink, .systemRed, .systemTeal]
        var images: [String: UIImage] = [:]
        for (name, color) in zip(names, colors) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            images[name] = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { _ in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 18, height: 18)).fill()
            }
        }
        return images
    }

    private static func makeInputs(names: [String]) -> [NSAttributedString] {
        let sentences = [
            "今天和 @小明 一起去看了日落，天空从橙色慢慢变成紫色，真的太好看了。",
            "参与 #城市漫步# 第三站，沿着老街走了两个小时，发现很多有意思的小店。",
            "分享一篇关于排版的文章 https://example.invalid/typesetting 写得很详细。",
            "周末的咖啡店人很多，我们找了靠窗的位置，一边聊天一边看书。",
            "感谢 @设计组 的同学们，这次活动的海报和视觉都做得非常用心。",
            "春天到了，公园里的花陆续开放，#春日摄影# 的投稿也越来越多。"
        ]
        let body = UIFont.preferredFont(forTextStyle: .body)
        return (0 ..< rowCount).map { row in
            var text = ""
            var cursor = row
            let targetLength = 100 + (row * 37) % 201
            var emoticonCount = 0
            let maxEmoticons = 3 + row % 3
            while text.count < targetLength {
                text += sentences[cursor % sentences.count]
                if emoticonCount < maxEmoticons {
                    text += names[(cursor + emoticonCount) % names.count]
                    emoticonCount += 1
                }
                cursor += 1
            }
            return NSAttributedString(string: text, attributes: [.font: body, .foregroundColor: UIColor.label])
        }
    }

    private static let remoteImageBase = "https://raw.githubusercontent.com/onevcat/Kingfisher/master/images/logo.png"

    /// 偶数行 2 张、奇数行 1 张网络图片。
    private static func remoteImageCount(row: Int) -> Int {
        row.isMultiple(of: 2) ? 2 : 1
    }

    /// 网络图片模式：第一张图放在行首，第二张放在第一个句号之后；表情与 @／#／链接按解析器相同的规则
    /// 拆成图片片段和动作片段（解析器的输出不能再插入远程图片）。
    private static func remoteDocument(
        _ input: NSAttributedString, row: Int, images: [String: UIImage]
    ) throws -> LYGlyphTextDocument {
        let attributes = input.attributes(at: 0, effectiveRange: nil)
        let text = input.string as NSString
        let split = text.range(of: "。")
        let head = split.location == NSNotFound ? text as String : text.substring(to: split.location + 1)
        let tail = split.location == NSNotFound ? "" : text.substring(from: split.location + 1)
        var counter = 0
        var segments: [LYGlyphTextSegment] = []
        for index in 0 ..< remoteImageCount(row: row) {
            guard let url = URL(string: remoteImageBase + "?feed=\(row)-\(index)") else { continue }
            let remote = LYGlyphTextRemoteImageAttachment(
                id: "remote-\(index)", url: url, size: CGSize(width: 48, height: 24), alignment: .center,
                contentMode: .scaleAspectFit, placeholder: UIImage(systemName: "photo"), alternativeText: "配图"
            )
            if index > 0 { segments += tokenSegments(head, attributes: attributes, images: images, counter: &counter) }
            segments.append(.remoteImage(remote, attributes: attributes))
        }
        segments += tokenSegments(
            remoteImageCount(row: row) > 1 ? tail : head + tail, attributes: attributes, images: images,
            counter: &counter
        )
        return try LYGlyphTextDocument(segments: segments)
    }

    private static let tokenExpression = try? NSRegularExpression(
        pattern: "\\[[^\\]]+\\]|@[\\p{L}\\p{N}_]+|#[^#\\n]+#|https?://[A-Za-z0-9./_-]+"
    )

    private static func tokenSegments(
        _ string: String, attributes: [NSAttributedString.Key: Any], images: [String: UIImage],
        counter: inout Int
    ) -> [LYGlyphTextSegment] {
        let source = string as NSString
        var segments: [LYGlyphTextSegment] = []
        var cursor = 0
        func plain(upTo location: Int) {
            guard location > cursor else { return }
            let range = NSRange(location: cursor, length: location - cursor)
            segments.append(.text(NSAttributedString(string: source.substring(with: range), attributes: attributes)))
        }
        let matches = tokenExpression?.matches(in: string, range: NSRange(location: 0, length: source.length)) ?? []
        for match in matches {
            let token = source.substring(with: match.range)
            if token.hasPrefix("[") {
                guard let image = images[token] else { continue }
                plain(upTo: match.range.location)
                counter += 1
                segments.append(.image(
                    .init(
                        id: "emoticon-\(counter)", image: image, size: CGSize(width: 20, height: 20),
                        alignment: .center, alternativeText: token
                    ),
                    attributes: attributes
                ))
            } else {
                plain(upTo: match.range.location)
                var linked = attributes
                linked[.foregroundColor] = UIColor.link
                let id = token.hasPrefix("@") ? "mention:" + token.dropFirst()
                    : token.hasPrefix("#") ? "topic:" + token.dropFirst().dropLast() : token
                segments.append(.text(NSAttributedString(string: token, attributes: linked), actionID: id))
            }
            cursor = match.range.location + match.range.length
        }
        plain(upTo: source.length)
        return segments
    }

    /// 对照组：表情短码替换为 20pt 的 NSTextAttachment，其余文字与属性相同。
    private static func systemText(_ input: NSAttributedString, images: [String: UIImage]) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: input)
        for (name, image) in images {
            while case let range = (result.string as NSString).range(of: name), range.location != NSNotFound {
                let attachment = NSTextAttachment(image: image)
                attachment.bounds = CGRect(x: 0, y: -4, width: 20, height: 20)
                let replacement = NSMutableAttributedString(attachment: attachment)
                replacement.addAttributes(
                    input.attributes(at: 0, effectiveRange: nil),
                    range: NSRange(location: 0, length: replacement.length)
                )
                result.replaceCharacters(in: range, with: replacement)
            }
        }
        return result
    }
}

/// CADisplayLink 持有 target，但 target 只弱引用页面。
@MainActor
private final class FeedDisplayLinkTarget: NSObject {
    weak var owner: FeedPerformanceController?

    init(owner: FeedPerformanceController) {
        self.owner = owner
    }

    @objc func tick() {
        owner?.profileTick()
    }
}

@MainActor
private final class FeedCell: UITableViewCell {
    static let reuseID = "FeedCell"
    private let label = LYGlyphTextLabel(frame: .zero)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: FeedPerformanceController.horizontalInset
            ),
            label.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -FeedPerformanceController.horizontalInset
            ),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    func bind(
        document: LYGlyphTextDocument, configuration: LYGlyphTextConfiguration, prepared: LYGlyphTextPreparedLayout?,
        imageLoader: (any LYGlyphTextImageLoading)?, onImageLoad: @escaping @MainActor () -> Void
    ) {
        label.imageLoader = imageLoader
        if imageLoader != nil {
            label.onRemoteImageLoad = { _, _ in onImageLoad() }
        }
        label.configuration = configuration
        if let prepared {
            label.apply(prepared)
        } else {
            label.document = document
        }
    }
}

@MainActor
private final class SystemFeedCell: UITableViewCell {
    static let reuseID = "SystemFeedCell"
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        label.numberOfLines = 5
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: FeedPerformanceController.horizontalInset
            ),
            label.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -FeedPerformanceController.horizontalInset
            ),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    func bind(_ text: NSAttributedString) {
        label.attributedText = text
    }
}
