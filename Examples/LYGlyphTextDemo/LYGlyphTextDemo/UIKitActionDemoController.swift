import LYGlyphText
import UIKit

@MainActor
final class UIKitActionDemoController: UIViewController {
    private let samples: DemoSamples
    private let state = ActionDemoState()
    private let textLabel = LYGlyphTextLabel(frame: .zero)
    private let statusLabel = UILabel()
    private let buttonStatusLabel = UILabel()
    private let callbackControl = UISegmentedControl(items: ActionCallbackMode.allCases.map(\.title))
    private let displayControl = UISegmentedControl(items: ["完整", "截断", "裁切"])
    private var clippedHeight: NSLayoutConstraint?
    #if DEBUG
        private let diagnosticOverlay = ActionDiagnosticOverlay(frame: .zero)
    #endif

    init(samples: DemoSamples) {
        self.samples = samples
        super.init(nibName: nil, bundle: nil)
        title = "UIKit 文字交互"
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
        stack.spacing = 14
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
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        callbackControl.selectedSegmentIndex = ActionCallbackMode.a.rawValue
        callbackControl.accessibilityIdentifier = "actionCallbackControl"
        callbackControl.addTarget(self, action: #selector(updateCallback), for: .valueChanged)
        displayControl.selectedSegmentIndex = 0
        displayControl.accessibilityIdentifier = "actionDisplayControl"
        displayControl.addTarget(self, action: #selector(updateDisplay), for: .valueChanged)
        for control in [callbackControl, displayControl] {
            stack.addArrangedSubview(control)
            control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        statusLabel.accessibilityIdentifier = "actionEventStatus"
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.numberOfLines = 0
        buttonStatusLabel.accessibilityIdentifier = "actionButtonStatus"
        buttonStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stack.addArrangedSubview(statusLabel)
        statusLabel.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(buttonStatusLabel)

        textLabel.document = samples.actionDocument
        textLabel.configuration = actionConfiguration(numberOfLines: 0)
        textLabel.viewProvider = state.provider
        textLabel.backgroundColor = .secondarySystemBackground
        textLabel.layer.borderColor = UIColor.systemGray.cgColor
        textLabel.layer.borderWidth = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textLabel)
        textLabel.widthAnchor.constraint(equalToConstant: 330).isActive = true
        textLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        #if DEBUG
            diagnosticOverlay.sourceLabel = textLabel
            diagnosticOverlay.sourceDocument = samples.actionDocument
            diagnosticOverlay.translatesAutoresizingMaskIntoConstraints = false
            textLabel.addSubview(diagnosticOverlay)
            NSLayoutConstraint.activate([
                diagnosticOverlay.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
                diagnosticOverlay.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
                diagnosticOverlay.topAnchor.constraint(equalTo: textLabel.topAnchor),
                diagnosticOverlay.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor)
            ])
        #endif

        let explanation = UILabel()
        explanation.text = "向上拖动动作或普通文字可滚动；原生按钮优先处理自己的触摸。"
        explanation.font = .preferredFont(forTextStyle: .subheadline)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0
        stack.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let marker = UILabel()
        marker.text = "滚动目标"
        marker.accessibilityIdentifier = "actionScrollMarker"
        marker.textColor = .secondaryLabel
        stack.addArrangedSubview(marker)
        marker.heightAnchor.constraint(equalToConstant: 360).isActive = true

        state.onChange = { [weak self] in self?.updateStatus() }
        updateCallback()
        updateStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if DEBUG
            diagnosticOverlay.refresh()
        #endif
    }

    private func actionConfiguration(numberOfLines: Int) -> LYGlyphTextConfiguration {
        .init(
            textContainerInset: UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18),
            numberOfLines: numberOfLines
        )
    }

    @objc private func updateCallback() {
        guard let mode = ActionCallbackMode(rawValue: callbackControl.selectedSegmentIndex) else { return }
        switch mode {
        case .a, .b:
            textLabel.onAction = { [weak self] event in self?.state.receive(event, callback: mode) }
        case .none:
            textLabel.onAction = nil
        }
    }

    @objc private func updateDisplay() {
        clippedHeight?.isActive = false
        clippedHeight = nil
        switch displayControl.selectedSegmentIndex {
        case 1:
            textLabel.configuration = actionConfiguration(numberOfLines: 8)
        case 2:
            textLabel.configuration = actionConfiguration(numberOfLines: 0)
            let height = textLabel.heightAnchor.constraint(equalToConstant: 60)
            height.isActive = true
            clippedHeight = height
        default:
            textLabel.configuration = actionConfiguration(numberOfLines: 0)
        }
        #if DEBUG
            diagnosticOverlay.refreshAfterLayout()
        #endif
    }

    private func updateStatus() {
        statusLabel.text = state.status
        buttonStatusLabel.text = "button=\(state.buttonCount)"
    }
}
