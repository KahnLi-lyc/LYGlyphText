import CoreText
import UIKit

/// 调试叠加层选项，用于排查排版、附件与点击区域；默认空。只在绘制最后描线，不影响测量、命中与无障碍。
public struct LYGlyphTextDebugOptions: OptionSet, Sendable {
    public let rawValue: Int

    /// 创建选项集合。
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 每行的排版框（红色描边）。
    public static let lineFrames = LYGlyphTextDebugOptions(rawValue: 1 << 0)
    /// 每行的基线（蓝色）。
    public static let baselines = LYGlyphTextDebugOptions(rawValue: 1 << 1)
    /// 图片与视图附件的声明框（绿色描边）。
    public static let attachmentFrames = LYGlyphTextDebugOptions(rawValue: 1 << 2)
    /// 动作与可交互截断 token 的可见区域（橙色半透明填充）。
    public static let actionRegions = LYGlyphTextDebugOptions(rawValue: 1 << 3)
    /// 全部选项。
    public static let all: LYGlyphTextDebugOptions = [.lineFrames, .baselines, .attachmentFrames, .actionRegions]
}

extension LYGlyphTextLayout {
    /// 在文本容器坐标中绘制调试叠加；颜色固定，不随显示环境变化。
    func drawDebug(_ options: LYGlyphTextDebugOptions, in context: CGContext) {
        guard !options.isEmpty else { return }
        context.saveGState()
        context.setLineWidth(1)
        if options.contains(.actionRegions) {
            context.setFillColor(UIColor.orange.withAlphaComponent(0.3).cgColor)
            for rect in actionIndex
                .flatMap(\.rects) + (truncationToken?.actionID == nil ? [] : truncationToken?.rects ?? [])
            {
                context.fill(rect)
            }
        }
        for line in lines {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line.text, &ascent, &descent, nil))
            guard width.isFinite, ascent.isFinite, descent.isFinite else { continue }
            if options.contains(.lineFrames) {
                context.setStrokeColor(UIColor.red.withAlphaComponent(0.7).cgColor)
                context.stroke(CGRect(
                    x: line.baseline.x, y: line.baseline.y - ascent, width: max(1, width), height: ascent + descent
                ).insetBy(dx: 0.5, dy: 0.5))
            }
            if options.contains(.baselines) {
                context.setStrokeColor(UIColor.blue.withAlphaComponent(0.7).cgColor)
                context.move(to: CGPoint(x: line.baseline.x, y: line.baseline.y))
                context.addLine(to: CGPoint(x: line.baseline.x + max(1, width), y: line.baseline.y))
                context.strokePath()
            }
        }
        if options.contains(.attachmentFrames) {
            context.setStrokeColor(UIColor.green.withAlphaComponent(0.8).cgColor)
            for rect in attachments.map(\.rect) {
                context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }
            // UIView 附件（含远程图片）盖在绘制内容之上，框描在视图外侧 1pt 才可见。
            for rect in viewAttachments.map(\.rect) {
                context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
            }
        }
        context.restoreGState()
    }
}
