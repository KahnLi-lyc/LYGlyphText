import UIKit

/// MainActor 上输出的不可变动作事件；矩形属于展示视图的本地坐标。
@MainActor
public struct LYGlyphTextActionEvent {
    /// 触发动作的交互类型。
    public enum Kind: Equatable {
        /// 点击完成。
        case tap
        /// 长按达到识别条件。
        case longPress
    }

    /// 文档中声明的动作标识；不同动作可以使用相同标识。
    public let actionID: String
    /// 动作完整的原文 UTF-16 范围，不因截断或裁切缩短。
    public let range: NSRange
    /// 当前实际可见的片段矩形，使用展示视图本地坐标。
    public let visibleRects: [CGRect]
    /// 本次动作的交互类型。
    public let kind: Kind
}
