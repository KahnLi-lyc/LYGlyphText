import LYGlyphText
import UIKit

@MainActor
final class UIKitHostMatrixController: UIViewController {
    let samples: HostMatrixSamples
    let rowState: HostMatrixRowState
    let glyphLabel = LYGlyphTextLabel(frame: .zero)

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let previewHost = UIView()
    private let previewStack = UIStackView()
    private let contentControl = UISegmentedControl(items: ["短文", "长文", "小图片", "大图片", "小视图", "大视图", "动作"])
    private let widthControl = UISegmentedControl(items: ["160", "240", "320", "容器"])
    private let alignmentControl = UISegmentedControl(items: ["填充", "前", "中", "后"])
    private let distributionControl = UISegmentedControl(items: ["填充", "等宽", "比例"])
    private let callbackControl = UISegmentedControl(items: ["A", "B"])
    private let currentRowLabel = UILabel()
    private let naturalHeightLabel = UILabel()
    private let eventLabel = UILabel()
    private let buttonLabel = UILabel()
    private var previewWidthConstraint: NSLayoutConstraint?
    #if DEBUG
        private let diagnostic = ActionDiagnosticOverlay(frame: .zero)
    #endif

    init(samples: HostMatrixSamples) {
        self.samples = samples
        rowState = HostMatrixRowState(rowID: samples.rows[0].id)
        super.init(nibName: nil, bundle: nil)
        title = "UIKit 宿主矩阵"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureHierarchy()
        configureControls()
        updatePreview()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let natural = glyphLabel.sizeThatFits(CGSize(width: glyphLabel.bounds.width, height: .infinity)).height
        naturalHeightLabel.text = String(format: "natural=%.1f", Double(natural))
        if let button = descendantButton(in: glyphLabel) {
            button.accessibilityIdentifier = "hostUIKitAttachmentButton"
        }
        buttonLabel.text = "button=\(rowState.buttonCount)"
        #if DEBUG
            diagnostic.sourceLabel = glyphLabel
            diagnostic.refresh()
        #endif
    }

