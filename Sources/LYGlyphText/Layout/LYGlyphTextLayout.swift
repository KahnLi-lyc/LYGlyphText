import CoreText
import UIKit

/// 所有基线均为 UIKit 本地坐标；原文范围使用 UTF-16，不包含补齐末尾空行的字符。
@MainActor
struct LYGlyphTextLayout {
    struct Line {
        let text: CTLine
        let baseline: CGPoint
        /// 原文 UTF-16 区间；生成的省略号没有原文索引。
        let visibleSourceRanges: [NSRange]
        /// CTLine 索引到原文索引的偏移；截断行重建后使用局部索引。
        let sourceOffset: Int
        /// 生成的省略号在 CTLine 内的索引，与原文中的省略号字符区分。
        let truncationTokenRange: NSRange?
    }

    struct Attachment {
        let attachment: LYGlyphTextAttachment
        let sourceLocation: Int
        /// 相对于文本容器左上原点的完整图片矩形，裁切由展示层统一完成。
        let rect: CGRect
    }

    struct ViewAttachment {
        let attachment: LYGlyphTextViewAttachment
        let sourceLocation: Int
        /// 相对于文本容器原点的完整声明矩形。
        let rect: CGRect
    }

    let viewAttachments: [ViewAttachment]
    let size: CGSize
    let lines: [Line]
    let attachments: [Attachment]
    let sourceGeometry: SourceGeometry?
    let actionIndex: [ActionSourceEntry]
    let preparedDecorations: TextDecorations.Prepared?
    let preparedDrawing: PressedTextDrawing

    struct ActionSourceEntry {
        let actionIndex: Int
        let action: LYGlyphTextAction
        let rects: [CGRect]
    }

    init(
        size: CGSize, lines: [Line], attachments: [Attachment] = [], viewAttachments: [ViewAttachment] = [],
        decorations: TextDecorations? = nil, traits: UITraitCollection = .current, source: String? = nil,
        actions: [LYGlyphTextAction] = [],
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) {
        self.viewAttachments = viewAttachments
        self.size = size
        self.lines = lines
        self.attachments = attachments
        let geometry = (source ?? decorations?.source).map {
            observe(.sourceSnapshot)
            return SourceGeometry(source: $0, lines: lines, attachments: attachments, viewAttachments: viewAttachments)
        }
        sourceGeometry = geometry
        preparedDecorations = decorations.map {
            $0.prepare(
                fragments: geometry?.fragments(in: NSRange(location: 0, length: $0.source.utf16.count)) ?? [],
                observe: observe
            )
        }
        actionIndex = Self.index(actions: actions, geometry: geometry)
        preparedDrawing = PressedTextDrawing(
            lines: lines,
            geometry: geometry,
            actions: actionIndex,
            decorations: decorations,
            prepared: preparedDecorations,
            traits: traits,
            observe: observe
        )
    }

    private static func index(actions: [LYGlyphTextAction], geometry: SourceGeometry?) -> [ActionSourceEntry] {
        guard let geometry, !actions.isEmpty else { return [] }
        let sorted = actions.enumerated().sorted { $0.element.range.location < $1.element.range.location }
        var rects: [Int: [CGRect]] = [:]
        // 最终源行的逻辑尾部空白始终剔除；生成 token 不成为源 cell，也不改变此判定。
        let lines = Dictionary(grouping: geometry.cells, by: \.lineIndex)
        var trailing = Set<NSRange>()
        for cells in lines.values {
            for cell in cells.reversed() {
                guard cell.isWhitespace else { break }
                trailing.insert(cell.range)
            }
        }
        for cell in geometry.cells where !trailing.contains(cell.range) {
            var lower = 0
            var upper = sorted.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if NSMaxRange(sorted[middle].element.range) <= cell.range.location { lower = middle + 1 }
                else { upper = middle }
            }
            guard lower < sorted.count else { continue }
            let entry = sorted[lower]
            guard NSIntersectionRange(entry.element.range, cell.range).length > 0 else { continue }
            // 一个组合字符跨 run 时保留真实矩形，不以 union 填补视觉间隙。
            rects[entry.offset, default: []].append(contentsOf: cell.pieces.map(\.rect).filter { $0.width > 0 })
        }
        return actions.enumerated().map { .init(
            actionIndex: $0.offset,
            action: $0.element,
            rects: rects[$0.offset] ?? []
        ) }
    }

    /// 观察入口不保存闭包；普通 draw 只消费缓存，因此不产生准备工作事件。
    func draw(
        in context: CGContext, pressedActionIndex: Int? = nil,
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) {
        observe(.drawCachedContent)
        context.saveGState()
        preparedDrawing.drawBackgrounds(in: context, pressed: pressedActionIndex)
        preparedDrawing.drawGlyphs(in: context, pressed: pressedActionIndex)
        preparedDrawing.drawStrokes(in: context, pressed: pressedActionIndex, observe: observe)
        context.restoreGState()
        // UIImage 的 UIKit 绘制路径负责方向与 scale；不直接翻转其 CGImage。
        UIGraphicsPushContext(context)
        for placement in attachments {
            placement.attachment.image.draw(in: placement.rect)
        }
        UIGraphicsPopContext()
    }
}

