import Combine
import Darwin
import LYGlyphText
import UIKit

/// 仅 Demo 使用的固定负载滚动页面，不参与框架 API。
@MainActor
final class PerformanceListController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private(set) var hasAppeared = false
    private let samples = PerformanceSamples().samples
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var rows: [PerformanceRowState] = []
    private var documents: [LYGlyphTextDocument] = []
    private var isStopped = false
    private let shouldProfile: Bool
    private var displayLink: CADisplayLink?
    private var profileStart: UInt64 = 0
    private var lastSample: UInt64 = 0
    private var lastTick: UInt64 = 0
    private var direction: CGFloat = 1
    private var directionChanges = 0
    private var observations: [Observation] = []
    private var stopSynchronousLive: Int?

    private struct Observation: Encodable {
        let elapsedSeconds: Double
        let offsetPoints: Double
        let direction: Int
        let directionChanges: Int
        let factory: Int
        let unmount: Int
        let liveWeakViews: Int
        let residentSizeBytes: UInt64?
    }

    private struct Profile: Encodable {
        let schemaVersion = 1
        let clock = "DispatchTime.uptimeNanoseconds"
        let memorySource = "mach_task_basic_info.resident_size (process RSS bytes; not a leak verdict)"
        let rowCount = 180
        let contentWidthPoints = 320
        let numberOfLines = 3
        let speedPointsPerSecond = 2800
        let elapsedSeconds: Double
        let directionChanges: Int
        let finalFactory: Int
        let finalUnmount: Int
        let finalLiveWeakViews: Int
        let stopSynchronousLiveWeakViews: Int?
        let finalActions: Int
        let finalButtons: Int
        let completedRoundTrips: Int
        let observations: [Observation]
    }

    init(profile: Bool = false) throws {
        shouldProfile = profile
        super.init(nibName: nil, bundle: nil)
        documents = try samples.map { try $0.makeDocument() }
        rows = (0 ..< 180).map { PerformanceRowState(id: $0) }
        title = "固定负载 · 180 行"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(profile:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.numberOfLines = 0
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.accessibilityIdentifier = "performanceStatus"
        tableView.accessibilityIdentifier = "performanceTable"
        tableView.register(PerformanceCell.self, forCellReuseIdentifier: PerformanceCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.dataSource = self
        tableView.delegate = self
        let stack = UIStackView(arrangedSubviews: [statusLabel, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let stop = UIBarButtonItem(title: "停止并清空", style: .plain, target: self, action: #selector(stopAndClear))
        stop.accessibilityIdentifier = "performanceStop"
        navigationItem.rightBarButtonItem = stop
        for row in rows {
            row.onChange = { [weak self] in self?.refreshStatus() }
        }
        refreshStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        if shouldProfile, profileStart == 0 { startProfile() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hasAppeared = false
        stopAndClear()
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        isStopped ? 0 : rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PerformanceCell.reuseID, for: indexPath)
        if let cell = cell as? PerformanceCell {
            cell.bind(document: documents[indexPath.row % samples.count], state: rows[indexPath.row])
        }
        return cell
    }

    func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isStopped, let cell = cell as? PerformanceCell else { return }
        cell.bind(document: documents[indexPath.row % samples.count], state: rows[indexPath.row])
    }

    func tableView(_: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt _: IndexPath) {
        (cell as? PerformanceCell)?.endDisplaying()
        refreshStatus()
    }

    func rowDiagnostics(_ row: Int) -> (factory: Int, unmount: Int, live: Int, actions: Int, buttons: Int) {
        let state = rows[row]
        return (state.factory, state.unmount, state.live, state.actions, state.buttons)
    }

    private var totals: (factory: Int, unmount: Int, live: Int, actions: Int, buttons: Int) {
        rows.reduce((0, 0, 0, 0, 0)) { value, row in
            (
                value.0 + row.factory,
                value.1 + row.unmount,
                value.2 + row.live,
                value.3 + row.actions,
                value.4 + row.buttons
            )
        }
    }

    private func refreshStatus() {
        let values = totals
        statusLabel.text = "180 行 · 9 组 × 20 · 320pt · 3 行尾部省略\n" +
            "factory=\(values.factory);unmount=\(values.unmount);live=\(values.live);" +
            "action=\(values.actions);button=\(values.buttons);stopped=\(isStopped ? 1 : 0);" +
            "stopSynchronousLive=\(stopSynchronousLive.map(String.init) ?? "pending")"
    }

    @objc private func stopAndClear() {
        displayLink?.invalidate()
        displayLink = nil
        guard !isStopped else { return }
        isStopped = true
        autoreleasepool {
            tableView.visibleCells.compactMap { $0 as? PerformanceCell }.forEach { $0.clear() }
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }
        stopSynchronousLive = totals.live
        refreshStatus()
        // UIKit 当前事件仍可临时持有附件；下个主队列事件读取实际 weak 值，不修改记录。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshStatus()
            if profileStart > 0 { finishProfile() }
        }
    }

    private func startProfile() {
        profileStart = DispatchTime.now().uptimeNanoseconds
        lastTick = profileStart
        lastSample = 0
        recordObservation(now: profileStart)
        let target = PerformanceDisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(PerformanceDisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func profileTick() {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - profileStart < 45_000_000_000 else {
            stopAndClear()
            return
        }
        let delta = min(Double(now - lastTick) / 1_000_000_000, 0.1)
        lastTick = now
        let maximum = max(0, tableView.contentSize.height - tableView.bounds.height)
        var offset = tableView.contentOffset.y + direction * 2800 * delta
        if offset >= maximum {
            offset = maximum
            direction = -1
            directionChanges += 1
        } else if offset <= 0 {
            offset = 0
            direction = 1
            directionChanges += 1
        }
        tableView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if now - lastSample >= 1_000_000_000 { recordObservation(now: now) }
    }

    private func recordObservation(now: UInt64) {
        lastSample = now
        let values = totals
        observations.append(Observation(
            elapsedSeconds: Double(now - profileStart) / 1_000_000_000,
            offsetPoints: Double(tableView.contentOffset.y), direction: direction > 0 ? 1 : -1,
            directionChanges: directionChanges, factory: values.factory, unmount: values.unmount,
            liveWeakViews: values.live, residentSizeBytes: residentSize()
        ))
    }

    private func finishProfile() {
        let now = DispatchTime.now().uptimeNanoseconds
        recordObservation(now: now)
        let values = totals
        let profile = Profile(
            elapsedSeconds: Double(now - profileStart) / 1_000_000_000, directionChanges: directionChanges,
            finalFactory: values.factory, finalUnmount: values.unmount, finalLiveWeakViews: values.live,
            stopSynchronousLiveWeakViews: stopSynchronousLive, finalActions: values.actions,
            finalButtons: values.buttons, completedRoundTrips: directionChanges / 2, observations: observations
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let directory = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            try encoder.encode(profile).write(
                to: directory.appendingPathComponent("performance-scroll.json"),
                options: .atomic
            )
        } catch {
            statusLabel.text = "无法保存滚动记录：\(error)"
        }
    }

    private func residentSize() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
}

/// CADisplayLink 持有 target，但 target 只弱引用页面。
@MainActor
private final class PerformanceDisplayLinkTarget: NSObject {
    weak var owner: PerformanceListController?

    init(owner: PerformanceListController) {
        self.owner = owner
    }

    @objc func tick() {
        owner?.profileTick()
    }
}

@MainActor
private final class PerformanceRowState {
    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) {
            self.view = view
        }
    }

    let id: Int
    var onChange: (() -> Void)?
    private(set) var factory = 0
    private(set) var unmount = 0
    @Published private(set) var actions = 0
    @Published private(set) var buttons = 0
    private var records: [WeakView] = []
    var live: Int {
        records.count(where: { $0.view != nil })
    }

    lazy var provider = LYGlyphTextAttachmentViewProvider(makeView: { [weak self] attachment in
        guard let self else { return nil }
        factory += 1
        let button = UIButton(type: .system)
        button.setTitle("+", for: .normal)
        button.accessibilityLabel = "性能附件按钮 行\(id)"
        button.accessibilityIdentifier = "performanceButton\(id)-\(attachment.id)"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            buttons += 1
            changed()
        }, for: .touchUpInside)
        // 累计整数保留，死亡 weak 包装及时移除，避免诊断本身随滚动增长。
        records.removeAll { $0.view == nil }
        records.append(WeakView(button))
        changed()
        return button
    }, onUnmount: { [weak self] _, _ in
        self?.unmount += 1
        self?.changed()
    })

    init(id: Int) {
        self.id = id
    }

    func receiveAction() {
        actions += 1
        changed()
    }

    private func changed() {
        onChange?()
    }
}

