import CoreText
import UIKit

/// Core Text 使用 Float 中间度量；先检查运算包络，再创建任何系统排版对象。
enum LayoutNumber {
    static func isSafe(_ value: CGFloat, times factor: CGFloat = 1) -> Bool {
        guard value.isFinite, factor.isFinite, Float(value).isFinite, Float(factor).isFinite else { return false }
        return (Float(value) * Float(factor)).isFinite
    }

    static func isMetricSafe(_ value: CGFloat, factor: CGFloat, naturalHeight: CGFloat) -> Bool {
        guard isSafe(value, times: factor), naturalHeight > 0, isSafe(naturalHeight) else { return false }
        // 已实测 1e20 的有限 Float 坐标会丢失整行高度，造成帧漏行。
        // 最坏坐标仍须能分辨自然字形高度；这是浮点精度包络，不是屏幕尺寸限制。
        let coordinate = abs(Float(value) * Float(factor))
        return coordinate.ulp <= Float(naturalHeight)
    }

    static func metric(_ value: CGFloat, factor: CGFloat, naturalHeight: CGFloat, discard: Bool) -> CGFloat {
        !discard && isMetricSafe(value, factor: max(2, factor), naturalHeight: naturalHeight) ? value : 0
    }

    static func add(_ first: CGFloat, _ second: CGFloat) -> CGFloat? {
        guard isSafe(first), isSafe(second), isSafe(first + second) else { return nil }
        return first + second
    }

    static func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard value.isFinite, scale.isFinite, scale > 0, isSafe(value, times: scale) else { return 0 }
        let result = ceil(value * scale) / scale
        return isSafe(result) ? result : 0
    }
}

/// 值指针仅在 CTParagraphStyleCreate 的同步调用内有效；截断和普通排版共用同一映射。
enum ResolvedParagraphStyle {
    static func create(
        _ style: ParagraphStyle, wrapping: LYGlyphTextConfiguration.Wrapping,
        length: Int, naturalHeight: CGFloat, discardMetrics: Bool = false
    ) -> CTParagraphStyle {
        var alignment: CTTextAlignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        default: .natural
        }
        var direction: CTWritingDirection = switch style.writingDirection {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        default: .natural
        }
        var mode: CTLineBreakMode = wrapping == .character ? .byCharWrapping : .byWordWrapping
        let factor = max(CGFloat(length + 1), naturalHeight, 2)
        let metrics: [(CTParagraphStyleSpecifier, CGFloat)] = [
            (.lineSpacingAdjustment, style.lineSpacing), (.paragraphSpacing, style.paragraphSpacing),
            (.paragraphSpacingBefore, style.paragraphSpacingBefore),
            (.firstLineHeadIndent, style.firstLineHeadIndent), (.headIndent, style.headIndent),
            (.tailIndent, style.tailIndent), (.minimumLineHeight, style.minimumLineHeight),
            (.maximumLineHeight, style.maximumLineHeight), (.lineHeightMultiple, style.lineHeightMultiple)
        ]
        let values = metrics.map { spec, value in
            let multiplier = spec == .lineHeightMultiple ? factor * naturalHeight : factor
            return LayoutNumber.metric(value, factor: multiplier, naturalHeight: naturalHeight, discard: discardMetrics)
        }
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &direction) { directionPointer in
                withUnsafePointer(to: &mode) { modePointer in
                    values.withUnsafeBufferPointer { buffer in
                        var settings = [
                            CTParagraphStyleSetting(
                                spec: .alignment,
                                valueSize: MemoryLayout<CTTextAlignment>.size,
                                value: alignmentPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .baseWritingDirection,
                                valueSize: MemoryLayout<CTWritingDirection>.size,
                                value: directionPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .lineBreakMode,
                                valueSize: MemoryLayout<CTLineBreakMode>.size,
                                value: modePointer
                            )
                        ]
                        if let base = buffer.baseAddress {
                            settings += metrics.indices.map {
                                CTParagraphStyleSetting(
                                    spec: metrics[$0].0,
                                    valueSize: MemoryLayout<CGFloat>.size,
                                    value: base.advanced(by: $0)
                                )
                            }
                        }
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
    }

    /// 保留原 style 的全部字段，只替换本次截断需要固定的方向或探测用缩进。
    static func copy(
        _ original: CTParagraphStyle, direction: CTWritingDirection? = nil, probe: Bool = false
    ) -> CTParagraphStyle {
        let specs: [CTParagraphStyleSpecifier] = [
            .lineSpacingAdjustment, .paragraphSpacing, .paragraphSpacingBefore, .firstLineHeadIndent,
            .headIndent, .tailIndent, .minimumLineHeight, .maximumLineHeight, .lineHeightMultiple
        ]
        var alignment = CTTextAlignment.natural
        var resolvedDirection = CTWritingDirection.natural
        var mode = CTLineBreakMode.byWordWrapping
        CTParagraphStyleGetValueForSpecifier(original, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment)
        CTParagraphStyleGetValueForSpecifier(
            original,
            .baseWritingDirection,
            MemoryLayout<CTWritingDirection>.size,
            &resolvedDirection
        )
        CTParagraphStyleGetValueForSpecifier(original, .lineBreakMode, MemoryLayout<CTLineBreakMode>.size, &mode)
        if let direction { resolvedDirection = direction }
        if probe { alignment = .natural
            resolvedDirection = .natural
        }
        let values = specs.map { spec -> CGFloat in
            var value: CGFloat = 0
            CTParagraphStyleGetValueForSpecifier(original, spec, MemoryLayout<CGFloat>.size, &value)
            return probe ? 0 : value
        }
        return withUnsafePointer(to: &alignment) { a in
            withUnsafePointer(to: &resolvedDirection) { d in
                withUnsafePointer(to: &mode) { m in
                    values.withUnsafeBufferPointer { buffer in
                        var settings = [
                            CTParagraphStyleSetting(
                                spec: .alignment,
                                valueSize: MemoryLayout<CTTextAlignment>.size,
                                value: a
                            ),
                            CTParagraphStyleSetting(
                                spec: .baseWritingDirection,
                                valueSize: MemoryLayout<CTWritingDirection>.size,
                                value: d
                            ),
                            CTParagraphStyleSetting(
                                spec: .lineBreakMode,
                                valueSize: MemoryLayout<CTLineBreakMode>.size,
                                value: m
                            )
                        ]
                        if let base = buffer.baseAddress {
                            settings += specs.indices.map {
                                CTParagraphStyleSetting(
                                    spec: specs[$0],
                                    valueSize: MemoryLayout<CGFloat>.size,
                                    value: base.advanced(by: $0)
                                )
                            }
                        }
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
    }
}
