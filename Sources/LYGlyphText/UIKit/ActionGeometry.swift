import UIKit

/// 展示层消费的动作几何；不保存闭包或触摸状态。
@MainActor
struct ActionGeometry {
    @MainActor
    struct Entry {
        let actionIndex: Int
        let action: LYGlyphTextAction
        let rects: [CGRect]

        func event(kind: LYGlyphTextActionEvent.Kind) -> LYGlyphTextActionEvent {
            .init(actionID: action.actionID, range: action.range, visibleRects: rects, kind: kind)
        }
    }

    let entries: [Entry]

    init(layout: LYGlyphTextLayout, bounds: CGRect, configuration: LYGlyphTextConfiguration) {
        guard let display = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        else {
            entries = []
            return
        }
        entries = layout.actionIndex.compactMap { entry in
            let rects = entry.rects.compactMap { rect -> CGRect? in
                guard let translated = display.displayRect(rect) else { return nil }
                let clipped = translated.intersection(bounds).intersection(display.contentClip)
                guard !clipped.isNull, !clipped.isEmpty,
                      [clipped.minX, clipped.maxX, clipped.minY, clipped.maxY].allSatisfy(\.isFinite)
                else { return nil }
                return clipped
            }
            guard !rects.isEmpty else { return nil }
            return .init(actionIndex: entry.actionIndex, action: entry.action, rects: rects)
        }
    }

    func hit(at point: CGPoint) -> Entry? {
        entries.first { entry in
            entry.rects.contains { rect in
                point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY
            }
        }
    }
}
