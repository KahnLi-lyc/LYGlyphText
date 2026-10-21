import UIKit

/// 展示层消费的动作几何；不保存闭包或触摸状态。
@MainActor
struct ActionGeometry {
    @MainActor
    struct Entry {
        let actionIndex: Int
        let action: LYGlyphTextAction
        let rects: [CGRect]
        var isTruncationToken = false

        func event(kind: LYGlyphTextActionEvent.Kind) -> LYGlyphTextActionEvent {
            .init(
                actionID: action.actionID, range: action.range, visibleRects: rects, kind: kind,
                isTruncationToken: isTruncationToken
            )
        }
    }

    let entries: [Entry]

    init(layout: LYGlyphTextLayout, bounds: CGRect, configuration: LYGlyphTextConfiguration) {
        guard let display = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        else {
            entries = []
            return
        }
        func visible(_ rects: [CGRect]) -> [CGRect] {
            rects.compactMap { rect -> CGRect? in
                guard let translated = display.displayRect(rect) else { return nil }
                let clipped = translated.intersection(bounds).intersection(display.contentClip)
                guard !clipped.isNull, !clipped.isEmpty,
                      [clipped.minX, clipped.maxX, clipped.minY, clipped.maxY].allSatisfy(\.isFinite)
                else { return nil }
                return clipped
            }
        }
        var entries: [Entry] = layout.actionIndex.compactMap { entry in
            let rects = visible(entry.rects)
            guard !rects.isEmpty else { return nil }
            return .init(actionIndex: entry.actionIndex, action: entry.action, rects: rects)
        }
        // token 没有原文位置，事件范围固定为 NSNotFound；序号排在全部文档动作之后。
        if let index = layout.truncationTokenActionIndex, let token = layout.truncationToken,
           let id = token.actionID
        {
            let rects = visible(token.rects)
            if !rects.isEmpty {
                entries.append(.init(
                    actionIndex: index,
                    action: LYGlyphTextAction(actionID: id, range: NSRange(location: NSNotFound, length: 0)),
                    rects: rects,
                    isTruncationToken: true
                ))
            }
        }
        self.entries = entries
    }

    func hit(at point: CGPoint) -> Entry? {
        entries.first { entry in
            entry.rects.contains { rect in
                point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY
            }
        }
    }
}
