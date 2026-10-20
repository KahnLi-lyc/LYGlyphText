import LYGlyphText
import UIKit

@MainActor
final class UIKitDemoController: UIViewController {
    private let samples: DemoSamples
    private let textLabel = LYGlyphTextLabel(frame: .zero)
    private let priorityLabel = LYGlyphTextLabel(frame: .zero)
    private let statusLabel = UILabel()
    private let sampleControl = UISegmentedControl(items: SampleKind.allCases.map(\.title))
    private let imageControl = UISegmentedControl(items: ["文字", "图片混排"])
    private let alignmentControl = UISegmentedControl(items: ImageAlignment.allCases.map(\.title))
    private let widthControl = UISegmentedControl(items: ["160", "240", "320"])
    private let lineLimitControl = UISegmentedControl(items: LineLimit.allCases.map(\.title))
    private let priorityControl = UISegmentedControl(items: ["压缩文本", "压缩按钮"])
    private let actionButton = UIButton(type: .system)
    private var textWidth: NSLayoutConstraint?

    init(samples: DemoSamples) {
        self.samples = samples
        super.init(nibName: nil, bundle: nil)
        title = "UIKit"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scrollView = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        sampleControl.selectedSegmentIndex = 0
        sampleControl.accessibilityIdentifier = "sampleControl"
        sampleControl.addTarget(self, action: #selector(updateContent), for: .valueChanged)
        imageControl.selectedSegmentIndex = 0
        imageControl.accessibilityIdentifier = "imageControl"
        imageControl.addTarget(self, action: #selector(updateContent), for: .valueChanged)
        alignmentControl.selectedSegmentIndex = ImageAlignment.bottom.rawValue
        alignmentControl.accessibilityIdentifier = "alignmentControl"
        alignmentControl.addTarget(self, action: #selector(updateContent), for: .valueChanged)
        widthControl.selectedSegmentIndex = 1
        widthControl.accessibilityIdentifier = "widthControl"
        widthControl.addTarget(self, action: #selector(updateContent), for: .valueChanged)
        lineLimitControl.selectedSegmentIndex = 0
        lineLimitControl.accessibilityIdentifier = "lineLimitControl"
        lineLimitControl.addTarget(self, action: #selector(updateContent), for: .valueChanged)
        statusLabel.accessibilityIdentifier = "sampleStatus"
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        textLabel.backgroundColor = .secondarySystemBackground
        textLabel.layer.borderWidth = 1
        textLabel.layer.borderColor = UIColor.systemGray.cgColor
        textLabel.accessibilityIdentifier = "richTextPreview"
        stack.addArrangedSubview(sampleControl)
        stack.addArrangedSubview(imageControl)
        stack.addArrangedSubview(alignmentControl)
        stack.addArrangedSubview(widthControl)
        stack.addArrangedSubview(lineLimitControl)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(textLabel)
        let imageExplanation = UILabel()
        imageExplanation.text = "图片：上向箭头橙标在左上，右向箭头橙标在右上；对齐参照当前字体区域。"
        imageExplanation.numberOfLines = 0
        imageExplanation.font = .preferredFont(forTextStyle: .caption1)
        imageExplanation.textColor = .secondaryLabel
        stack.addArrangedSubview(imageExplanation)
        imageExplanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let width = textLabel.widthAnchor.constraint(equalToConstant: 240)
        width.priority = UILayoutPriority(999)
        width.isActive = true
        textWidth = width
        textLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        let explanation = UILabel()
        explanation.text = "横向优先级：富文本与按钮共享可用宽度。切换下方选项观察谁先被压缩。"
        explanation.numberOfLines = 0
        explanation.font = .preferredFont(forTextStyle: .subheadline)
        stack.addArrangedSubview(explanation)
        priorityControl.selectedSegmentIndex = 0
        priorityControl.addTarget(self, action: #selector(updatePriorities), for: .valueChanged)
        stack.addArrangedSubview(priorityControl)
        let row = UIStackView(arrangedSubviews: [priorityLabel, actionButton])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        priorityLabel.document = samples.documents[.multiline]
        priorityLabel.backgroundColor = .secondarySystemBackground
        actionButton.setTitle("按钮保留完整标题", for: .normal)
        actionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for control in [
            sampleControl,
            imageControl,
            alignmentControl,
            widthControl,
            lineLimitControl,
            priorityControl
        ] {
            control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updatePriorities()
        updateContent()
    }

    @objc private func updateContent() {
        guard let kind = SampleKind(rawValue: sampleControl.selectedSegmentIndex) else { return }
        let widths: [CGFloat] = [160, 240, 320]
        let width = widths[widthControl.selectedSegmentIndex]
        let limit = LineLimit.allCases[lineLimitControl.selectedSegmentIndex]
        let includesImages = imageControl.selectedSegmentIndex == 1
        let alignment = ImageAlignment.allCases[alignmentControl.selectedSegmentIndex]
        alignmentControl.isEnabled = includesImages
        textLabel.document = samples.document(for: kind, includesImages: includesImages, alignment: alignment)
        textLabel.configuration = .init(
            textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
            numberOfLines: limit.rawValue
        )
        textWidth?.constant = width
        let imageStatus = includesImages ? " · 图片混排 · \(alignment.title)" : ""
        statusLabel.text = "\(kind.title) · 宽度 \(Int(width)) · \(limit.title)\(imageStatus)"
        statusLabel.numberOfLines = 0
    }

    @objc private func updatePriorities() {
        let compressText = priorityControl.selectedSegmentIndex == 0
        priorityLabel.setContentCompressionResistancePriority(
            UILayoutPriority(compressText ? 249 : 751),
            for: .horizontal
        )
        actionButton.setContentCompressionResistancePriority(
            UILayoutPriority(compressText ? 750 : 249),
            for: .horizontal
        )
    }
}
