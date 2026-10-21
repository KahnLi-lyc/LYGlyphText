import Combine
import LYGlyphText
import UIKit

@MainActor
enum HostMatrixContent: Int, CaseIterable {
    case shortText
    case longText
    case smallImage
    case largeImage
    case smallView
    case largeView
    case action
}

@MainActor
struct HostMatrixRow: Identifiable {
    let id: Int
    let documents: [HostMatrixContent: LYGlyphTextDocument]
}

@MainActor
enum HostMatrixCallback: String, CaseIterable {
    case a = "A"
    case b = "B"
}

@MainActor
final class HostMatrixRowState: ObservableObject {
    let rowID: Int
    @Published private(set) var actionCount = 0
    @Published private(set) var buttonCount = 0
    @Published private(set) var callback = HostMatrixCallback.a
    @Published private(set) var lastHandledCallback: HostMatrixCallback?
    @Published private(set) var lastActionID: String?
    lazy var provider: LYGlyphTextAttachmentViewProvider = makeProvider()

    init(rowID: Int) {
        self.rowID = rowID
    }

    func receive(_ event: LYGlyphTextActionEvent) {
        lastHandledCallback = callback
        lastActionID = event.actionID
        actionCount += 1
    }

    func selectCallback(_ callback: HostMatrixCallback) {
        self.callback = callback
    }

    func resetForReuse() {
        actionCount = 0
        buttonCount = 0
        callback = .a
        lastHandledCallback = nil
        lastActionID = nil
    }

    private func makeProvider() -> LYGlyphTextAttachmentViewProvider {
        LYGlyphTextAttachmentViewProvider { [weak self] attachment in
            guard let self else { return nil }
            switch attachment.viewID {
            case "button":
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = "hostRowAttachmentButton\(rowID)"
                button.setTitle("\(rowID) · \(buttonCount)", for: .normal)
                button.addAction(UIAction { [weak self, weak button] _ in
                    guard let self else { return }
                    buttonCount += 1
                    button?.setTitle("\(rowID) · \(buttonCount)", for: .normal)
                }, for: .touchUpInside)
                return button
            case "badge":
                let label = UILabel()
                label.text = "R\(rowID)"
                label.textAlignment = .center
                label.backgroundColor = .systemYellow
                return label
            default:
                return nil
            }
        }
    }
}

@MainActor
final class HostMatrixSamples {
    let rows: [HostMatrixRow]

    init() throws {
        let image = DemoSamples.makeDirectionImage()
        rows = try (0 ..< 40).map { rowID in
            try HostMatrixRow(id: rowID, documents: Self.makeDocuments(rowID: rowID, image: image))
        }
    }

    private static func makeDocuments(rowID: Int, image: UIImage) throws
        -> [HostMatrixContent: LYGlyphTextDocument]
    {
        let body: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18),
            .foregroundColor: UIColor.label
        ]
        let shortText = NSAttributedString(string: "第 \(rowID) 行 · 短文", attributes: body)
        let longText = NSAttributedString(
            string: "第 \(rowID) 行 · 中英文与 emoji 👨‍👩‍👧‍👦 混排。列表宽度变化时，文字按实际内容宽度换行并自动撑高。\n第二段验证复用后的当前文档。",
            attributes: body
        )
        let imageSource = NSAttributedString(string: "图片 \u{FFFC} · 第 \(rowID) 行", attributes: body)
        let viewSource = NSAttributedString(string: "视图 \u{FFFC} · 第 \(rowID) 行", attributes: body)
        let actionSource = NSMutableAttributedString(string: "第 \(rowID) 行 · ", attributes: body)
        let actionLocation = actionSource.length
        actionSource.append(NSAttributedString(
            string: "执行动作",
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.systemIndigo
            ]
        ))

        return try [
            .shortText: LYGlyphTextDocument(attributedText: shortText),
            .longText: LYGlyphTextDocument(attributedText: longText),
            .smallImage: LYGlyphTextDocument(
                attributedText: imageSource,
                attachments: [3: .init(id: "image-small-\(rowID)", image: image, size: CGSize(width: 20, height: 20))]
            ),
            .largeImage: LYGlyphTextDocument(
                attributedText: imageSource,
                attachments: [3: .init(id: "image-large-\(rowID)", image: image, size: CGSize(width: 48, height: 64))]
            ),
            .smallView: LYGlyphTextDocument(
                attributedText: viewSource,
                viewAttachments: [3: .init(
                    id: "view-small-\(rowID)", viewID: "button", size: CGSize(width: 44, height: 24),
                    isInteractive: true
                )]
            ),
            .largeView: LYGlyphTextDocument(
                attributedText: viewSource,
                viewAttachments: [3: .init(
                    id: "view-large-\(rowID)", viewID: "button", size: CGSize(width: 96, height: 52),
                    isInteractive: true
                )]
            ),
            .action: LYGlyphTextDocument(
                attributedText: actionSource,
                actions: [.init(
                    actionID: "host-row-\(rowID)",
                    range: NSRange(location: actionLocation, length: actionSource.length - actionLocation)
                )]
            )
        ]
    }
}