/// 解析动态字体和颜色后的本次显示输入。仅在 MainActor 使用。
@MainActor
final class ResolvedText {
    let framesetter: CTFramesetter
    let sourceLength: Int
    let idealWidth: CGFloat
    private let glyphPadding: CGFloat
    private let isEmpty: Bool
    private let document: LYGlyphTextDocument?
    private let traits: UITraitCollection
    private let wrapping: LYGlyphTextConfiguration.Wrapping
    private let discardsMetrics: Bool
    private(set) var fallbackCount = 0
    private let attributedText: NSAttributedString
    private let attachments: [Int: LYGlyphTextAttachment]
    private let viewAttachments: [Int: LYGlyphTextViewAttachment]
    private let decorationStyles: [TextDecorations.Style]

    init(
        document: LYGlyphTextDocument?, traits: UITraitCollection,
        wrapping: LYGlyphTextConfiguration.Wrapping = .word, discardMetrics: Bool = false
    ) {
        self.document = document
        self.traits = traits
        self.wrapping = wrapping
        discardsMetrics = discardMetrics
        let string = document?.string ?? ""
        sourceLength = (string as NSString).length
        isEmpty = sourceLength == 0
        attachments = document?.attachments ?? [:]
        viewAttachments = document?.viewAttachments ?? [:]
        let text = NSMutableAttributedString(string: string)
        var decorationStyles: [TextDecorations.Style] = []
        for run in document?.styleRuns ?? [] {
            let proposedFont = run.font ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let font = LayoutNumber.isSafe(proposedFont.lineHeight, times: CGFloat(sourceLength + 1))
                ? proposedFont : UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let color = (run.color ?? .label).resolvedColor(with: traits)
            decorationStyles.append(.init(
                range: run.range, background: run.background?.resolvedColor(with: traits).cgColor,
                underlineStyle: run.underlineStyle,
                underlineColor: (run.underlineColor?.resolvedColor(with: traits) ?? color).cgColor,
                strikethroughStyle: run.strikethroughStyle,
                strikethroughColor: (run.strikethroughColor?.resolvedColor(with: traits) ?? color).cgColor,
                underlineColorIsInherited: run.underlineColor == nil,
                strikethroughColorIsInherited: run.strikethroughColor == nil
            ))
            let factor = max(CGFloat(sourceLength + 1), font.lineHeight, 2)
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): ResolvedParagraphStyle.create(
                    run.paragraph, wrapping: wrapping, length: sourceLength, naturalHeight: font.lineHeight,
                    discardMetrics: discardMetrics
                ),
                NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): LayoutNumber.metric(
                    run.baselineOffset, factor: factor, naturalHeight: font.lineHeight, discard: discardMetrics
                ),
                NSAttributedString.Key(kCTLigatureAttributeName as String): run.ligature,
                NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): TextDecorations
                    .needsUnderlineFallback(run.underlineStyle) ? 0 : run.underlineStyle
            ]
            if !discardMetrics, let kern = run.kern, LayoutNumber.isMetricSafe(
                kern,
                factor: factor,
                naturalHeight: font.lineHeight
            ) {
                attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kern
            }
            if !TextDecorations.needsUnderlineFallback(run.underlineStyle), run.underlineStyle & 0xF != 0,
               let underlineColor = run.underlineColor
            {
                attributes[NSAttributedString.Key(kCTUnderlineColorAttributeName as String)] = underlineColor
                    .resolvedColor(with: traits).cgColor
            }
            text.setAttributes(attributes, range: run.range)
        }
        self.decorationStyles = decorationStyles
        for location in Set(attachments.keys).union(viewAttachments.keys) {
            guard let size = attachments[location]?.size ?? viewAttachments[location]?.size,
                  let alignment = attachments[location]?.alignment ?? viewAttachments[location]?.alignment,
                  LayoutNumber.isSafe(size.width, times: CGFloat(sourceLength + 1)),
                  LayoutNumber.isSafe(size.height, times: CGFloat(sourceLength + 1))
            else { continue }
            let font = text.attribute(
                NSAttributedString.Key(kCTFontAttributeName as String),
                at: location,
                effectiveRange: nil
            ) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let metrics = AttachmentMetrics(
                size: size, ascender: font.ascender, descender: font.descender,
                alignment: alignment
            )
            text.addAttributes([
                NSAttributedString.Key(kCTRunDelegateAttributeName as String): metrics.makeDelegate(),
                AttachmentMetrics.locationKey: location
            ], range: NSRange(location: location, length: 1))
        }
        // Core Text 默认不为末尾分隔符生成最后一个空行，添加零宽字符保留该行。
        if let last = string.unicodeScalars.last, CharacterSet.newlines.contains(last) {
            let attributes = text.attributes(at: sourceLength - 1, effectiveRange: nil)
            text.append(NSAttributedString(string: "\u{200B}", attributes: attributes))
        }
        attributedText = text.copy() as! NSAttributedString
        framesetter = CTFramesetterCreateWithAttributedString(text)
        // 按显式行测量 advance；framesetter 的建议宽度会省略行尾空白。
        let stringValue = text.string as NSString
        var cursor = 0
        var maximumWidth: CGFloat = 0
        var maximumPadding: CGFloat = 0
        while cursor < text.length {
            let range = stringValue.lineRange(for: NSRange(location: cursor, length: 0))
            let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            if let padding = LayoutNumber.add(ascent, descent), let fullPadding = LayoutNumber.add(padding, leading) {
                maximumPadding = max(maximumPadding, fullPadding)
            }
            // 自然宽度按每条显式行自己的段落缩进计算，不能把另一段的缩进加到最长行上。
            var indent: CGFloat = 0
            var tail: CGFloat = 0
            if let style = text.attribute(
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String),
                at: cursor,
                effectiveRange: nil
            ) {
                let paragraph = style as! CTParagraphStyle
                let paragraphRange = stringValue.paragraphRange(for: NSRange(location: cursor, length: 0))
                let spec: CTParagraphStyleSpecifier = cursor == paragraphRange
                    .location ? .firstLineHeadIndent : .headIndent
                CTParagraphStyleGetValueForSpecifier(paragraph, spec, MemoryLayout<CGFloat>.size, &indent)
                CTParagraphStyleGetValueForSpecifier(paragraph, .tailIndent, MemoryLayout<CGFloat>.size, &tail)
            }
            if let width = LayoutNumber.add(advance, max(0, indent)),
               let fullWidth = LayoutNumber.add(width, max(0, -tail))
            {
                maximumWidth = max(maximumWidth, fullWidth)
            }
            cursor = NSMaxRange(range)
        }
        idealWidth = maximumWidth
        glyphPadding = maximumPadding
    }

    func layout(
        width: CGFloat?, insets: UIEdgeInsets, scale: CGFloat, numberOfLines: Int = 0,
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) -> LYGlyphTextLayout {
        func inset(_ value: CGFloat) -> CGFloat {
            value >= 0 && LayoutNumber.isSafe(value, times: 4) ? value : 0
        }
        let insets = UIEdgeInsets(
            top: inset(insets.top),
            left: inset(insets.left),
            bottom: inset(insets.bottom),
            right: inset(insets.right)
        )
        let horizontal = LayoutNumber.add(insets.left, insets.right) ?? 0
        let vertical = LayoutNumber.add(insets.top, insets.bottom) ?? 0
        let scale = scale > 0 && LayoutNumber.isSafe(scale, times: max(idealWidth, horizontal, vertical, 2)) ? scale : 1
        let finiteWidth = width.flatMap { $0 >= 0 && LayoutNumber.isSafe($0, times: 4) ? $0 : nil }
        let outerWidth = finiteWidth ?? (LayoutNumber.add(idealWidth, horizontal) ?? idealWidth)
        let available = max(0, LayoutNumber.add(outerWidth, -horizontal) ?? 0)
        func pixelCeil(_ value: CGFloat) -> CGFloat {
            LayoutNumber.pixelCeil(value, scale: scale)
        }
        if isEmpty || (finiteWidth != nil && available <= 0) {
            return LYGlyphTextLayout(
                size: CGSize(width: min(outerWidth, pixelCeil(horizontal)), height: pixelCeil(vertical)), lines: []
            )
        }
        // 理想宽度向上对齐像素，避免浮点误差换行；纯换行仍需正宽路径保留行高。
        let contentWidth = finiteWidth == nil ? max(1 / scale, pixelCeil(available)) : available
        let frame = TextFrame(
            framesetter: framesetter,
            width: contentWidth,
            scale: scale,
            expectedLength: attributedText.length,
            minimumPadding: glyphPadding
        )
        func fallback() -> LYGlyphTextLayout {
            if !discardsMetrics {
                fallbackCount += 1
                return ResolvedText(document: document, traits: traits, wrapping: wrapping, discardMetrics: true)
                    .layout(
                        width: finiteWidth,
                        insets: insets,
                        scale: scale,
                        numberOfLines: numberOfLines
                    )
            }
            return LYGlyphTextLayout(size: CGSize(width: pixelCeil(horizontal), height: pixelCeil(vertical)), lines: [])
        }
        guard frame.isValid else { return fallback() }
        let lines = zip(frame.lines, frame.origins).compactMap { line, origin -> LYGlyphTextLayout.Line? in
            guard let baselineX = LayoutNumber.add(insets.left, origin.x),
                  let baselineY = LayoutNumber.add(insets.top, frame.height - origin.y) else { return nil }
            let range = CTLineGetStringRange(line)
            let start = min(sourceLength, max(0, range.location))
            let end = min(sourceLength, max(start, range.location + range.length))
            return LYGlyphTextLayout.Line(
                text: line,
                baseline: CGPoint(x: baselineX, y: baselineY),
                visibleSourceRanges: end > start ? [NSRange(location: start, length: end - start)] : [],
                sourceOffset: 0,
                truncationTokenRange: nil
            )
        }
        if numberOfLines > 0, lines.count > numberOfLines {
            guard let visible = truncatedLines(
                Array(lines.prefix(numberOfLines)), width: contentWidth, insets: insets, scale: scale
            ) else { return fallback() }
            return LYGlyphTextLayout(
                size: CGSize(
                    width: pixelCeil(min(outerWidth, idealWidth + horizontal)),
                    height: pixelCeil(visible.height + vertical)
                ),
                lines: visible.lines, attachments: visibleAttachments(in: visible.lines),
                viewAttachments: visibleViewAttachments(in: visible.lines),
                decorations: TextDecorations(source: document?.string ?? "", styles: decorationStyles, scale: scale),
                traits: traits, source: document?.string ?? "", actions: document?.actions ?? [], observe: observe
            )
        }
        return LYGlyphTextLayout(
            size: CGSize(
                width: pixelCeil(min(outerWidth, idealWidth + horizontal)),
                height: pixelCeil(frame.contentHeight + vertical)
            ),
            lines: lines, attachments: visibleAttachments(in: lines),
            viewAttachments: visibleViewAttachments(in: lines),
            decorations: TextDecorations(source: document?.string ?? "", styles: decorationStyles, scale: scale),
            traits: traits, source: document?.string ?? "", actions: document?.actions ?? [], observe: observe
        )
    }

    private static func padding(for text: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return LayoutNumber.add(LayoutNumber.add(ascent, descent) ?? 0, leading) ?? 0
    }

    private func visibleAttachments(in lines: [LYGlyphTextLayout.Line]) -> [LYGlyphTextLayout.Attachment] {
        visibleAttachmentRects(in: lines).compactMap { location, rect in
            attachments[location].map { .init(attachment: $0, sourceLocation: location, rect: rect) }
        }
    }

    private func visibleViewAttachments(in lines: [LYGlyphTextLayout.Line]) -> [LYGlyphTextLayout.ViewAttachment] {
        visibleAttachmentRects(in: lines).compactMap { location, rect in
            viewAttachments[location].map { .init(attachment: $0, sourceLocation: location, rect: rect) }
        }
    }

    /// 两种附件消费同一最终 run 几何，包含 RTL、截断映射和占位字符字体度量。
    private func visibleAttachmentRects(in lines: [LYGlyphTextLayout.Line]) -> [(Int, CGRect)] {
        lines.flatMap { line in
            (CTLineGetGlyphRuns(line.text) as! [CTRun]).compactMap { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let location = attributes[AttachmentMetrics.locationKey] as? Int,
                      let size = attachments[location]?.size ?? viewAttachments[location]?.size,
                      CTRunGetGlyphCount(run) > 0,
                      line.visibleSourceRanges.contains(where: { NSLocationInRange(location, $0) })
                else { return nil }
                let runRange = CTRunGetStringRange(run)
                guard runRange.location + line.sourceOffset == location,
                      line.truncationTokenRange.map({ !NSLocationInRange(runRange.location, $0) }) ?? true
                else { return nil }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let delegate = attributes[kCTRunDelegateAttributeName] as! CTRunDelegate
                let metrics = Unmanaged<AttachmentMetrics>.fromOpaque(
                    CTRunDelegateGetRefCon(delegate)
                ).takeUnretainedValue()
                let x = line.baseline.x + position.x
                let y = line.baseline.y - position.y - metrics.bottom - size.height
                guard LayoutNumber.isSafe(x), LayoutNumber.isSafe(y), LayoutNumber.isSafe(size.width),
                      LayoutNumber.isSafe(size.height), LayoutNumber.isSafe(x + size.width),
                      LayoutNumber.isSafe(y + size.height) else { return nil }
                return (location, CGRect(x: x, y: y, width: size.width, height: size.height))
            }
        }
    }

    private func truncatedLines(
        _ original: [LYGlyphTextLayout.Line], width: CGFloat, insets: UIEdgeInsets, scale: CGFloat
    ) -> (lines: [LYGlyphTextLayout.Line], height: CGFloat)? {
        guard let last = original.last else { return ([], 0) }
        let sourceRange = CTLineGetStringRange(last.text)
        let start = min(sourceLength, sourceRange.location)
        let end = min(sourceLength, sourceRange.location + sourceRange.length)
        let truncation = TailTruncation(
            text: attributedText, range: NSRange(location: start, length: end - start), width: width
        )
        let finalText = truncation.text
        let metricsText = NSMutableAttributedString(string: "")
        // 用所有可见源行重建度量前缀；软换行保持同一段落，硬分隔符保留原值。
        // 该字符串不参与源映射，人工字符不携带附件 delegate 或位置。
        for previous in original.dropLast() {
            let range = CTLineGetStringRange(previous.text)
            let sourceRange = NSRange(
                location: range.location,
                length: min(range.length, sourceLength - range.location)
            )
            metricsText.append(attributedText.attributedSubstring(from: sourceRange))
            if let last = metricsText.string.unicodeScalars.last,
               !CharacterSet.newlines.contains(last)
            {
                var attributes = attributedText.attributes(at: NSMaxRange(sourceRange) - 1, effectiveRange: nil)
                attributes.removeValue(forKey: NSAttributedString.Key(kCTRunDelegateAttributeName as String))
                attributes.removeValue(forKey: AttachmentMetrics.locationKey)
                metricsText.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            }
        }
        metricsText.append(finalText)
        // 已用显式软分隔符固定行边界，宽度只需容纳这些有限的最终 advance。
        var metricsWidth: CGFloat = width
        for previous in original {
            let advance = CGFloat(CTLineGetTypographicBounds(previous.text, nil, nil, nil))
            if LayoutNumber.isSafe(advance) { metricsWidth = max(metricsWidth, advance) }
        }
        metricsWidth = LayoutNumber.add(metricsWidth, max(1, idealWidth)) ?? max(width, idealWidth)
        let metrics = TextFrame(
            framesetter: CTFramesetterCreateWithAttributedString(metricsText), width: metricsWidth, scale: scale,
            expectedLength: metricsText.length, minimumPadding: Self.padding(for: metricsText)
        )
        let lastBaseline = metrics.origins.last.map { metrics.height - $0.y } ?? 0
        guard metrics.isValid, let x = LayoutNumber.add(insets.left, truncation.alignmentOffset),
              let y = LayoutNumber.add(insets.top, lastBaseline),
              TextFrame.isFinite(truncation.line) else { return nil }
        var lines = Array(original.dropLast())
        lines.append(LYGlyphTextLayout.Line(
            text: truncation.drawsToken ? truncation
                .line : CTLineCreateWithAttributedString(NSAttributedString(string: "")),
            baseline: CGPoint(x: x, y: y),
            visibleSourceRanges: truncation.visibleSourceRanges(
                in: truncation.line,
                source: attributedText.string as NSString
            ),
            sourceOffset: truncation.sourceOffset,
            truncationTokenRange: truncation.drawsToken ? truncation.tokenRange : nil
        ))
        return (lines, metrics.contentHeight)
    }
}

