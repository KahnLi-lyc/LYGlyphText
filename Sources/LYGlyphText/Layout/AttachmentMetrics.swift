import CoreText
import UIKit

/// C 回调只读取纯数值；不持有 UIImage、Label、工厂或 MainActor 状态。
final class AttachmentMetrics {
    static let locationKey = NSAttributedString.Key("LYGlyphText.attachmentLocation")
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    /// 附件底边相对于 Core Text 基线的向上偏移。
    let bottom: CGFloat

    init(size: CGSize, ascender: CGFloat, descender: CGFloat, alignment: LYGlyphTextAttachmentAlignment) {
        width = size.width
        bottom = switch alignment {
        case .top: ascender - size.height
        case .center: (ascender + descender - size.height) / 2
        case .bottom: descender
        }
        // 即使一行只有小附件，也保留占位字体区域，避免字体底部度量消失。
        ascent = max(ascender, bottom + size.height, 0)
        descent = max(-descender, -bottom, 0)
    }

    func makeDelegate() -> CTRunDelegate {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in Unmanaged<AttachmentMetrics>.fromOpaque(pointer).release() },
            getAscent: { pointer in Unmanaged<AttachmentMetrics>.fromOpaque(pointer).takeUnretainedValue().ascent },
            getDescent: { pointer in Unmanaged<AttachmentMetrics>.fromOpaque(pointer).takeUnretainedValue().descent },
            getWidth: { pointer in Unmanaged<AttachmentMetrics>.fromOpaque(pointer).takeUnretainedValue().width }
        )
        let pointer = Unmanaged.passRetained(self).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else {
            Unmanaged<AttachmentMetrics>.fromOpaque(pointer).release()
            preconditionFailure("Core Text 无法创建有效的附件度量 delegate")
        }
        return delegate
    }
}
