import os
import UIKit

extension LYGlyphTextLabel {
    /// 先移除全部内部状态和 superview，再允许业务清理回调重入。
    private func unmount(_ removed: [MountedAttachment], removing container: AttachmentContainer? = nil) {
        guard !removed.isEmpty || container != nil else { return }
        attachmentCleanupDepth += 1
        defer {
            attachmentCleanupDepth -= 1
            setNeedsLayout()
        }
        // 一个旧批次全部清理完毕前，不允许新工厂重新取得尚未回调的旧实例。
        container?.removeFromSuperview()
        for attachment in removed {
            (attachment.view as? RemoteImageView)?.cancel()
            attachment.view.removeFromSuperview()
        }
        for attachment in removed {
            attachment.provider?.onUnmount?(attachment.descriptor, attachment.view)
        }
    }

    func resetAttachments() {
        clearAccessibilitySnapshot()
        cancelActionInteraction()
        attachmentRevision &+= 1
        failedAttachmentIDs.removeAll()
        let removed = Array(mountedAttachments.values)
        mountedAttachments.removeAll()
        let container = attachmentContainer
        attachmentContainer = nil
        setNeedsLayout()
        unmount(removed, removing: container)
    }

    func reconcileAttachments() {
        guard !isTearingDown, attachmentCleanupDepth == 0, !isReconcilingAttachments, window != nil else { return }
        isReconcilingAttachments = true
        defer { isReconcilingAttachments = false }
        let revision = attachmentRevision
        let layout = measuredLayout(width: max(0, bounds.width))
        let geometry = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        let contentRect = geometry?.contentClip ?? .zero
        let placements = layout.viewAttachments.compactMap { placement -> (LYGlyphTextLayout.ViewAttachment, CGRect)? in
            guard let rect = geometry?.displayRect(placement.rect),
                  !contentRect.isEmpty, rect.intersects(contentRect) else { return nil }
            return (placement, rect)
        }
        let visibleIDs = Set(placements.map(\.0.attachment.id))
        failedAttachmentIDs.formIntersection(visibleIDs)
        let hiddenIDs = Set(mountedAttachments.keys).subtracting(visibleIDs)
        if !hiddenIDs.isEmpty { cancelActionInteraction() }
        let removed = hiddenIDs.compactMap { mountedAttachments.removeValue(forKey: $0) }
        unmount(removed)
        guard revision == attachmentRevision, window != nil else { return }
        let provider = viewProvider
        let remoteImages = document?.remoteImages ?? [:]
        guard provider != nil || !remoteImages.isEmpty else { return }
        attachmentContainer?.frame = contentRect
        for (placement, displayRect) in placements {
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            let descriptor = placement.attachment
            let rect = displayRect.offsetBy(dx: -contentRect.minX, dy: -contentRect.minY)
            if let mounted = mountedAttachments[descriptor.id] {
                mounted.view.frame = rect
                continue
            }
            guard !failedAttachmentIDs.contains(descriptor.id) else { continue }
            let remote = remoteImages[descriptor.id]
            // 远程图片由组件内部视图承载，不调用宿主工厂；其他视图附件仍需要工厂。
            guard remote != nil || provider != nil else { continue }
            let candidate: UIView? = if let remote {
                RemoteImageView(descriptor: remote)
            } else {
                provider?.makeView(descriptor)
            }
            // 工厂可以同步替换文档、provider、reload 或移出 window；过期结果从未挂载。
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            guard let candidate else {
                failedAttachmentIDs.insert(descriptor.id)
                continue
            }
            guard candidate !== self, candidate.superview == nil,
                  !isDescendant(of: candidate),
                  !mountedAttachments.values.contains(where: { $0.view === candidate })
            else {
                Self.attachmentLogger.debug("拒绝已有宿主、重复实例或自身／祖先的附件视图")
                failedAttachmentIDs.insert(descriptor.id)
                continue
            }
            let container: AttachmentContainer
            if let existing = attachmentContainer {
                container = existing
            } else {
                container = AttachmentContainer(frame: contentRect)
                attachmentContainer = container
                addSubview(container)
            }
            candidate.isUserInteractionEnabled = descriptor.isInteractive
            candidate.frame = rect
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            cancelActionInteraction()
            mountedAttachments[descriptor.id] = MountedAttachment(
                descriptor: descriptor, view: candidate, provider: remote == nil ? provider : nil
            )
            container.addSubview(candidate)
            // 挂载完成后再请求；同步缓存结果直接显示，回调不会重新进入排版。
            let id = descriptor.id
            (candidate as? RemoteImageView)?.load(
                using: imageLoader, scale: traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
            ) { [weak self] size in
                self?.onRemoteImageLoad?(id, size)
            }
        }
    }
}

/// 容器只命中实际交互附件，不拦截文字和空白区域的宿主手势。
@MainActor
final class AttachmentContainer: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(frame:)")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }
}
