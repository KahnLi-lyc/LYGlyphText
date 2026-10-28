# L4 网络图片真实尺寸验证记录

日期：2026-10-28。基于 L3，分支 `codex/l4-remote-image-size`。契约见 [L 批次](../superpowers/plans/2026-10-27-label-refinements.md) L4。

## 交付内容

- `LYGlyphTextLabel.onRemoteImageLoad`（SwiftUI 对应参数）：远程图片加载成功时回调附件 ID 与图片 point 尺寸，含同步缓存命中；取消或失败不回调；SwiftUI 拆卸释放。
- `LYGlyphTextDocument.replacingRemoteImageSize(id:size:)`：返回只替换该远程图片排版尺寸的新文档，文字、样式、动作、其他附件不变，原文档不变。
- `LYGlyphTextDocumentError` 新增 `unknownAttachmentID(id:)`（对穷举 switch 的宿主是源码变化，见 CHANGELOG）；非法尺寸仍为 `invalidAttachmentSize`。
- 组件不在加载后自动改排版，保持测量稳定；宿主用回调尺寸按比例重建文档并刷新行高。

## 行为证据

`Tests/LYGlyphTextTests/RemoteImageSizeTests.swift`（3 项）：成功回调尺寸、失败不回调、移出 window 取消后迟到结果不回调、同步缓存回调、拆卸释放；替换尺寸后原文档不变、动作与样式保留、测量高度增加且附件矩形为新尺寸、未知 ID 与非法尺寸报错；Label 换成新尺寸文档后以新尺寸重新挂载并重新请求，旧请求取消。

## 正式检查

| 检查 | 结果 |
|---|---|
| 定向（RemoteImageSize／RemoteImage 等，与 L5 一起运行） | 全部通过（`l45-targeted-01/`） |
| 包含 L2—L5 全部代码的完整回归（L5 候选） | **442／442 Passed**，0 失败／跳过，`runtimeWarnings=[]` |

证据保存在主 checkout 的 `.build/verification/l4/`。
