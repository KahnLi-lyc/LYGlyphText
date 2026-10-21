@testable import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

@MainActor
final class PerformanceMeasurementTests: XCTestCase {
    private struct Phase: Encodable {
        let name: String
        let rawNanoseconds: [UInt64]
        let p50Nanoseconds: UInt64
        let p95Nanoseconds: UInt64
        let layoutBuildBefore: [Int]
        let layoutBuildAfter: [Int]
        let factoryCount: Int
    }

    private struct Result: Encodable {
        let input: PerformanceSample.Metadata
        let configuration: String
        let fontName: String
        let fontPointSize: Double
        let widthPoints: Double
        let scale: Double
        let bitmapWidthPixels: Int
        let bitmapHeightPixels: Int
        let bitmapHeightPoints: Double
        let includesViewSubtree: Bool
        let warmupCount: Int
        let phases: [Phase]
    }

    private struct Report: Encodable {
        let schemaVersion = 1
        let configuration: String
        let clock = "DispatchTime.uptimeNanoseconds"
        let percentileMethod = "nearest-rank: sorted[ceil(p * n) - 1]"
        let firstMeasurementScope = "new Label first sizeThatFits; process/font caches may already be warm"
        let bitmapScope = "labelDrawCachedBitmap; preallocated CGContext; clips natural unlimited-line layout to bitmap bounds"
        let results: [Result]
    }