/// Core Text 的帧度量与行原点，保持系统行高规则；坐标尚未转换为 UIKit。
@MainActor
struct TextFrame {
    let contentHeight: CGFloat
    let height: CGFloat
    let lines: [CTLine]
    let origins: [CGPoint]
    let isValid: Bool

    init(
        framesetter: CTFramesetter, width: CGFloat, scale: CGFloat, expectedLength: Int? = nil,
        minimumPadding: CGFloat = 0
    ) {
        guard width > 0, LayoutNumber.isSafe(width), scale > 0, LayoutNumber.isSafe(scale) else {
            contentHeight = 0
            height = 0
            lines = []
            origins = []
            isValid = false
            return
        }
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: CGFloat(Float.greatestFiniteMagnitude) / 4), nil
        )
        guard LayoutNumber.isSafe(suggested.width), suggested.height >= 0,
              LayoutNumber.isSafe(suggested.height, times: scale),
              let frameHeight = LayoutNumber.add(
                  LayoutNumber.pixelCeil(suggested.height, scale: scale),
                  max(1 / scale, minimumPadding)
              ),
              frameHeight > 0
        else {
            contentHeight = 0
            height = 0
            lines = []
            origins = []
            isValid = false
            return
        }
        contentHeight = suggested.height
        height = frameHeight
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: frameHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let candidateLines = CTFrameGetLines(frame) as! [CTLine]
        var candidateOrigins = [CGPoint](repeating: .zero, count: candidateLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &candidateOrigins)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        let coversText = expectedLength.map { visibleRange.location + visibleRange.length >= $0 } ?? true
        let valid = coversText && !candidateLines.isEmpty && candidateOrigins.allSatisfy {
            LayoutNumber.isSafe($0.x) && LayoutNumber.isSafe($0.y) && LayoutNumber.isSafe(frameHeight - $0.y)
        } && candidateLines.allSatisfy(Self.isFinite)
        lines = valid ? candidateLines : []
        origins = valid ? candidateOrigins : []
        isValid = valid
    }

    static func isFinite(_ line: CTLine) -> Bool {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        guard [width, ascent, descent, leading].allSatisfy({ LayoutNumber.isSafe($0) }) else { return false }
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            guard positions.allSatisfy({ LayoutNumber.isSafe($0.x) && LayoutNumber.isSafe($0.y) }),
                  advances.allSatisfy({ LayoutNumber.isSafe($0.width) && LayoutNumber.isSafe($0.height) })
            else { return false }
        }
        return true
    }
}