@MainActor
private final class PerformanceCell: UITableViewCell {
    static let reuseID = "PerformanceCell"
    private let glyphLabel = LYGlyphTextLabel(frame: .zero)
    private let statusLabel = UILabel()
    private weak var state: PerformanceRowState?
    private var subscription: AnyCancellable?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        glyphLabel.configuration = .init(numberOfLines: 3)
        glyphLabel.preferredMaxLayoutWidth = 320
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glyphLabel)
        contentView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            glyphLabel.widthAnchor.constraint(equalToConstant: 320),
            glyphLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            glyphLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: glyphLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: glyphLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: glyphLabel.bottomAnchor, constant: 4),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clear()
    }

    func endDisplaying() {
        subscription = nil
        glyphLabel.onAction = nil
        glyphLabel.viewProvider = nil
        // UITableView 会在 willDisplay 前测量返回的 cell，保留不可变输入供自适应高度使用。
    }

    func clear() {
        endDisplaying()
        state = nil
        glyphLabel.document = nil
        statusLabel.text = nil
        statusLabel.accessibilityIdentifier = nil
    }

    func bind(document: LYGlyphTextDocument, state: PerformanceRowState) {
        if self.state !== state { clear() }
        self.state = state
        accessibilityIdentifier = "performanceRow\(state.id)"
        statusLabel.accessibilityIdentifier = "performanceRowStatus\(state.id)"
        glyphLabel.onAction = { [weak state] _ in state?.receiveAction() }
        // 每个 cell 独立订阅；离屏临时测量 cell 不会覆盖可见 cell 的状态观察。
        let rowID = state.id
        subscription = state.$actions.combineLatest(state.$buttons).sink { [weak self] actions, buttons in
            self?.statusLabel.text = "row=\(rowID);action=\(actions);button=\(buttons)"
        }
        glyphLabel.viewProvider = state.provider
        glyphLabel.document = document
    }
}
