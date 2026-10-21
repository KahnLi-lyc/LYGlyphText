import Combine
import UIKit
#if DEBUG
    @testable import LYGlyphText
#else
    import LYGlyphText
#endif

@MainActor
final class HostMatrixTableController: UITableViewController {
    let samples: HostMatrixSamples
    private(set) var content: HostMatrixContent
    private(set) var callback: HostMatrixCallback
    private(set) var rowStates: [Int: HostMatrixRowState] = [:]

    init(
        samples: HostMatrixSamples,
        content: HostMatrixContent = .shortText,
        callback: HostMatrixCallback = .a
    ) {
        self.samples = samples
        self.content = content
        self.callback = callback
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:content:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(HostMatrixTableCell.self, forCellReuseIdentifier: HostMatrixTableCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.dataSource = self
        tableView.delegate = self
    }

    func setContent(_ content: HostMatrixContent) {
        self.content = content
        tableView.reloadData()
    }

    func state(for rowID: Int) -> HostMatrixRowState {
        if let state = rowStates[rowID] { return state }
        let state = HostMatrixRowState(rowID: rowID)
        state.selectCallback(callback)
        rowStates[rowID] = state
        return state
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        samples.rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HostMatrixTableCell.reuseID, for: indexPath)
        guard let cell = cell as? HostMatrixTableCell else { return cell }
        let row = samples.rows[indexPath.row]
        cell.bind(row: row, content: content, state: state(for: row.id))
        return cell
    }
}

@MainActor
final class HostMatrixTableCell: UITableViewCell {
    static let reuseID = "HostMatrixTableCell"
    static let horizontalInset: CGFloat = 16
    let glyphLabel = LYGlyphTextLabel(frame: .zero)
    let statusLabel = UILabel()
    private(set) var rowID: Int?
    private(set) var eventCount = 0
    private var subscriptions: Set<AnyCancellable> = []
    #if DEBUG
        private let diagnostic = ActionDiagnosticOverlay(frame: .zero)
    #endif

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let stack = UIStackView(arrangedSubviews: [glyphLabel, statusLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 1
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.horizontalInset),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        #if DEBUG
            diagnostic.translatesAutoresizingMaskIntoConstraints = false
            diagnostic.sourceLabel = glyphLabel
            glyphLabel.addSubview(diagnostic)
            NSLayoutConstraint.activate([
                diagnostic.leadingAnchor.constraint(equalTo: glyphLabel.leadingAnchor),
                diagnostic.trailingAnchor.constraint(equalTo: glyphLabel.trailingAnchor),
                diagnostic.topAnchor.constraint(equalTo: glyphLabel.topAnchor),
                diagnostic.bottomAnchor.constraint(equalTo: glyphLabel.bottomAnchor)
            ])
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    override func layoutSubviews() {
        synchronizeMeasurementWidth(contentView.bounds.width)
        super.layoutSubviews()
        if let rowID, let button = descendantButton(in: glyphLabel) {
            button.accessibilityIdentifier = "hostRowAttachmentButton\(rowID)"
        }
        #if DEBUG
            diagnostic.refresh()
        #endif
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        synchronizeMeasurementWidth(targetSize.width)
        return super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        prepareForBinding()
    }

    func prepareForBinding() {
        glyphLabel.onAction = nil
        glyphLabel.document = nil
        glyphLabel.viewProvider = nil
        subscriptions.removeAll()
        rowID = nil
        eventCount = 0
        statusLabel.text = nil
        statusLabel.accessibilityIdentifier = nil
        #if DEBUG
            diagnostic.sourceDocument = nil
            diagnostic.accessibilityIdentifier = "actionPreview"
        #endif
    }

    func bind(row: HostMatrixRow, content: HostMatrixContent, state: HostMatrixRowState) {
        prepareForBinding()
        rowID = row.id
        glyphLabel.onAction = { [weak self, weak state] event in
            self?.eventCount += 1
            state?.receive(event)
        }
        glyphLabel.document = row.documents[content]
        glyphLabel.viewProvider = state.provider
        statusLabel.accessibilityIdentifier = "hostTableRowStatus\(row.id)"
        state.$actionCount.combineLatest(state.$buttonCount, state.$callback)
            .sink { [weak self] action, button, callback in
                guard let self else { return }
                statusLabel.text = "row=\(row.id);event=\(action);button=\(button);callback=\(callback.rawValue);" +
                    "pressed=\(pressedValue)"
            }.store(in: &subscriptions)
        #if DEBUG
            diagnostic.sourceDocument = row.documents[content]
            diagnostic.accessibilityIdentifier = "hostTableAction\(row.id)"
            diagnostic.refreshAfterLayout()
        #endif
    }

    private func synchronizeMeasurementWidth(_ cellWidth: CGFloat) {
        guard cellWidth.isFinite else { return }
        glyphLabel.preferredMaxLayoutWidth = max(0, cellWidth - 2 * Self.horizontalInset)
    }

    private func descendantButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        return view.subviews.lazy.compactMap(descendantButton).first
    }

    private var pressedValue: Int {
        #if DEBUG
            glyphLabel.pressedActionIndex == nil ? 0 : 1
        #else
            0
        #endif
    }
}
