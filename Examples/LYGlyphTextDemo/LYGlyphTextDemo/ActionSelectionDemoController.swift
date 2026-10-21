import LYGlyphText
import UIKit

@MainActor
final class ActionSelectionDemoController: UITableViewController {
    private let documents: [LYGlyphTextDocument]
    private let statusLabel = UILabel()
    private var selectionCount = 0
    private var lastSelectedRow: Int?
    private var eventCount = 0
    private var lastEventID = "-"
    private var lastEventRange = "-"
    private var lastEventRow: Int?
    private var isCallbackEnabled = true

    init(documents: [LYGlyphTextDocument]) {
        self.documents = documents
        super.init(style: .plain)
        title = "动作与列表选择"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(documents:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(ActionSelectionCell.self, forCellReuseIdentifier: "action")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.accessibilityIdentifier = "actionSelectionList"
        statusLabel.accessibilityIdentifier = "actionListStatus"
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        statusLabel.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
        navigationItem.titleView = statusLabel
        let toggle = UIBarButtonItem(title: "关闭回调", style: .plain, target: self, action: #selector(toggleCallback))
        toggle.accessibilityIdentifier = "actionListCallbackToggle"
        navigationItem.rightBarButtonItem = toggle
        updateStatus()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        documents.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath)
        if let cell = cell as? ActionSelectionCell {
            cell.bind(document: documents[indexPath.row], row: indexPath.row, callbackEnabled: isCallbackEnabled) {
                [weak self] event in
                self?.eventCount += 1
                self?.lastEventID = event.actionID
                self?.lastEventRange = "\(event.range.location):\(event.range.length)"
                self?.lastEventRow = indexPath.row
                self?.updateStatus()
            }
        }
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectionCount += 1
        lastSelectedRow = indexPath.row
        updateStatus()
    }

    @objc private func toggleCallback() {
        isCallbackEnabled.toggle()
        navigationItem.rightBarButtonItem?.title = isCallbackEnabled ? "关闭回调" : "开启回调"
        for case let cell as ActionSelectionCell in tableView.visibleCells {
            cell.setCallbackEnabled(isCallbackEnabled)
        }
        updateStatus()
    }

    private func updateStatus() {
        statusLabel.text = "selection=\(selectionCount) last=\(lastSelectedRow.map(String.init) ?? "-") "
            + "events=\(eventCount) row=\(lastEventRow.map(String.init) ?? "-") id=\(lastEventID) "
            + "range=\(lastEventRange) callback=\(isCallbackEnabled ? "A" : "nil")"
    }
}

@MainActor
final class ActionSelectionCell: UITableViewCell {
    let glyphLabel = LYGlyphTextLabel(frame: .zero)
    private var callback: ((LYGlyphTextActionEvent) -> Void)?
    private var minimumHeightConstraint: NSLayoutConstraint?
    #if DEBUG
        private let diagnosticOverlay = ActionDiagnosticOverlay(frame: .zero)
    #endif

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        glyphLabel.configuration = .init(
            textContainerInset: UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18),
            verticalAlignment: .center
        )
        contentView.addSubview(glyphLabel)
        NSLayoutConstraint.activate([
            glyphLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            glyphLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            glyphLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            glyphLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
        #if DEBUG
            diagnosticOverlay.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(diagnosticOverlay)
            NSLayoutConstraint.activate([
                diagnosticOverlay.leadingAnchor.constraint(equalTo: glyphLabel.leadingAnchor),
                diagnosticOverlay.trailingAnchor.constraint(equalTo: glyphLabel.trailingAnchor),
                diagnosticOverlay.topAnchor.constraint(equalTo: glyphLabel.topAnchor),
                diagnosticOverlay.bottomAnchor.constraint(equalTo: glyphLabel.bottomAnchor)
            ])
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        callback = nil
        glyphLabel.onAction = nil
        glyphLabel.document = nil
        #if DEBUG
            diagnosticOverlay.sourceLabel = nil
            diagnosticOverlay.sourceDocument = nil
            diagnosticOverlay.accessibilityIdentifier = nil
        #endif
    }

    func bind(
        document: LYGlyphTextDocument,
        row: Int,
        callbackEnabled: Bool,
        callback: @escaping (LYGlyphTextActionEvent) -> Void
    ) {
        self.callback = callback
        accessibilityIdentifier = "actionSelectionRow\(row)"
        minimumHeightConstraint?.isActive = false
        let minimumHeight = glyphLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: row == 0 ? 360 : 96)
        minimumHeight.isActive = true
        minimumHeightConstraint = minimumHeight
        glyphLabel.document = document
        setCallbackEnabled(callbackEnabled)
        #if DEBUG
            diagnosticOverlay.sourceLabel = glyphLabel
            diagnosticOverlay.sourceDocument = document
            diagnosticOverlay.accessibilityIdentifier = "actionListLabel\(row)"
            diagnosticOverlay.refreshAfterLayout()
        #endif
    }

    func setCallbackEnabled(_ isEnabled: Bool) {
        if isEnabled {
            glyphLabel.onAction = { [weak self] event in self?.callback?(event) }
        } else {
            glyphLabel.onAction = nil
        }
    }
}
