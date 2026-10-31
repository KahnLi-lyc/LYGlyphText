import UIKit

@MainActor
struct LayoutMeasurementSnapshot: Equatable {
    let layoutBuildCount: Int
    let intrinsicInvalidationCount: Int
    let cachedLayoutCount: Int
}

/// 进程内累计的测量与准备次数，只供性能基准测试读取；递增成本可忽略，不影响行为。
@MainActor
enum MeasurementCounters {
    /// 主线程新建完整布局（含显示数据）的次数；预排版采用不计数。
    static var fullLayoutBuilds = 0
    /// 只求尺寸的测量次数（未命中缓存时）。
    static var sizeMeasurements = 0
    /// 实际构建无障碍元素快照的次数。
    static var accessibilityPreparations = 0
    /// 因 trait 变化清空排版的次数。
    static var traitInvalidations = 0

    static func reset() {
        fullLayoutBuilds = 0
        sizeMeasurements = 0
        accessibilityPreparations = 0
        traitInvalidations = 0
    }
}
