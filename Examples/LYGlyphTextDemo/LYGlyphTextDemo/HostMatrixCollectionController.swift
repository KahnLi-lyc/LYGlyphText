import Combine
import UIKit
#if DEBUG
    @testable import LYGlyphText
#else
    import LYGlyphText
#endif

@MainActor
final class HostMatrixCollectionController: UICollectionViewController {
    let samples: HostMatrixSamples
    private(set) var content: HostMatrixContent
    private(set) var callback: HostMatrixCallback
    private(set) var rowStates: [Int: HostMatrixRowState] = [:]
    private(set) var layoutInvalidationCount = 0
    private var previousLayoutWidth: CGFloat?

    init(
        samples: HostMatrixSamples,
        content: HostMatrixContent = .shortText,
        callback: HostMatrixCallback = .a
    ) {
        self.samples = samples
        self.content = content
        self.callback = callback
        super.init(collectionViewLayout: Self.makeLayout())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:content:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(
            HostMatrixCollectionCell.self,
            forCellWithReuseIdentifier: HostMatrixCollectionCell.reuseID
        )
        collectionView.dataSource = self
        collectionView.delegate = self
    }

    override func viewWillLayoutSubviews() {
        let boundsWidth = collectionView.bounds.width
        if boundsWidth.isFinite, boundsWidth != previousLayoutWidth {
            previousLayoutWidth = boundsWidth
            layoutInvalidationCount &+= 1
            collectionView.collectionViewLayout.invalidateLayout()
        }
        super.viewWillLayoutSubviews()
    }

    func setContent(_ content: HostMatrixContent) {
        self.content = content
        collectionView.reloadData()
    }

    func state(for rowID: Int) -> HostMatrixRowState {
        if let state = rowStates[rowID] { return state }
        let state = HostMatrixRowState(rowID: rowID)
        state.selectCallback(callback)
        rowStates[rowID] = state
        return state
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(80)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        return UICollectionViewCompositionalLayout(section: section)
    }

    override func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        samples.rows.count
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HostMatrixCollectionCell.reuseID,
            for: indexPath
        )
        guard let cell = cell as? HostMatrixCollectionCell else { return cell }
        let row = samples.rows[indexPath.item]
        cell.bind(row: row, content: content, state: state(for: row.id))
        return cell
    }
}

@MainActor
final class HostMatrixCollectionCell: UICollectionViewCell {
    static let reuseID = "HostMatrixCollectionCell"
    static let horizontalInset: CGFloat = 16
    let glyphLabel = LYGlyphTextLabel(frame: .zero)
    let statusLabel = UILabel()
    private(set) var rowID: Int?
    private(set) var eventCount = 0
    private var subscriptions: Set<AnyCancellable> = []
    #if DEBUG
        private let diagnostic = ActionDiagnosticOverlay(frame: .zero)
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
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
            contentView.addSubview(diagnostic)
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
        fatalError("请使用 init(frame:)")
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

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else {
            return layoutAttributes
        }
        let width = max(0, layoutAttributes.size.width)
        synchronizeMeasurementWidth(width)
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let fitted = contentView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        attributes.size.width = width
        attributes.size.height = ceil(max(0, fitted.height) * scale) / scale
        return attributes
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
        statusLabel.accessibilityIdentifier = "hostCollectionRowStatus\(row.id)"
        state.$actionCount.combineLatest(state.$buttonCount, state.$callback)
            .sink { [weak self] action, button, callback in
                guard let self else { return }
                statusLabel.text = "row=\(row.id);event=\(action);button=\(button);callback=\(callback.rawValue);" +
                    "pressed=\(pressedValue)"
            }.store(in: &subscriptions)
        #if DEBUG
            diagnostic.sourceDocument = row.documents[content]
            diagnostic.accessibilityIdentifier = "hostCollectionAction\(row.id)"
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
