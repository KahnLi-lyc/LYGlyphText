import LYGlyphText
import SwiftUI
import UIKit

/// 工厂身份跨重绘保持稳定；只有真实按钮动作更新 SwiftUI 可观察状态。
@MainActor
final class DemoAttachmentState: ObservableObject {
    @Published private(set) var count = 0
    var onCountChanged: (() -> Void)?

    lazy var provider = makeProvider()

    func makeProvider() -> LYGlyphTextAttachmentViewProvider {
        LYGlyphTextAttachmentViewProvider { [weak self] descriptor in
            guard let self else { return nil }
            switch descriptor.viewID {
            case "image":
                let image = UIImageView(image: UIImage(systemName: "star.fill"))
                image.tintColor = .systemOrange
                image.contentMode = .scaleAspectFit
                image.accessibilityIdentifier = "attachmentImage"
                return image
            case "button":
                let button = UIButton(type: .system)
                button.setTitle("点击 +1", for: .normal)
                button.backgroundColor = .systemTeal.withAlphaComponent(0.15)
                button.layer.cornerRadius = 6
                button.accessibilityIdentifier = "attachmentButton"
                button.addAction(UIAction { [weak self] _ in
                    self?.count += 1
                    self?.onCountChanged?()
                }, for: .touchUpInside)
                return button
            case "badge":
                let badge = UILabel()
                badge.text = "UIView"
                badge.textAlignment = .center
                badge.font = .systemFont(ofSize: 12, weight: .bold)
                badge.textColor = .systemPurple
                badge.backgroundColor = .systemPurple.withAlphaComponent(0.15)
                badge.accessibilityIdentifier = "attachmentBadge"
                return badge
            default:
                return nil
            }
        }
    }
}
