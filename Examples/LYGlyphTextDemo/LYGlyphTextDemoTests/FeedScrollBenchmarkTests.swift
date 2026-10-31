@testable import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

/// 业务图文列表的模拟器滚动基准：LYGlyphText 与系统 UILabel 交替运行，逐步推进 contentOffset，
/// 每步在主线程同步完成布局与绘制（`layoutIfNeeded` + `CATransaction.flush`）并计时。
///
/// 只比较相对差异与计数器；模拟器使用 Mac 的 CPU／GPU，绝对值不代表真机。Release 运行时输出 JSON 附件。
@MainActor
final class FeedScrollBenchmarkTests: XCTestCase {
    private struct Run: Encodable {
        let mode: String
        let round: Int
        let pointsPerFrame: Double
        let steps: Int
        let p50Microseconds: Double
        let p95Microseconds: Double
        let maxMicroseconds: Double
        let totalMilliseconds: Double
        let fullLayoutBuilds: Int
        let accessibilityPreparations: Int
        let traitInvalidations: Int
    }

    private struct Report: Encodable {
        let schemaVersion = 1
        let configuration: String
        let window = "390x844pt"
        let clock = "DispatchTime.uptimeNanoseconds per step (layoutIfNeeded + CATransaction.flush)"
        let runs: [Run]
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        sorted.isEmpty ? 0 : sorted[max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1)]
    }

    private func run(usesUILabel: Bool, round: Int, pointsPerFrame: CGFloat, steps: Int) throws -> Run {
        let controller = try FeedPerformanceController(profile: false, usesUILabel: usesUILabel)
        // 测试宿主基于 scene；不挂到 scene 的 window 不会显示，列表也不会布局。
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let deadline = Date().addingTimeInterval(30)
        while !controller.isReady, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(controller.isReady, "预排版未在 30 秒内完成")
        let table = controller.tableView
        table.layoutIfNeeded()
        CATransaction.flush()
        MeasurementCounters.reset()
        XCTAssertGreaterThan(table.bounds.height, 0, "列表未布局，基准无效")
        var samples: [Double] = []
        var direction: CGFloat = 1
        for _ in 0 ..< steps {
            let maximum = max(0, table.contentSize.height - table.bounds.height)
            var offset = table.contentOffset.y + direction * pointsPerFrame
            if offset >= maximum {
                offset = maximum
                direction = -1
            } else if offset <= 0 {
                offset = 0
                direction = 1
            }
            let start = DispatchTime.now().uptimeNanoseconds
            table.contentOffset.y = offset
            table.layoutIfNeeded()
            CATransaction.flush()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
        }
        let sorted = samples.sorted()
        return Run(
            mode: usesUILabel ? "UILabel" : "LYGlyphText", round: round, pointsPerFrame: Double(pointsPerFrame),
            steps: steps, p50Microseconds: percentile(sorted, 0.5), p95Microseconds: percentile(sorted, 0.95),
            maxMicroseconds: sorted.last ?? 0, totalMilliseconds: samples.reduce(0, +) / 1000,
            fullLayoutBuilds: MeasurementCounters.fullLayoutBuilds,
            accessibilityPreparations: MeasurementCounters.accessibilityPreparations,
            traitInvalidations: MeasurementCounters.traitInvalidations
        )
    }

    func testFeedScrollAgainstUILabel() throws {
        #if DEBUG
            let configuration = "Debug sanity (not Release performance)"
            let rounds = 1
            let steps = 30
        #else
            let configuration = "Release"
            let rounds = 3
            let steps = 300
        #endif
        var runs: [Run] = []
        // 60Hz 下 800 与 2800 pt/s 对应的每帧位移；两种实现交替，减少机器负载漂移的影响。
        for round in 1 ... rounds {
            for pointsPerFrame: CGFloat in [800.0 / 60, 2800.0 / 60] {
                for usesUILabel in [false, true] {
                    try runs.append(run(
                        usesUILabel: usesUILabel, round: round, pointsPerFrame: pointsPerFrame, steps: steps
                    ))
                }
            }
        }
        XCTAssertTrue(runs.allSatisfy { $0.steps == steps && $0.totalMilliseconds > 0 })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Report(configuration: configuration, runs: runs))
        for run in runs {
            print(String(
                format: "FEED-BENCH %@ r%d %.1fpt/frame p50=%.0fus p95=%.0fus max=%.0fus total=%.0fms full=%d ax=%d trait=%d",
                run.mode, run.round, run.pointsPerFrame, run.p50Microseconds, run.p95Microseconds,
                run.maxMicroseconds, run.totalMilliseconds, run.fullLayoutBuilds, run.accessibilityPreparations,
                run.traitInvalidations
            ))
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "feed-scroll-benchmark-\(configuration.hasPrefix("Debug") ? "debug-sanity" : "release").json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