    private func configureHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "hostUIKitScroll"
        view.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -16
            ),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        for control in [contentControl, widthControl, alignmentControl, distributionControl, callbackControl] {
            contentStack.addArrangedSubview(control)
        }
        previewStack.axis = .vertical
        previewStack.spacing = 0
        previewStack.backgroundColor = .secondarySystemGroupedBackground
        previewStack.layer.borderColor = UIColor.separator.cgColor
        previewStack.layer.borderWidth = 1
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        glyphLabel.accessibilityIdentifier = "hostUIKitGlyph"
        glyphLabel.configuration = .init(textContainerInset: .init(top: 8, left: 8, bottom: 8, right: 8))
        previewStack.addArrangedSubview(glyphLabel)
        previewHost.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(previewStack)
        contentStack.addArrangedSubview(previewHost)
        NSLayoutConstraint.activate([
            previewStack.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            previewStack.topAnchor.constraint(equalTo: previewHost.topAnchor),
            previewStack.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor),
            previewStack.widthAnchor.constraint(lessThanOrEqualTo: previewHost.widthAnchor)
        ])
        #if DEBUG
            diagnostic.translatesAutoresizingMaskIntoConstraints = false
            diagnostic.sourceLabel = glyphLabel
            previewStack.addSubview(diagnostic)
            NSLayoutConstraint.activate([
                diagnostic.leadingAnchor.constraint(equalTo: glyphLabel.leadingAnchor),
                diagnostic.trailingAnchor.constraint(equalTo: glyphLabel.trailingAnchor),
                diagnostic.topAnchor.constraint(equalTo: glyphLabel.topAnchor),
                diagnostic.bottomAnchor.constraint(equalTo: glyphLabel.bottomAnchor)
            ])
        #endif

        currentRowLabel.accessibilityIdentifier = "hostUIKitCurrentRow"
        naturalHeightLabel.accessibilityIdentifier = "hostUIKitNaturalHeight"
        eventLabel.accessibilityIdentifier = "hostUIKitEvent"
        buttonLabel.accessibilityIdentifier = "hostUIKitButtonStatus"
        for label in [currentRowLabel, naturalHeightLabel, eventLabel, buttonLabel] {
            label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            label.numberOfLines = 0
            contentStack.addArrangedSubview(label)
        }

        let routes = UIStackView()
        routes.axis = .horizontal
        routes.distribution = .fillEqually
        routes.spacing = 10
        let table = routeButton(title: "Table", identifier: "openHostTable", action: #selector(openTable))
        let collection = routeButton(
            title: "Collection",
            identifier: "openHostCollection",
            action: #selector(openCollection)
        )
        routes.addArrangedSubview(table)
        routes.addArrangedSubview(collection)
        contentStack.addArrangedSubview(routes)
    }

    private func configureControls() {
        contentControl.accessibilityIdentifier = "hostUIKitContent"
        widthControl.accessibilityIdentifier = "hostUIKitWidth"
        alignmentControl.accessibilityIdentifier = "hostUIKitAlignment"
        distributionControl.accessibilityIdentifier = "hostUIKitDistribution"
        callbackControl.accessibilityIdentifier = "hostUIKitCallback"
        contentControl.selectedSegmentIndex = HostMatrixContent.action.rawValue
        widthControl.selectedSegmentIndex = 1
        alignmentControl.selectedSegmentIndex = 0
        distributionControl.selectedSegmentIndex = 0
        callbackControl.selectedSegmentIndex = 0
        for control in [contentControl, widthControl, alignmentControl, distributionControl, callbackControl] {
            control.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
        }
    }

    @objc private func controlChanged() {
        updatePreview()
    }

    private func updatePreview() {
        let content = HostMatrixContent(rawValue: contentControl.selectedSegmentIndex) ?? .shortText
        let callback = callbackControl.selectedSegmentIndex == 0 ? HostMatrixCallback.a : .b
        rowState.selectCallback(callback)
        glyphLabel.onAction = { [weak self, weak rowState] event in
            guard let self, let rowState else { return }
            rowState.receive(event)
            updateEventLabel()
        }
        glyphLabel.document = samples.rows[0].documents[content]
        glyphLabel.viewProvider = rowState.provider
        currentRowLabel.text = "row=0;content=\(content.rawValue);width=\(selectedWidthName)"
        updateEventLabel()
        buttonLabel.text = "button=\(rowState.buttonCount)"

        previewWidthConstraint?.isActive = false
        if let width = selectedWidth {
            previewWidthConstraint = previewStack.widthAnchor.constraint(equalToConstant: width)
            previewWidthConstraint?.isActive = true
        } else {
            previewWidthConstraint = nil
        }
        previewStack.alignment = [.fill, .leading, .center, .trailing][alignmentControl.selectedSegmentIndex]
        previewStack.distribution = [.fill, .fillEqually, .fillProportionally][distributionControl.selectedSegmentIndex]
        #if DEBUG
            diagnostic.sourceDocument = glyphLabel.document
            diagnostic.sourceLabel = glyphLabel
        #endif
        view.setNeedsLayout()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            view.layoutIfNeeded()
            descendantButton(in: glyphLabel)?.accessibilityIdentifier = "hostUIKitAttachmentButton"
        }
    }

    private var selectedWidth: CGFloat? {
        [CGFloat?(160), 240, 320, nil][widthControl.selectedSegmentIndex]
    }

    private var selectedWidthName: String {
        ["160", "240", "320", "container"][widthControl.selectedSegmentIndex]
    }

    private func routeButton(title: String, identifier: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openTable() {
        let controller = HostMatrixTableController(
            samples: samples,
            content: selectedContent,
            callback: selectedCallback
        )
        controller.title = "Host Table"
        controller.tableView.accessibilityIdentifier = "hostMatrixTable"
        navigationController?.pushViewController(controller, animated: false)
    }

    @objc private func openCollection() {
        let controller = HostMatrixCollectionController(
            samples: samples,
            content: selectedContent,
            callback: selectedCallback
        )
        controller.title = "Host Collection"
        controller.collectionView.accessibilityIdentifier = "hostMatrixCollection"
        navigationController?.pushViewController(controller, animated: false)
    }

    private var selectedContent: HostMatrixContent {
        HostMatrixContent(rawValue: contentControl.selectedSegmentIndex) ?? .shortText
    }

    private var selectedCallback: HostMatrixCallback {
        callbackControl.selectedSegmentIndex == 0 ? .a : .b
    }

    private func updateEventLabel() {
        let handledCallback = rowState.lastHandledCallback?.rawValue ?? "none"
        eventLabel.text =
            "event=\(rowState.actionCount);callback=\(rowState.callback.rawValue);" +
            "handled=\(handledCallback);id=\(rowState.lastActionID ?? "none")"
    }

    private func descendantButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        return view.subviews.lazy.compactMap(descendantButton).first
    }
}
