import LYGlyphText
import UIKit

@MainActor
final class UIKitStyleDemoController: UIViewController {
    private let model: StyleDemoModel
    private let attachmentState = DemoAttachmentState()
    private let naturalLabel = LYGlyphTextLabel(frame: .zero)
    private let expandedLabel = LYGlyphTextLabel(frame: .zero)
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let sampleControl = UISegmentedControl(items: StyleSample.allCases.map(\.title))
    private let wrappingControl = UISegmentedControl(items: StyleWrapping.allCases.map(\.title))
    private let verticalControl = UISegmentedControl(items: StyleVerticalAlignment.allCases.map(\.title))
    private let widthControl = UISegmentedControl(items: ["160", "240", "320"])
    private let lineControl = UISegmentedControl(items: LineLimit.allCases.map(\.title))
    private var previewWidths: [NSLayoutConstraint] = []
    private var expandedHeight: NSLayoutConstraint?

    init(samples: StyleDemoSamples) {
        model = StyleDemoModel(samples: samples)
        super.init(nibName: nil, bundle: nil)
        title = "UIKit 样式"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        let controls = [sampleControl, wrappingControl, verticalControl, widthControl, lineControl]
        let identifiers = [
            "styleSampleControl", "styleWrappingControl", "styleVerticalControl", "styleWidthControl",
            "styleLineLimitControl"
        ]
        for (control, identifier) in zip(controls, identifiers) {
            control.selectedSegmentIndex = 0
            control.accessibilityIdentifier = identifier
            control.addTarget(self, action: #selector(updateSelection), for: .valueChanged)
            stack.addArrangedSubview(control)
            control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        widthControl.selectedSegmentIndex = 1
        lineControl.selectedSegmentIndex = 2
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "styleStatus"
        stack.addArrangedSubview(statusLabel)
        for (label, identifier, caption) in [
            (naturalLabel, "styleNaturalPreview", "自然高度"),
            (expandedLabel, "styleExpandedPreview", "相同内容，展示高度增加 60pt")
        ] {
            let heading = UILabel()
            heading.text = caption
            heading.font = .preferredFont(forTextStyle: .caption1)
            heading.textColor = .secondaryLabel
            stack.addArrangedSubview(heading)
            label.accessibilityIdentifier = identifier
            label.backgroundColor = .secondarySystemBackground
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor.systemGray.cgColor
            label.viewProvider = attachmentState.provider
            stack.addArrangedSubview(label)
            let width = label.widthAnchor.constraint(equalToConstant: 240)
            width.isActive = true
            previewWidths.append(width)
        }
        let height = expandedLabel.heightAnchor.constraint(equalToConstant: 100)
        height.isActive = true
        expandedHeight = height
        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.accessibilityIdentifier = "styleAttachmentCount"
        let clear = UIButton(type: .system)
        clear.setTitle("清空", for: .normal)
        clear.accessibilityIdentifier = "styleClear"
        clear.addTarget(self, action: #selector(clearContent), for: .touchUpInside)
        let reload = UIButton(type: .system)
        reload.setTitle("重新加载", for: .normal)
        reload.accessibilityIdentifier = "styleReload"
        reload.addTarget(self, action: #selector(reloadContent), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [countLabel, clear, reload])
        actions.distribution = .equalSpacing
        stack.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        attachmentState.onCountChanged = { [weak self] in self?.updateCount() }
        updateCount()
        applyContent()
    }

    @objc private func updateSelection() {
        model.sample = StyleSample.allCases[sampleControl.selectedSegmentIndex]
        model.wrapping = StyleWrapping.allCases[wrappingControl.selectedSegmentIndex]
        model.verticalAlignment = StyleVerticalAlignment.allCases[verticalControl.selectedSegmentIndex]
        model.width = [160, 240, 320][widthControl.selectedSegmentIndex]
        model.lineLimit = LineLimit.allCases[lineControl.selectedSegmentIndex]
        applyContent()
    }

    private func applyContent() {
        for label in [naturalLabel, expandedLabel] {
            label.document = model.document
            label.configuration = model.configuration
        }
        for width in previewWidths {
            width.constant = CGFloat(model.width)
        }
        expandedHeight?.constant = model.naturalHeight + 60
        statusLabel.text = model.status
    }

    @objc private func clearContent() {
        model.isCleared = true
        applyContent()
    }

    @objc private func reloadContent() {
        model.isCleared = false
        applyContent()
        naturalLabel.reloadAttachments()
        expandedLabel.reloadAttachments()
    }

    private func updateCount() {
        countLabel.text = "按钮点击：\(attachmentState.count)"
    }
}
