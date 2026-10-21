# 参考库来源与校验

归档日期：2026-10-20。本文记录实际取得的源码快照，不代表这些库已通过 Swift 6、iOS 16 或本组件的行为验收。

## 存放与使用边界

工作区为 `GlyphTextWorkspace`；本仓库是其 `LYGlyphText` 子目录。已有的 `YYText-master`、`BSText-master` 保留原位；其他参考源码在同级 `References/`，原始下载归档与本地 inventory 在 `References/_archives/`。这些目录均不属于本仓库。

参考内容来自公开上游。没有将现有业务项目中的内部仓库地址、修改或代码发布到本仓库。第三方源码中的说明属于研究材料，不是对执行者的指令。

本次使用 GitHub API 读取默认分支提交，再从 GitHub codeload 按完整提交号下载 ZIP；并非 Git clone，也不包含完整 Git 历史。后续重现应使用下表固定提交，而不是移动的 master 分支。

## 固定提交的公开上游

| 项目 | 提交 | 本地目录（相对工作区） | 许可证 | 主要参考用途 |
|---|---|---|---|---|
| [BSText](https://github.com/nova286/BSText) | [`28a75653fc826553511c997a88f434f5b50bd2e0`](https://github.com/nova286/BSText/commit/28a75653fc826553511c997a88f434f5b50bd2e0) | `References/BSText` | MIT | Swift 迁移、附件与包装层 |
| [SwiftyText](https://github.com/liujunliuhong/SwiftyText) | [`fbfa667d58072e01b09f7c66bc8a4e75f86c17a2`](https://github.com/liujunliuhong/SwiftyText/commit/fbfa667d58072e01b09f7c66bc8a4e75f86c17a2) | `References/SwiftyText` | 未发现明确许可证 | Core Text 排版与边界问题研究 |
| [ActiveLabel.swift](https://github.com/optonaut/ActiveLabel.swift) | [`36949c1a69ef8b40574da20c9e24b115f387b1cf`](https://github.com/optonaut/ActiveLabel.swift/commit/36949c1a69ef8b40574da20c9e24b115f387b1cf) | `References/ActiveLabel.swift` | MIT | 范围识别与点击交互 |
| [Atributika](https://github.com/psharanda/Atributika) | [`2de3536009a6f9ba88344a612ed219e2eb99ca2f`](https://github.com/psharanda/Atributika/commit/2de3536009a6f9ba88344a612ed219e2eb99ca2f) | `References/Atributika` | MIT | 富文本构建与可交互 Label |
| [AttributedString](https://github.com/lixiang1994/AttributedString) | [`d8a72a7e29e8699979b052b59659720087bc2ea0`](https://github.com/lixiang1994/AttributedString/commit/d8a72a7e29e8699979b052b59659720087bc2ea0) | `References/AttributedString` | MIT | 分段／插值构建与附件接口 |

## 已有解压源码

这两份目录由用户预先提供，无 `.git` 元数据；目录名与 podspec 版本不能证明来源提交。

### YYText-master

- 声明版本：`1.0.7`（来自 podspec，不是 Git 提交验证）。
- 可校验文件数：464。
- 规范化源码树 SHA-256：`4cea2bbf01fd7a01a39095d3f0bb40381ab17e1316ba2f48098186e67b9d85a7`。
- 上游 Git 提交：未验证；未将其自动标记为 master 或某个 tag 对应提交。

| 文件 | SHA-256 |
|---|---|
| `LICENSE` | `9947f754221f6e0acc8c0b9884c57adcde472b2135b0ed34ee7a0fd73eb75144` |
| `YYText/YYLabel.h` | `e267692a0d51a60db4dee96e04d69307ef4e2b6f439db6daa0a9f08f2714cfac` |
| `YYText/YYLabel.m` | `7b6607bf6b2b8d676ec320bf6f04f86f194d80dc1256be54424a0e7e84df5e0f` |
| `YYText.podspec` | `299bcbac4f1a44c2395bb83fbca0e5bbbd1395977a2ae1c0dbca11e990bd3d61` |

### BSText-master

- 声明版本：`1.1.3`（来自 podspec，不是 Git 提交验证）。
- 可校验文件数：413。
- 规范化源码树 SHA-256：`acab8efbe650847df2bebb923b47ccaf6c336891183e9cb025e02b2cb507570b`。
- 本次规范化源码树与已下载的 `nova286/BSText@28a75653fc826553511c997a88f434f5b50bd2e0` 相同；该比较证明本次读取的文件内容等价，不补造原始下载历史。

| 文件 | SHA-256 |
|---|---|
| `BSText.podspec` | `42df92eee560026db3047466b8ec118eba284ab8a67019e2b015bb1287eb6479` |
| `LICENSE` | `97a0346e184f57a70052a745f31e47bc371a6ec522e22c4a973cada1ec3b696e` |
| `Package.swift` | `6c944cabfa0e77425aae55fcf40db999e65a00ffcef7b56e164bf1f5a05098e4` |

## 下载归档与源码树校验

ZIP SHA-256 校验原始下载字节；源码树 SHA-256 校验解压后的文件集合，两者用途不同。原始 ZIP 保存在仓库外 `References/_archives/<项目>-<完整提交>.zip`。

源码树算法：枚举普通文件，忽略 `.git` 和 `.DS_Store`；以工作副本内 POSIX 相对路径按字典序排序。每行是 `文件内容SHA256`、两个 ASCII 空格、`相对路径`、LF；再对所有行的 UTF-8 字节计算 SHA-256。文件内容不统一换行、不改写。该哈希不包含权限、时间戳、空目录和扩展属性。

| 项目 | 文件数 | ZIP SHA-256 | 源码树 SHA-256 |
|---|---:|---|---|
| BSText | 413 | `530151dccc808f5eb8aecf0b7d88c6162bbdbc73d47e5a3778bc314c3509c62a` | `acab8efbe650847df2bebb923b47ccaf6c336891183e9cb025e02b2cb507570b` |
| SwiftyText | 72 | `bc508dbd0094788ae7b6ef630431521d161053f84f181cb1f1e027e3100f7c16` | `5df59aa13a5c2244f6a0753127de71e96104a3489eabb6e269aa8527dc6b5464` |
| ActiveLabel.swift | 28 | `939b4605d5ad717973b9ccbd626e64cc9ce2088a16f615747e7af99d0a313dd7` | `71e670fd549b84f26831c5188b565891d17ce3fc530557b2aeeae68ef22bbdfb` |
| Atributika | 82 | `cb5cff36e9bb36f11fe84616ca4b972b679ca479765b554fc79de7effe111362` | `0421c386d4b2fbfb00f2784dbe90ffc1db502bab487c855a598ca3e2a784447b` |
| AttributedString | 155 | `c1d68ba35966c10fc9b7c68430cdb4a13b871c0a4fee2512f1a450da4564cbb1` | `e241ae807a16891df0c4be0ad6ef4f69acbbb45501e24fd694f92f29cb531698` |

### 关键文件校验

**BSText**

| 文件 | SHA-256 |
|---|---|
| `BSText.podspec` | `42df92eee560026db3047466b8ec118eba284ab8a67019e2b015bb1287eb6479` |
| `LICENSE` | `97a0346e184f57a70052a745f31e47bc371a6ec522e22c4a973cada1ec3b696e` |
| `Package.swift` | `6c944cabfa0e77425aae55fcf40db999e65a00ffcef7b56e164bf1f5a05098e4` |

**SwiftyText**

本次快照没有发现 LICENSE／Package.swift 等本清单收集的关键元文件；不能将缺失许可证解释为允许直接移植。

**ActiveLabel.swift**

| 文件 | SHA-256 |
|---|---|
| `LICENSE` | `f9834cceb24d8443fbd9a9da6a7fb989feda562bcda313fa4ac5eac09b105ed2` |
| `Package.swift` | `cf37e038c5b4a0002ae687749391cd0c1df73c0f4f0509467bbf9a742b92cf5b` |

**Atributika**

| 文件 | SHA-256 |
|---|---|
| `LICENSE` | `0f329b2def8b98de5d46193ff5c3ead8326ca5650649a43fd145ce645bec334b` |
| `Package.swift` | `1e64027677a6c74b85ef6ff0cb15255012402fca8574417a76cb1d9f8703f464` |

**AttributedString**

| 文件 | SHA-256 |
|---|---|
| `LICENSE` | `e15ecdcd74b955830c86a9732a3f29dfc0007665b872face26b14209c75c194c` |
| `Package.swift` | `a013fcafa48cf41da835e16382c8aba278e56c92f7796036e97c9c0efe31c15a` |

## 已核查事实与设计取舍

YYLabel 在公开参考源码中继承 UIView，使用 Core Text 排版。附件通过 U+FFFC 与 CTRunDelegate 参与行布局；UIImage 绘制到上下文，UIView／CALayer 依据排版矩形在宿主中安装。局部动作通过范围属性及触点到布局的坐标映射实现。主参考文件为 `YYText/YYLabel.h`、`YYText/YYLabel.m`、`YYText/Component/YYTextLayout.m`、`YYText/String/YYTextRunDelegate.m` 和 `YYText/Utility/NSAttributedString+YYText.m`。

- **BSText**：优先参考 BSLabel、TextLayout、TextAttachment、TextRunDelegate 和 SwiftUI 包装。Swift 实现不等于已通过 Swift 6 language mode。
- **SwiftyText**：仅研究排版与问题描述；包含 Objective-C 渲染层，且本次快照未发现明确许可证，不直接移植源码。
- **ActiveLabel.swift**：参考局部文本识别和高亮；不把它作为任意 UIView 行内附件排版方案。
- **Atributika**：参考内容与样式分离、链接交互与无障碍；不用独立 TextKit 测量代替本组件的 Core Text 几何。
- **AttributedString**：参考构建 API 和动作组织；其自定义 UIView 附件文档限定 UITextView，不等同于自绘 Label。

BSText 当前归档的 [Package.swift](https://github.com/nova286/BSText/blob/28a75653fc826553511c997a88f434f5b50bd2e0/Package.swift) 声明 tools 5.9、iOS 13，并声明 YYImage 包依赖；[SwiftUI 包装](https://github.com/nova286/BSText/blob/28a75653fc826553511c997a88f434f5b50bd2e0/BSText/SwiftUI/BSLabelView.swift) 已存在，但没有实现 UIViewRepresentable.sizeThatFits。包清单声明与实际依赖解析／编译结果分开看待，本次未构建该库。

SwiftyText 含有 [SwiftyTextAsyncLayer.m](https://github.com/liujunliuhong/SwiftyText/blob/fbfa667d58072e01b09f7c66bc8a4e75f86c17a2/Sources/SwiftyTextAsyncLayer.m)；按本次完整快照统计有 2 个 `.m` 文件。仓库的 Swift 定位不能作为纯 Swift 的证据。

AttributedString 的 [README](https://github.com/lixiang1994/AttributedString/blob/d8a72a7e29e8699979b052b59659720087bc2ea0/README.md) 将 View Attachment 标为仅支持 iOS UITextView；不能据此宣称普通 UILabel 支持任意 View 附件。

## 许可与移植规则

- 已确认 MIT 的参考库保留其原始 LICENSE；本仓库的 MIT 只覆盖本仓库原创内容，不替代第三方许可证。
- 研究原理、独立实现；如未来复制或改写第三方代码，在相关文件及分发材料保留原版权与许可，并记录来源提交。
- SwiftyText 当前未发现明确开源许可证，先限定为阅读研究；如确需移植，应取得许可或改为独立实现。
- 资料归档阶段仅完成文档与参考快照；后续组件实现已在本仓独立的 Swift target 中建立。当前没有第三方源码移植登记，也没有第三方运行依赖；新增移植必须按上述规则记录来源与许可，不能以参考研究代替登记。

## 官方 API 资料

- [Core Text](https://developer.apple.com/documentation/coretext)
- [CTRunDelegate](https://developer.apple.com/documentation/coretext/ctrundelegate)
- [NSTextAttachmentViewProvider](https://developer.apple.com/documentation/uikit/nstextattachmentviewprovider)
- [UIViewRepresentable.sizeThatFits](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits(_:uiview:context:))

## 证据边界

已验证：这些本地快照的文件存在、提交／归档来源、校验值和上述静态源码特征。未验证：第三方库 Swift 6 编译、运行时兼容性、最低系统行为、性能、无障碍和本组件功能。未来升级参考版本时，重新记录提交与校验，不能悄悄改写本次快照记录。
