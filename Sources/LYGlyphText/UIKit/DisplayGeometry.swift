import UIKit

/// 已含 inset 的布局只平移一次；内容裁切区始终留在宿主 bounds 内。
struct DisplayGeometry {
    let translation: CGPoint
    let contentClip: CGRect

    init?(bounds: CGRect, layoutSize: CGSize, configuration: LYGlyphTextConfiguration) {
        let insets = configuration.insets
        guard [bounds.minX, bounds.minY, bounds.width, bounds.height, layoutSize.height]
            .allSatisfy({ LayoutNumber.isSafe($0, times: 4) }) else { return nil }
        let extra = max(0, bounds.height - layoutSize.height)
        let offset: CGFloat = switch configuration.verticalAlignment {
        case .top: 0
        case .center: extra / 2
        case .bottom: extra
        }
        guard let y = LayoutNumber.add(bounds.minY, offset),
              let clipX = LayoutNumber.add(bounds.minX, insets.left),
              let clipY = LayoutNumber.add(bounds.minY, insets.top) else { return nil }
        translation = CGPoint(x: bounds.minX, y: y)
        contentClip = CGRect(
            x: clipX, y: clipY,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    func displayRect(_ rect: CGRect) -> CGRect? {
        guard let x = LayoutNumber.add(rect.minX, translation.x),
              let y = LayoutNumber.add(rect.minY, translation.y),
              LayoutNumber.add(x, rect.width) != nil,
              LayoutNumber.add(y, rect.height) != nil else { return nil }
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}
