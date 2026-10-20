# LYGlyphText

面向 UIKit 与 SwiftUI 的轻量级只读富文本组件，计划采用纯 Swift 和 Core Text 实现，支持局部文字交互及行内图片、自定义 UIView 附件。

**当前状态：资料、实施规划与工程规范阶段。已提供文档／格式检查工具；尚未提供可安装的 Swift Package、组件功能或组件测试结果。下列能力均为首版实施目标。**

## 目标

- iOS 16 及以上，Swift 6 语言模式。
- UIKit 使用 `LYGlyphTextLabel`，SwiftUI 使用 `LYGlyphTextView`，共享展示内核。
- 富文本样式、多行换行、尾部省略、局部点击、长按及按下高亮。
- 行内 `UIImage`、`UIImageView` 及自定义 UIView；明确附件尺寸与基线对齐。
- Auto Layout 固有尺寸、多行自动撑高、布局优先级、UIStackView、列表自适应及 SwiftUI 宽度驱动测量。
- 深色模式、Dynamic Type、基础 VoiceOver 与列表复用。
- 不引入含 Objective-C 源码的第三方运行依赖。

## 文档

- [实施计划与阶段验收](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md)
- [参考库来源、版本、校验与借鉴边界](docs/REFERENCES.md)
- [开发规则](AGENTS.md)、[编码规范](CODING_STYLE.md) 与 [参与开发及检查命令](CONTRIBUTING.md)

## 架构方向

```text
LYGlyphTextDocument  文本、样式、动作标识与附件描述
        ↓
LYGlyphTextLayout    Core Text 排版、测量、截断和几何查询（内部）
        ↓
LYGlyphTextLabel     UIKit 绘制、Auto Layout、交互、附件生命周期及无障碍
        ↓
LYGlyphTextView      SwiftUI UIViewRepresentable 包装
```

尺寸测量、文字绘制、附件定位与命中检测共用一份布局结果。首版采用主线程同步排版与有界缓存，具体 UIKit 对象不进入后台任务。

## 布局支持规划

`LYGlyphTextLabel` 将继承 UIView，通过 `intrinsicContentSize`、`sizeThatFits(_:)` 和标准 `systemLayoutSizeFitting` 流程接入 Auto Layout。宿主可直接设置 Content Hugging／Compression Resistance，无需专用布局优先级接口；组件不重置宿主优先级。

多行文本由明确宽度驱动高度计算，支持 `preferredMaxLayoutWidth` 离屏估算、原生约束、宿主 SnapKit 约束、横向／纵向 UIStackView 和列表自适应。SwiftUI 使用 UIViewRepresentable 的尺寸提议，复用同一排版入口；组件自身不依赖 SnapKit，也不将 SwiftUI `layoutPriority` 映射成 UIKit 优先级。

首版不承诺 UILabel 首／末文字基线对齐等价性。完整宽度选择、裁切、缓存失效及验收规则见实施计划第 4.2 节；当前尚未实现这些布局行为。

## 当前工程检查

```sh
scripts/verify.sh docs
scripts/verify.sh format
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```

没有 Swift 源文件时，format 明确报告“不适用”；工具回归测试不代表组件测试。SwiftFormat 固定 0.59.1，需使用时显式安装或指定已有二进制，见参与开发文档。

## 范围

首版定位为只读展示组件，不包含编辑器、输入法、文本选择复制、竖排、HTML／Markdown 解析或异步渲染。功能实现和发布前，需要分别完成 Swift 6 编译、最低系统运行及交互验证。

技术路线采用 Core Text，首版不使用 TextKit 2。工程规范参考共同开发的 Club Circle、Kitta、TideRefresh 和 LYSVGAPlayer，组件实现保持独立，不引入业务 App 的架构依赖。

## 参考与许可

架构研究参考 [YYText](https://github.com/ibireme/YYText)、[BSText](https://github.com/nova286/BSText) 等公开项目。第三方源码保存在本地工作区的仓库外，本仓库只记录来源、分析与设计；参考源码不构成本组件的运行依赖。

本仓库原创内容采用 [MIT License](LICENSE)。未来如复用第三方代码，应保留对应版权及许可证；许可证未明确的代码仅用于研究，不直接移植。
