import UIKit

extension LYGlyphTextLabel {
    /// 是否应把该位置的单击交给 `onTap`：动作、可交互 token、交互附件与已有选区优先。
    func shouldSendTap(at point: CGPoint, touchedView: UIView?) -> Bool {
        guard onTap != nil, !isTearingDown, window != nil, bounds.contains(point), selectedRange == nil,
              !isInteractiveAttachmentTarget(touchedView), !isActionTarget(at: point) else { return false }
        return true
    }

    func updateTapRecognizer() {
        if onTap != nil, labelTapRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:)))
            tap.delegate = selectionGestureDelegate
            addGestureRecognizer(tap)
            labelTapRecognizer = tap
        } else if onTap == nil, let tap = labelTapRecognizer {
            removeGestureRecognizer(tap)
            labelTapRecognizer = nil
        }
        // 长按选择需要先失败，单击才成立；两者都存在时建立依赖。
        if let tap = labelTapRecognizer, let press = selectionLongPress {
            tap.require(toFail: press)
        }
    }

    @objc private func labelTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard recognizer.state == .ended, shouldSendTap(at: point, touchedView: nil), let onTap else { return }
        onTap(point)
    }
}
