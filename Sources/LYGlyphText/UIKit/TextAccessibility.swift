import UIKit

/// 展示事务的身份；元素只保存数字，不保活文档、工厂或业务回调。
struct AccessibilityRevision: Equatable {
    let document: UInt64
    let geometry: UInt64
    let attachment: UInt64
}

/// 从最终源 cell 构造逻辑顺序语义，不重新 shaping，也不访问附件工厂。
@MainActor
struct TextAccessibility {
    struct Entry {
        let label: String
        let rects: [CGRect]
        let actionIndex: Int?
    }

    enum Item {
        case text(Entry)
        case native(UIView)
    }

    let items: [Item]

    init(
        layout: LYGlyphTextLayout,
        document: LYGlyphTextDocument,
        bounds: CGRect,
        configuration: LYGlyphTextConfiguration,
        nativeViews: [String: UIView]
    ) {
        guard let source = layout.sourceGeometry,
              let display = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        else {
            items = []
            return
        }
        let string = document.string as NSString
        let cells = Dictionary(grouping: source.cells, by: \.range)
        let actions = document.actions.enumerated().sorted { $0.element.range.location < $1.element.range.location }
        var result: [Item] = []
        var pendingLabel = ""
        var pendingRects: [CGRect] = []
        var pendingActionIndex: Int?
        var previousEnd: Int?
        func flush() {
            if !pendingLabel.isEmpty {
                result.append(.text(.init(label: pendingLabel, rects: pendingRects, actionIndex: pendingActionIndex)))
            }
            pendingLabel = ""
            pendingRects = []
            pendingActionIndex = nil
            previousEnd = nil
        }
        for range in cells.keys.sorted(by: { $0.location < $1.location }) {
            let rects = cells[range, default: []].flatMap(\.pieces).compactMap { piece -> CGRect? in
                guard let rect = display.displayRect(piece.rect) else { return nil }
                let clipped = rect.intersection(bounds).intersection(display.contentClip)
                return !clipped.isNull && clipped.width > 0 && clipped.height > 0 ? clipped : nil
            }
            guard !rects.isEmpty else { continue }
            var lower = 0
            var upper = actions.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if NSMaxRange(actions[middle].element.range) <= range.location { lower = middle + 1 }
                else { upper = middle }
            }
            let actionIndex: Int? = if lower < actions.count,
                                       actions[lower].element.range.location <= range.location,
                                       NSMaxRange(range) <= NSMaxRange(actions[lower].element.range)
            {
                actions[lower].offset
            } else { nil }
            let image = document.attachments[range.location]
            let view = document.viewAttachments[range.location]
            if image != nil || view != nil {
                flush()
                if let view, view.isInteractive, let native = nativeViews[view.id] {
                    result.append(.native(native))
                } else if let alt = image?.alternativeText ?? view?.alternativeText,
                          !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    result.append(.text(.init(label: alt, rects: rects, actionIndex: actionIndex)))
                }
                continue
            }
            var separator = ""
            var canAppend = pendingActionIndex == actionIndex
            if let end = previousEnd, end < range.location {
                let gap = string.substring(with: NSRange(location: end, length: range.location - end))
                if gap.unicodeScalars.allSatisfy({ CharacterSet.newlines.contains($0) }) { separator = " " }
                else { canAppend = false }
            }
            if !canAppend {
                flush()
                separator = ""
            }
            pendingLabel.append(separator)
            pendingLabel.append(string.substring(with: range))
            pendingRects.append(contentsOf: rects)
            pendingActionIndex = actionIndex
            previousEnd = NSMaxRange(range)
        }
        flush()
        items = result
    }
}

/// UIKit 的容器引用与显式 owner 都是弱引用；坐标在每次查询时转换，跟随祖先滚动。
@MainActor
final class TextAccessibilityElement: UIAccessibilityElement {
    private weak var owner: LYGlyphTextLabel?
    let revision: AccessibilityRevision
    let entry: TextAccessibility.Entry

    init(owner: LYGlyphTextLabel, revision: AccessibilityRevision, entry: TextAccessibility.Entry) {
        self.owner = owner
        self.revision = revision
        self.entry = entry
        super.init(accessibilityContainer: owner)
        accessibilityLabel = entry.label
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get {
            owner?.canActivateAccessibilityElement(self) == true ? .button : .staticText
        }
        set {}
    }

    /// 使用 UIWindow 专用的屏幕转换；显式 nil 类型避免落入 UIView 的重载。
    private var screenTransform: CGAffineTransform? {
        guard let owner, owner.isCurrentAccessibilityElement(self), let window = owner.window else { return nil }
        func convert(_ point: CGPoint) -> CGPoint {
            window.convert(owner.convert(point, to: window), to: nil as UIWindow?)
        }
        let origin = convert(.zero)
        let x = convert(CGPoint(x: 1, y: 0))
        let y = convert(CGPoint(x: 0, y: 1))
        return CGAffineTransform(
            a: x.x - origin.x,
            b: x.y - origin.y,
            c: y.x - origin.x,
            d: y.y - origin.y,
            tx: origin.x,
            ty: origin.y
        )
    }

    override var accessibilityFrame: CGRect {
        get {
            guard let transform = screenTransform else { return .zero }
            return entry.rects.reduce(CGRect.null) { $0.union($1.applying(transform)) }
        }
        set {}
    }

    override var accessibilityPath: UIBezierPath? {
        get {
            guard let transform = screenTransform else { return nil }
            let path = UIBezierPath()
            for rect in entry.rects {
                path.append(UIBezierPath(rect: rect))
            }
            path.apply(transform)
            return path
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        owner?.activateAccessibilityElement(self) ?? false
    }
}
