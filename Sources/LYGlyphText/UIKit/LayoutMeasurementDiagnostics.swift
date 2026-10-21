import UIKit

@MainActor
struct LayoutMeasurementSnapshot: Equatable {
    let layoutBuildCount: Int
    let intrinsicInvalidationCount: Int
    let cachedLayoutCount: Int
}