    func testRecordFixedLoadPhaseTimingsAndCacheInvariants() throws {
        #if DEBUG
            let configuration = "Debug sanity (not Release performance)"
            let repetitions = 2
            let warmup = 1
            let hotRepetitions = 3
        #else
            let configuration = "Release"
            let repetitions = 30
            let warmup = 5
            let hotRepetitions = 200
        #endif
        var results: [Result] = []
        for sample in PerformanceSamples().samples {
            var factoryCount = 0
            let provider = LYGlyphTextAttachmentViewProvider { _ in
                factoryCount += 1
                return UIView()
            }
            var phases: [Phase] = []
            var raw: [UInt64] = []
            for _ in 0 ..< repetitions {
                try autoreleasepool {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let document = try sample.makeDocument()
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    raw.append(elapsed)
                    XCTAssertEqual(document.string.utf16.count, sample.metadata.utf16Length)
                }
            }
            phases.append(phase("documentConstruction", raw, [], [], factoryCount))
            raw = []
            var before: [Int] = []
            var after: [Int] = []
            for _ in 0 ..< repetitions {
                try autoreleasepool {
                    let label = LYGlyphTextLabel(frame: .zero)
                    label.configuration = sample.configuration
                    label.document = try sample.makeDocument()
                    label.viewProvider = provider
                    label.resetLayoutMeasurementCounts()
                    before.append(label.layoutMeasurementSnapshot.layoutBuildCount)
                    let start = DispatchTime.now().uptimeNanoseconds
                    let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    raw.append(elapsed)
                    after.append(label.layoutMeasurementSnapshot.layoutBuildCount)
                    XCTAssertGreaterThan(size.height, 0)
                    XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 1)
                }
            }
            phases.append(phase("newLabelFirstSizeThatFits", raw, before, after, factoryCount))
            let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
            label.configuration = sample.configuration
            label.document = try sample.makeDocument()
            label.viewProvider = provider
            raw = []
            before = [label.layoutMeasurementSnapshot.layoutBuildCount]
            for _ in 0 ..< warmup {
                autoreleasepool {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    raw.append(elapsed)
                    XCTAssertGreaterThan(size.height, 0)
                }
            }
            after = [label.layoutMeasurementSnapshot.layoutBuildCount]
            XCTAssertEqual(after, [1])
            phases.append(phase("sameLabelWarmupSizeThatFits", raw, before, after, factoryCount))
            let stableBuilds = label.layoutMeasurementSnapshot.layoutBuildCount
            raw = []
            before = [stableBuilds]
            for _ in 0 ..< hotRepetitions {
                autoreleasepool {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    raw.append(elapsed)
                    XCTAssertGreaterThan(size.height, 0)
                }
            }
            after = [label.layoutMeasurementSnapshot.layoutBuildCount]
            XCTAssertEqual(after, before)
            phases.append(phase("sameLabelHotSizeThatFits", raw, before, after, factoryCount))

            let scale = label.traitCollection.displayScale
            let pixelWidth = Int(ceil(320 * scale))
            let pixelHeight = Int(ceil(160 * scale))
            let context = try XCTUnwrap(CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: scale, y: -scale)
            UIGraphicsPushContext(context)
            raw = []
            for _ in 0 ..< repetitions {
                autoreleasepool {
                    context.clear(label.bounds)
                    let start = DispatchTime.now().uptimeNanoseconds
                    label.draw(label.bounds)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    raw.append(elapsed)
                }
            }
            UIGraphicsPopContext()
            after = [label.layoutMeasurementSnapshot.layoutBuildCount]
            XCTAssertEqual(after, before)
            XCTAssertEqual(factoryCount, 0)
            phases.append(phase("labelDrawCachedBitmap", raw, before, after, factoryCount))
            results.append(Result(
                input: sample.metadata,
                configuration: "numberOfLines=0;wrapping=word;verticalAlignment=top;insets=0,0,0,0",
                fontName: sample.metadata.fontName, fontPointSize: 20, widthPoints: 320, scale: Double(scale),
                bitmapWidthPixels: pixelWidth, bitmapHeightPixels: pixelHeight, bitmapHeightPoints: 160,
                includesViewSubtree: false, warmupCount: warmup, phases: phases
            ))
        }
        let report = Report(configuration: configuration, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = try XCTAttachment(data: encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "performance-measurements-\(configuration.hasPrefix("Debug") ? "debug-sanity" : "release").json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testVisibleRowsKeepNaturalThreeLineHeightsAfterScrollingAwayAndReturning() throws {
        let controller = try PerformanceListController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UINavigationController(rootViewController: controller)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        var cancelledActions = 0
        let (table, originalCells, originalRows, originalButtons) = try autoreleasepool {
            window.makeKeyAndVisible()
            XCTAssertTrue(waitUntil { controller.hasAppeared && controller.viewIfLoaded?.window === window })
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UITableView }.first)
            XCTAssertTrue(table.window === window)
            controller.view.layoutIfNeeded()
            table.layoutIfNeeded()
            let cells = table.visibleCells
            let rows = cells.compactMap { table.indexPath(for: $0)?.row }
            for label in cells.flatMap({ descendants($0).compactMap { $0 as? LYGlyphTextLabel } }) {
                label.onAction = { _ in cancelledActions += 1 }
            }
            let buttons = cells.flatMap { descendants($0).compactMap { $0 as? UIButton } }
                .map { WeakMeasuredView($0) }
            XCTAssertFalse(buttons.isEmpty)
            table.scrollToRow(at: IndexPath(row: 20, section: 0), at: .top, animated: false)
            table.layoutIfNeeded()
            return (table, cells, rows, buttons)
        }
        XCTAssertTrue(waitUntil {
            originalRows.allSatisfy { row in
                let value = controller.rowDiagnostics(row)
                return value.factory == value.unmount && value.live == 0
            }
        }, "离屏行需配对卸载且实际 weak 归零")
        XCTAssertTrue(originalButtons.allSatisfy { $0.view == nil })
        XCTAssertEqual(cancelledActions, 0, "离屏清理不能发送动作")
        for cell in originalCells where table.indexPath(for: cell) == nil {
            for label in descendants(cell).compactMap({ $0 as? LYGlyphTextLabel }) {
                XCTAssertNil(label.viewProvider)
                XCTAssertNil(label.onAction)
                XCTAssertNotNil(label.document, "离屏仍保留测量输入")
            }
        }
        var observations: [[String: String]] = []
        for destination in [0, 8, 0, 12, 0, 20, 0] {
            controller.view.layoutIfNeeded()
            table.scrollToRow(at: IndexPath(row: destination, section: 0), at: .top, animated: false)
            table.layoutIfNeeded()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            for cell in table.visibleCells {
                let label = try XCTUnwrap(descendants(cell).compactMap { $0 as? LYGlyphTextLabel }.first)
                let status = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first {
                    $0.accessibilityIdentifier?.hasPrefix("performanceRowStatus") == true
                })
                let natural = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity)).height
                let statusNatural = status.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity)).height
                // UITableView 的自适应 fitting 将状态文字高度向上取整到完整 point。
                let statusFitting = ceil(statusNatural)
                let pixel = 1 / table.traitCollection.displayScale
                let separator = table.separatorStyle == .none ? 0 : pixel
                let expected = natural + statusFitting + 20 + separator
                let row = table.indexPath(for: cell)?.row ?? -1
                observations.append([
                    "destination": String(destination), "row": String(row),
                    "cellHeight": String(describing: cell.bounds.height),
                    "labelHeight": String(describing: label.bounds.height),
                    "naturalLabelHeight": String(describing: natural),
                    "naturalStatusHeight": String(describing: statusNatural),
                    "fittingStatusHeight": String(describing: statusFitting),
                    "statusHeight": String(describing: status.bounds.height),
                    "separatorHeight": String(describing: separator),
                    "expectedCellHeight": String(describing: expected),
                    "hasDocument": String(label.document != nil)
                ])
                XCTAssertNotNil(label.document, "row=\(row), destination=\(destination)")
                XCTAssertGreaterThan(natural, 40, "row=\(row), destination=\(destination)")
                XCTAssertEqual(
                    cell.bounds.height,
                    expected,
                    accuracy: pixel + 0.0001,
                    "row=\(row), destination=\(destination)"
                )
                // 两个相同 hugging 优先级的文字视图会分配最多 1pt 的 fitting 取整余量。
                XCTAssertEqual(label.bounds.height, natural, accuracy: 1.0001, "row=\(row), destination=\(destination)")
            }
        }
        let attachment = try XCTAttachment(
            data: JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "performance-visible-row-heights.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private final class WeakMeasuredView {
        weak var view: UIView?
        init(_ view: UIView) {
            self.view = view
        }
    }

    private func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while !predicate(), DispatchTime.now().uptimeNanoseconds < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func phase(
        _ name: String, _ raw: [UInt64], _ before: [Int], _ after: [Int], _ factoryCount: Int
    ) -> Phase {
        let sorted = raw.sorted()
        func percentile(_ probability: Double) -> UInt64 {
            sorted[Int(ceil(probability * Double(sorted.count))) - 1]
        }
        return Phase(
            name: name, rawNanoseconds: raw, p50Nanoseconds: percentile(0.5), p95Nanoseconds: percentile(0.95),
            layoutBuildBefore: before, layoutBuildAfter: after, factoryCount: factoryCount
        )
    }
}
