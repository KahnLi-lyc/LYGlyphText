# LYGlyphText 编码规范

## 技术与职责

- Swift tools 6.0、Swift 6 language mode、iOS 16+；首版仅 iOS／UIKit，SwiftUI 复用 UIKit 内核，零第三方运行依赖。
- `LYGlyphTextDocument` 是经过校验的快照，不持有 UIView 或业务回调；`LYGlyphTextLayout` 为 internal，保存统一布局和原文映射。
- `LYGlyphTextLabel` 负责展示、Auto Layout、附件与交互；`LYGlyphTextView` 负责 SwiftUI 更新、测量和拆卸，不另建排版或状态源。
- Core Text 是唯一排版引擎，不使用 TextKit 2 反算点击位置；首版 MainActor 同步排版，每 Label 最多保留两个布局结果。

## 命名、访问级别与文件

- 类型 UpperCamelCase，成员 lowerCamelCase；Bool 使用 is／has／can／should，方法使用动作语义。
- 公开顶层类型使用 `LYGlyphText` 前缀；内部／私有类型用清晰职责名，嵌套类型不重复前缀。避免万能 Manager、Helper、Utils。
- 默认 private，模块协作用 internal，确有宿主需求才 public；公开 class 默认 final，不为潜在扩展开放 open。
- 每个文件承担一个清晰职责，主文件名与主要类型一致；扩展使用 `Type+Responsibility.swift`，协议实现优先独立 extension。
- 不按行数机械拆文件，不创建没有当前用途的目录或抽象，不混入无关格式化或依赖升级。

## 注释与格式

- 公共类型、成员、初始化方法和枚举 case 使用简体中文 `///` DocC，保留英文 API 名称。
- 按需说明单位、UTF-16 范围、坐标系、默认值、MainActor、持有关系、失败及取消语义。内部中文注释解释非显然行为，不逐行翻译语法。
- UTF-8、LF、末尾换行、4 空格缩进；SwiftFormat 以 120 列为换行目标，固定版本与参数见 [开发流程](CONTRIBUTING.md)。不清除版权／许可头。
- 仅使用非空 MARK 分组，按需排列：Public Properties、Private Properties、Views、Initialization、Lifecycle、Layout、Public Methods、Interaction、Teardown、Private Methods。
- 独占且需要延迟创建的子视图使用 private lazy var 闭包初始化；注入视图与简单不可变对象不强制 lazy。清理不触发 lazy 初始化。

## 范围、错误与线程

- 内部索引统一为 UTF-16；通过安全转换关联原 Swift String，不将 Character 数量当作 NSRange 长度。
- 非法范围、切开组合字符、重叠动作、重复附件 ID 或非法尺寸返回明确错误；不能以默认值掩盖非法输入。
- 避免强制解包、try! 和静默吞错；fatalError 仅用于已标记不可用的初始化入口。
- UIKit 相关对象、文档构造、附件工厂、动作回调与清理在 MainActor；含 UIKit 属性的不可变文档不因此获得 Sendable。
- 不通过 @unchecked Sendable、nonisolated(unsafe)、关闭并发检查或普遍添加 @preconcurrency 换取编译通过。
- 文档替换、滚动接管、视图移除和 SwiftUI dismantle 均有取消与幂等清理路径；取消不发送 tap。deinit 不访问 UI。
- 组件不接管宿主代理、不做全局方法交换、不引入业务状态和网络服务；网络图片只经可替换的加载协议请求，测量不发请求。诊断不输出完整宿主文本、URL 查询参数或凭据。

## Auto Layout、附件与环境

- 通过 intrinsicContentSize／sizeThatFits 和标准 systemLayoutSizeFitting 流程对接布局，不提供另一套优先级 API；具体规则以 [实施计划](docs/superpowers/plans/2026-10-20-lyglyphtext-implementation.md) 第 4.2 节为准。
- 宿主设置的 Hugging／Compression Resistance 不被 configure、内容更新或复用重置。preferredMaxLayoutWidth 仅参与固有尺寸估算，绘制按实际 bounds。
- 测量不改 frame／约束，不调用 layoutIfNeeded，不创建附件；有效宽度未变时不重复失效，不以旧高度限制新固有高度。
- 使用原生 Auto Layout 管理普通子视图，Core Text 几何管理文字和附件外框；不读取固定屏幕宽度，不引入 SnapKit。
- 附件尺寸来自文档，工厂不能反向改变排版；每个宿主使用独立实例，隐藏附件卸载，重复清理安全。
- 支持 Dynamic Type、语义颜色、Dark Mode、RTL 和 VoiceOver；显式固定字号保持固定，不复制业务 App 的全局固定字号策略。
- SwiftUI 测量直接消费 proposal，不依赖旧 bounds，不在测量期间修改 Binding；layoutPriority 不映射为 UIKit 优先级。

## 测试与来源

- 测试观察行为和边界，不镜像实现或仅调用回调代替真实交互；异步测试优先可控时钟／事件，不靠任意 sleep。
- 布局断言固定字体、宽度和 scale，截图标记系统；UIKit 相关测试在 iOS 测试宿主运行，macOS swift test 不代替。
- 每个阶段保持可审阅；记录已验证、失败和未执行项，不能由工具链存在推导最低系统可运行。
- Club Circle、Kitta、TideRefresh、LYSVGAPlayer 是已有共同开发实践参考；YYText／BSText 等是第三方源码研究。参考不等于依赖或获准复制。
- 如复制或改写第三方代码，保留要求的版权与许可并记录来源提交；许可证未明确的源码只研究，不移植。
