# LYGlyphText

面向 UIKit 与 SwiftUI 的轻量级只读富文本组件，计划采用纯 Swift 和 Core Text 实现，支持局部文字交互及行内图片、自定义 UIView 附件。

**当前状态：规划与资料归档阶段。尚未提供可安装的 Swift Package、功能实现或组件测试结果。**

## 目标

- iOS 16 及以上，Swift 6 语言模式。
- UIKit 使用 `LYGlyphTextLabel`，SwiftUI 使用 `LYGlyphTextView`，共享展示内核。
- 富文本样式、多行换行、尾部省略、局部点击、长按及按下高亮。
- 行内 `UIImage`、`UIImageView` 及自定义 UIView；明确附件尺寸与基线对齐。
- 深色模式、Dynamic Type、基础 VoiceOver 与列表复用。
- 不引入含 Objective-C 源码的第三方运行依赖。

## 文档

- [实施计划与阶段验收](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md)
- [参考库来源、版本、校验与借鉴边界](docs/REFERENCES.md)

## 架构方向

```text
LYGlyphTextDocument  文本、样式、动作标识与附件描述
        ↓
LYGlyphTextLayout    Core Text 排版、测量、截断和几何查询（内部）
        ↓
LYGlyphTextLabel     UIKit 绘制、交互、附件生命周期及无障碍
        ↓
LYGlyphTextView      SwiftUI UIViewRepresentable 包装
```

尺寸测量、文字绘制、附件定位与命中检测共用一份布局结果。首版采用主线程同步排版与有界缓存，具体 UIKit 对象不进入后台任务。

## 范围

首版定位为只读展示组件，不包含编辑器、输入法、文本选择复制、竖排、HTML／Markdown 解析或异步渲染。功能实现和发布前，需要分别完成 Swift 6 编译、最低系统运行及交互验证。

## 参考与许可

架构研究参考 [YYText](https://github.com/ibireme/YYText)、[BSText](https://github.com/nova286/BSText) 等公开项目。第三方源码保存在本地工作区的仓库外，本仓库只记录来源、分析与设计；参考源码不构成本组件的运行依赖。

本仓库原创内容采用 [MIT License](LICENSE)。未来如复用第三方代码，应保留对应版权及许可证；许可证未明确的代码仅用于研究，不直接移植。
