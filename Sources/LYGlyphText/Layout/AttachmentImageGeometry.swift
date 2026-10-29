import UIKit

/// 本地图片附件在声明框内的绘制矩形，语义与 UIImageView 的 contentMode 一致。
///
/// 只决定绘制位置，不影响排版尺寸；超出声明框的部分由绘制方裁切。对齐类模式使用物理方向，
/// 与 UIImageView 相同，不随 RTL 翻转。
enum AttachmentImageGeometry {
    static func drawingRect(imageSize: CGSize, in box: CGRect, contentMode: UIView.ContentMode) -> CGRect {
        let width = imageSize.width
        let height = imageSize.height
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return box }
        func placed(_ size: CGSize, horizontal: CGFloat, vertical: CGFloat) -> CGRect {
            CGRect(
                x: box.minX + (box.width - size.width) * horizontal,
                y: box.minY + (box.height - size.height) * vertical,
                width: size.width, height: size.height
            )
        }
        switch contentMode {
        case .scaleAspectFit, .scaleAspectFill:
            let ratio = contentMode == .scaleAspectFit
                ? min(box.width / width, box.height / height)
                : max(box.width / width, box.height / height)
            return placed(CGSize(width: width * ratio, height: height * ratio), horizontal: 0.5, vertical: 0.5)
        case .center: return placed(imageSize, horizontal: 0.5, vertical: 0.5)
        case .top: return placed(imageSize, horizontal: 0.5, vertical: 0)
        case .bottom: return placed(imageSize, horizontal: 0.5, vertical: 1)
        case .left: return placed(imageSize, horizontal: 0, vertical: 0.5)
        case .right: return placed(imageSize, horizontal: 1, vertical: 0.5)
        case .topLeft: return placed(imageSize, horizontal: 0, vertical: 0)
        case .topRight: return placed(imageSize, horizontal: 1, vertical: 0)
        case .bottomLeft: return placed(imageSize, horizontal: 0, vertical: 1)
        case .bottomRight: return placed(imageSize, horizontal: 1, vertical: 1)
        case .scaleToFill, .redraw: return box
        @unknown default: return box
        }
    }
}
