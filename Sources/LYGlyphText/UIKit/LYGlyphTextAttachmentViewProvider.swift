import UIKit

/// 主线程上的附件工厂。每个宿主须返回独立且尚未挂载的 UIView。
@MainActor
public final class LYGlyphTextAttachmentViewProvider {
    /// 仅在有 window 的展示布局中创建可见附件；nil 在本次连续可见期间不重试。
    public let makeView: @MainActor (LYGlyphTextViewAttachment) -> UIView?
    /// 成功挂载的视图移出宿主后调用一次，使用最初创建它的 provider。
    public let onUnmount: (@MainActor (LYGlyphTextViewAttachment, UIView) -> Void)?

    /// 创建不可变工厂对象。对象身份变化或显式 reloadAttachments 会重建附件。
    public init(
        makeView: @escaping @MainActor (LYGlyphTextViewAttachment) -> UIView?,
        onUnmount: (@MainActor (LYGlyphTextViewAttachment, UIView) -> Void)? = nil
    ) {
        self.makeView = makeView
        self.onUnmount = onUnmount
    }
}
