import LYGlyphText
import SwiftUI
import UIKit

@MainActor
enum ActionCallbackMode: Int, CaseIterable {
    case a, b, none

    var title: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .none: "无"
        }
    }

    var statusValue: String {
        self == .none ? "nil" : title
    }
}

@MainActor
final class ActionDemoState: ObservableObject {
    @Published private(set) var eventCount = 0
    @Published private(set) var buttonCount = 0
    @Published private(set) var lastCallback = "-"
    @Published private(set) var lastKind = "-"
    @Published private(set) var lastID = "-"
    @Published private(set) var lastRange = "-"
    var onChange: (() -> Void)?

    lazy var provider = LYGlyphTextAttachmentViewProvider { [weak self] descriptor in
        guard let self else { return nil }
        switch descriptor.viewID {
        case "action-badge":
            let badge = UILabel()
            badge.text = "徽章"
            badge.textAlignment = .center
            badge.font = .systemFont(ofSize: 12, weight: .bold)
            badge.textColor = .systemPurple
            badge.backgroundColor = .systemPurple.withAlphaComponent(0.16)
            badge.layer.cornerRadius = 5
            badge.clipsToBounds = true
            badge.accessibilityIdentifier = "actionDecorativeView"
            return badge
        case "action-button":
            let button = UIButton(type: .system)
            button.setTitle("按钮 +1", for: .normal)
            button.backgroundColor = .systemTeal.withAlphaComponent(0.16)
            button.layer.cornerRadius = 6
            button.accessibilityIdentifier = "actionAttachmentButton"
            button.addAction(UIAction { [weak self] _ in
                self?.buttonCount += 1
                self?.onChange?()
            }, for: .touchUpInside)
            return button
        default:
            return nil
        }
    }

    var status: String {
        "events=\(eventCount) callback=\(lastCallback) kind=\(lastKind) id=\(lastID) range=\(lastRange)"
    }

    func receive(_ event: LYGlyphTextActionEvent, callback: ActionCallbackMode) {
        eventCount += 1
        lastCallback = callback.statusValue
        lastKind = event.kind == .tap ? "tap" : "longPress"
        lastID = event.actionID
        lastRange = "\(event.range.location):\(event.range.length)"
        onChange?()
    }
}
