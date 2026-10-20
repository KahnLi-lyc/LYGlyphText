#if DEBUG
    import CoreText
    @testable import LYGlyphText
    import SwiftUI
    import UIKit

    @MainActor
    final class ActionDiagnosticOverlay: UIView {
        weak var sourceLabel: LYGlyphTextLabel?
        var sourceDocument: LYGlyphTextDocument?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            isUserInteractionEnabled = false
            accessibilityIdentifier = "actionPreview"
            backgroundColor = .clear
        }

        override var accessibilityValue: String? {
            get {
                guard let label = sourceLabel ?? findLabel(in: window), label.bounds.width > 0,
                      label.bounds.height > 0
                else { return "" }
                sourceLabel = label
                return ActionDemoDiagnostics.value(for: label)
            }
            set {
                super.accessibilityValue = newValue
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("请使用 init(frame:)")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refreshAfterLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            refresh()
        }

        func refreshAfterLayout() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                sourceLabel = sourceLabel ?? findLabel(in: window)
                refresh()
            }
        }

        func refresh() {
            guard let label = sourceLabel ?? findLabel(in: window), label.bounds.width > 0,
                  label.bounds.height > 0
            else {
                accessibilityValue = ""
                return
            }
            sourceLabel = label
            accessibilityValue = ActionDemoDiagnostics.value(for: label)
        }

        private func findLabel(in view: UIView?) -> LYGlyphTextLabel? {
            guard let view else { return nil }
            if let label = view as? LYGlyphTextLabel,
               sourceDocument == nil || label.document === sourceDocument { return label }
            for child in view.subviews {
                if let result = findLabel(in: child) { return result }
            }
            return nil
        }
    }

    @MainActor
    struct ActionDiagnosticProbe: UIViewRepresentable {
        let document: LYGlyphTextDocument

        func makeUIView(context _: Context) -> ActionDiagnosticOverlay {
            let view = ActionDiagnosticOverlay(frame: .zero)
            view.sourceDocument = document
            return view
        }

        func updateUIView(_ uiView: ActionDiagnosticOverlay, context _: Context) {
            uiView.sourceDocument = document
            uiView.sourceLabel = nil
            uiView.refreshAfterLayout()
        }
    }

    @MainActor
    private enum ActionDemoDiagnostics {
        static func value(for label: LYGlyphTextLabel) -> String {
            let layout = label.measuredLayout(width: max(0, label.bounds.width))
            guard let display = DisplayGeometry(
                bounds: label.bounds,
                layoutSize: layout.size,
                configuration: label.configuration
            ) else { return "" }
            let geometry = ActionGeometry(layout: layout, bounds: label.bounds, configuration: label.configuration)
            let totals = Dictionary(grouping: geometry.entries, by: \ .action.actionID).mapValues(\.count)
            var occurrences: [String: Int] = [:]
            var points: [String: CGPoint] = [:]

            for entry in geometry.entries {
                let id = entry.action.actionID
                let occurrence = occurrences[id, default: 0]
                occurrences[id] = occurrence + 1
                let base = totals[id] == 1 ? id : "\(id)#\(occurrence)"
                let rects = entry.rects.sorted {
                    if abs($0.minY - $1.minY) > 0.5 { return $0.minY < $1.minY }
                    return $0.minX < $1.minX
                }
                if let first = rects.first {
                    points[base] = screenPoint(first.center, in: label)
                }
                let lineRects = lineUnions(rects)
                if lineRects.count > 1 {
                    for (index, rect) in lineRects.enumerated() {
                        points["\(base).\(index)"] = screenPoint(rect.center, in: label)
                    }
                }
                if ["rtl", "emoji", "fi"].contains(id), let union = rects.union {
                    points["\(base).left"] = screenPoint(
                        CGPoint(x: union.minX + union.width * 0.2, y: union.midY), in: label
                    )
                    points["\(base).right"] = screenPoint(
                        CGPoint(x: union.maxX - union.width * 0.2, y: union.midY), in: label
                    )
                }
            }

            if let plain = plainRect(layout: layout, label: label, display: display) {
                points["plain"] = screenPoint(plain.center, in: label)
            }
            points["inset"] = screenPoint(CGPoint(
                x: label.bounds.minX + max(2, label.configuration.insets.left / 2),
                y: label.bounds.midY
            ), in: label)
            if let cross = geometry.entries.first(where: { $0.action.actionID == "cross" }) {
                let ordered = lineUnions(cross.rects)
                if ordered.count > 1 {
                    let first = ordered[0]
                    let second = ordered[1]
                    points["lineGap"] = screenPoint(
                        CGPoint(x: first.midX, y: (first.maxY + second.minY) / 2), in: label
                    )
                    points["lineEnd"] = screenPoint(CGPoint(
                        x: min(display.contentClip.maxX - 2, first.maxX + 12), y: first.midY
                    ), in: label)
                }
            }
            if let token = truncationTokenRect(layout: layout, display: display) {
                points["token"] = screenPoint(token.center, in: label)
            }
            if label.bounds.height + 0.5 < layout.size.height,
               let visible = geometry.entries.first(where: { $0.action.actionID == "cross" })?.rects.first
            {
                points["clipped.visible"] = screenPoint(visible.center, in: label)
                if let raw = layout.actionIndex.first(where: { $0.action.actionID == "cross" })?.rects.last,
                   let translated = display.displayRect(raw)
                {
                    points["clipped.hidden"] = screenPoint(translated.center, in: label)
                }
            }
            points["alignment"] = screenPoint(CGPoint(
                x: display.contentClip.midX,
                y: display.contentClip.minY + 2
            ), in: label)
            points["pressed"] = CGPoint(x: CGFloat(label.pressedActionIndex ?? -1), y: 0)

            return serialize(points)
        }

        private static func serialize(_ points: [String: CGPoint]) -> String {
            points.keys.sorted().map { key in
                let point = points[key] ?? .zero
                return "\(key)=\(format(point.x)),\(format(point.y))"
            }.joined(separator: ";")
        }

        private static func lineUnions(_ rects: [CGRect]) -> [CGRect] {
            let ordered = rects.sorted {
                if abs($0.midY - $1.midY) > 1 { return $0.midY < $1.midY }
                return $0.minX < $1.minX
            }
            var lines: [CGRect] = []
            for rect in ordered {
                if let last = lines.last, abs(last.midY - rect.midY) <= 1 {
                    lines[lines.count - 1] = last.union(rect)
                } else {
                    lines.append(rect)
                }
            }
            return lines
        }

        private static func plainRect(
            layout: LYGlyphTextLayout,
            label: LYGlyphTextLabel,
            display: DisplayGeometry
        ) -> CGRect? {
            guard let source = layout.sourceGeometry, let document = label.document else { return nil }
            for cell in source.cells where !cell.isWhitespace {
                guard !document.actions.contains(where: { NSIntersectionRange($0.range, cell.range).length > 0 }) else {
                    continue
                }
                for piece in cell.pieces {
                    guard let translated = display.displayRect(piece.rect) else { continue }
                    let clipped = translated.intersection(label.bounds).intersection(display.contentClip)
                    if !clipped.isNull, !clipped.isEmpty { return clipped }
                }
            }
            return nil
        }

        private static func truncationTokenRect(layout: LYGlyphTextLayout, display: DisplayGeometry) -> CGRect? {
            guard let source = layout.sourceGeometry,
                  let group = source.glyphGroups.first(where: { $0.origin == .generatedToken }),
                  layout.lines.indices.contains(group.lineIndex) else { return nil }
            let line = layout.lines[group.lineIndex]
            let runs = CTLineGetGlyphRuns(line.text) as! [CTRun]
            guard runs.indices.contains(group.runIndex) else { return nil }
            let run = runs[group.runIndex]
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { return nil }
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            let members = group.glyphIndices.filter { positions.indices.contains($0) }
            guard !members.isEmpty,
                  let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont?
            else { return nil }
            let minX = members.map { min(positions[$0].x, positions[$0].x + advances[$0].width) }.min() ?? 0
            let maxX = members.map { max(positions[$0].x, positions[$0].x + advances[$0].width) }.max() ?? 0
            let rect = CGRect(
                x: line.baseline.x + minX,
                y: line.baseline.y - CTFontGetAscent(font),
                width: max(0, maxX - minX),
                height: CTFontGetAscent(font) + CTFontGetDescent(font)
            )
            guard let translated = display.displayRect(rect) else { return nil }
            let clipped = translated.intersection(display.contentClip)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }

        private static func screenPoint(_ point: CGPoint, in label: UIView) -> CGPoint {
            label.convert(point, to: nil)
        }

        private static func format(_ value: CGFloat) -> String {
            String(format: "%.2f", Double(value))
        }
    }

    private extension CGRect {
        var center: CGPoint {
            CGPoint(x: midX, y: midY)
        }
    }

    private extension [CGRect] {
        var union: CGRect? {
            guard let first else { return nil }
            return dropFirst().reduce(first) { $0.union($1) }
        }
    }
#endif
