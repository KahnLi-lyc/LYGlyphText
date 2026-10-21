@testable import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

/// 比较新 Label 首次同步测量与“后台预排版＋apply 后首次测量”在主线程上的耗时；只记录数据，不设阈值。
@MainActor
final class PreparedLayoutMeasurementTests: XCTestCase {
    private struct Row: Encodable {
        let input: String
        let synchronousFirstSizeThatFitsNanoseconds: [UInt64]
        let preparedApplyAndSizeThatFitsNanoseconds: [UInt64]
        let backgroundPrepareWallNanoseconds: [UInt64]
        let synchronousP50: UInt64
        let preparedP50: UInt64
    }

    private struct Report: Encodable {
        let configuration: String
        let clock = "DispatchTime.uptimeNanoseconds"
        let percentile = "nearest-rank p50: sorted[ceil(0.5 * n) - 1]"
        let scope = "main-thread cost only; background prepare wall time recorded separately"
        let rows: [Row]
    }

    private func p50(_ values: [UInt64]) -> UInt64 {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[Int((0.5 * Double(sorted.count)).rounded(.up)) - 1]
    }

    func testPreparedLayoutMovesFirstMeasurementOffMainThread() async throws {
        #if DEBUG
            let configuration = "Debug sanity (not Release performance)"
            let repetitions = 2
        #else
            let configuration = "Release"
            let repetitions = 30
        #endif
        var rows: [Row] = []
        for sample in PerformanceSamples().samples {
            var synchronous: [UInt64] = []
            var prepared: [UInt64] = []
            var background: [UInt64] = []
            for _ in 0 ..< repetitions {
                let label = LYGlyphTextLabel(frame: .zero)
                label.configuration = sample.configuration
                label.document = try sample.makeDocument()
                label.resetLayoutMeasurementCounts()
                var start = DispatchTime.now().uptimeNanoseconds
                _ = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
                synchronous.append(DispatchTime.now().uptimeNanoseconds - start)
                XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 1)

                let target = LYGlyphTextLabel(frame: .zero)
                let document = try sample.makeDocument()
                start = DispatchTime.now().uptimeNanoseconds
                let result = await LYGlyphTextPreparedLayout.prepare(
                    document: document, configuration: sample.configuration, width: 320,
                    traitCollection: target.traitCollection
                )
                background.append(DispatchTime.now().uptimeNanoseconds - start)
                XCTAssertFalse(result.wasBuiltOnMainThread)
                target.resetLayoutMeasurementCounts()
                start = DispatchTime.now().uptimeNanoseconds
                target.apply(result)
                let size = target.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
                prepared.append(DispatchTime.now().uptimeNanoseconds - start)
                XCTAssertEqual(target.layoutMeasurementSnapshot.layoutBuildCount, 0)
                XCTAssertEqual(size, result.size)
            }
            rows.append(Row(
                input: sample.metadata.id, synchronousFirstSizeThatFitsNanoseconds: synchronous,
                preparedApplyAndSizeThatFitsNanoseconds: prepared, backgroundPrepareWallNanoseconds: background,
                synchronousP50: p50(synchronous), preparedP50: p50(prepared)
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = try XCTAttachment(
            data: encoder.encode(Report(configuration: configuration, rows: rows)), uniformTypeIdentifier: "public.json"
        )
        attachment.name = "prepared-layout-\(configuration.hasPrefix("Debug") ? "debug-sanity" : "release").json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
