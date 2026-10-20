import LYGlyphText
import UIKit

/// 列表宿主负责自己的滚动视口；prepareForReuse 先清空再绑定新行。
@MainActor
final class ReuseDemoController: UITableViewController {
    private let documents: [LYGlyphTextDocument]

    init(documents: [LYGlyphTextDocument]) {
        self.documents = documents
        super.init(style: .plain)
        title = "列表复用"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(documents:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(ReuseDemoCell.self, forCellReuseIdentifier: "attachment")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.accessibilityIdentifier = "attachmentList"
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        documents.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "attachment", for: indexPath)
        if let cell = cell as? ReuseDemoCell { cell.bind(document: documents[indexPath.row], row: indexPath.row) }
        return cell
    }
}

@MainActor
final class ReuseDemoCell: UITableViewCell {
    let glyphLabel = LYGlyphTextLabel(frame: .zero)
    private var tapCount = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glyphLabel)
        NSLayoutConstraint.activate([
            glyphLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            glyphLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            glyphLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            glyphLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(style:reuseIdentifier:)")
    }

    /// 列表传入的实际 cell 宽度决定富文本高度，避免复用时拿旧 bounds 估算。
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        glyphLabel.preferredMaxLayoutWidth = max(0, targetSize.width - 40)
        return super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        glyphLabel.document = nil
        glyphLabel.viewProvider = nil
        tapCount = 0
    }

    func bind(document: LYGlyphTextDocument, row: Int) {
        glyphLabel.document = nil
        glyphLabel.viewProvider = nil
        tapCount = 0
        accessibilityIdentifier = "reuseRow\(row)"
        glyphLabel.document = document
        glyphLabel.viewProvider = .init { [weak self] _ in
            let button = UIButton(type: .system)
            button.setTitle("行 \(row) · 0", for: .normal)
            button.accessibilityIdentifier = "reuseButton\(row)"
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self else { return }
                tapCount += 1
                button?.setTitle("行 \(row) · \(tapCount)", for: .normal)
            }, for: .touchUpInside)
            return button
        }
    }
}
