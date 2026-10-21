import LYGlyphText
import UIKit

@MainActor
final class UIKitEnvironmentController: UIViewController {
    let samples: EnvironmentSamples
    let glyphLabel = LYGlyphTextLabel(frame: .zero)
    private let previewController = UIViewController()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let selectionLabel = UILabel()
    private let eventLabel = UILabel()
    private let state = EnvironmentEventState()
    private var selection = EnvironmentSelection()
    private var widthConstraint: NSLayoutConstraint?
    private var controls: [UISegmentedControl] = []

    init(samples: EnvironmentSamples) {
        self.samples = samples
        super.init(nibName: nil, bundle: nil)
        title = "UIKit 环境与无障碍"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scroll.accessibilityIdentifier = "environmentScroll"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        let names = ["Size", "Scheme", "Direction", "Width", "Lines", "Callback"]
        for (index, titles) in [
            ["L", "XXXL", "AX5"],
            ["Light", "Dark"],
            ["LTR", "RTL"],
            ["160", "320"],
            ["1", "不限"],
            ["A", "B"]
        ].enumerated() {
            let control = UISegmentedControl(items: titles)
            control.accessibilityIdentifier = "environment\(names[index])"
            control.selectedSegmentIndex = [0, 0, 0, 1, 1, 0][index]
            control.addTarget(self, action: #selector(changed), for: .valueChanged)
            controls.append(control)
            stack.addArrangedSubview(control)
        }
        for (label, identifier) in [(selectionLabel, "environmentSelection"), (eventLabel, "environmentEvents")] {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.numberOfLines = 0
            label.accessibilityIdentifier = identifier
            stack.addArrangedSubview(label)
        }
        addChild(previewController)
        previewController.view.backgroundColor = .secondarySystemBackground
        stack.addArrangedSubview(previewController.view)
        previewController.didMove(toParent: self)
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        previewController.view.addSubview(glyphLabel)
        let width = glyphLabel.widthAnchor.constraint(equalToConstant: 320)
        widthConstraint = width
        NSLayoutConstraint.activate([
            glyphLabel.centerXAnchor.constraint(equalTo: previewController.view.centerXAnchor),
            glyphLabel.topAnchor.constraint(equalTo: previewController.view.topAnchor),
            glyphLabel.bottomAnchor.constraint(equalTo: previewController.view.bottomAnchor),
            width
        ])
        glyphLabel.document = samples.document
        glyphLabel.viewProvider = state.provider
        state.onChange = { [weak self] in self?.eventLabel.text = self?.state.status }
        updatePreview()
    }

    @objc private func changed() {
        selection.sizeIndex = controls[0].selectedSegmentIndex
        selection.isDark = controls[1].selectedSegmentIndex == 1
        selection.isRTL = controls[2].selectedSegmentIndex == 1
        selection.width = controls[3].selectedSegmentIndex == 0 ? 160 : 320
        selection.isSingleLine = controls[4].selectedSegmentIndex == 0
        selection.callback = controls[5].selectedSegmentIndex == 0 ? "A" : "B"
        updatePreview()
    }

    private func updatePreview() {
        overrideUserInterfaceStyle = selection.isDark ? .dark : .light
        // 仅当前 navigationItem 的颜色跟随此页，避免修改共享导航栏或返回首页的环境。
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        let colors = UITraitCollection(userInterfaceStyle: overrideUserInterfaceStyle)
        appearance.backgroundColor = UIColor.systemBackground.resolvedColor(with: colors)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label.resolvedColor(with: colors)]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            .init(preferredContentSizeCategory: selection.category),
            .init(userInterfaceStyle: selection.isDark ? .dark : .light),
            .init(layoutDirection: selection.isRTL ? .rightToLeft : .leftToRight)
        ]), forChild: previewController)
        previewController.view.semanticContentAttribute = selection.isRTL ? .forceRightToLeft : .forceLeftToRight
        glyphLabel.semanticContentAttribute = selection.isRTL ? .forceRightToLeft : .forceLeftToRight
        widthConstraint?.constant = CGFloat(selection.width)
        glyphLabel.preferredMaxLayoutWidth = CGFloat(selection.width)
        glyphLabel.configuration = selection.configuration
        let callback = selection.callback
        glyphLabel.onAction = { [weak state] event in state?.receive(event, callback: callback) }
        selectionLabel.text = selection.status
        eventLabel.text = state.status
    }
}
