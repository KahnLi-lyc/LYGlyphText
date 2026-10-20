import Foundation

/// MainActor 上的不可变动作描述；范围和重叠关系在文档构造时校验。
@MainActor
public struct LYGlyphTextAction {
    /// 宿主识别动作的非空标识；同一文档允许重复，且不进行裁剪或大小写转换。
    public let actionID: String
    /// 动作覆盖的原文 UTF-16 范围，必须非空并包含完整组合字符。
    public let range: NSRange
    /// 按下时的前景与背景样式；不改变字体、度量或附件尺寸。
    public let pressedStyle: LYGlyphTextPressedStyle

    /// 创建动作描述；动作实例按其在文档内的位置区分，不以 actionID 唯一标识。
    public init(actionID: String, range: NSRange, pressedStyle: LYGlyphTextPressedStyle = .init()) {
        self.actionID = actionID
        self.range = range
        self.pressedStyle = pressedStyle
    }
}
