import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class PreparedLayoutTests: XCTestCase {
    private let traits = UITraitCollection(traitsFrom: [
        UITraitCollection(displayScale: 3), UITraitCollection(preferredContentSizeCategory: .large),
        UITraitCollection(userInterfaceStyle: .light)
    ])

    private func document() throws -> LYGlyphTextDocument {
        let image = LYGlyphTextAttachment(
            id: "image", image: UIImage(systemName: "star")!, size: CGSize(width: 18, height: 18)
        )
        let view = LYGlyphTextViewAttachment(id: "badge", viewID: "badge", size: CGSize(width: 24, height: 16))
        return try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: String(repeating: "预排版 Prepared layout مرحبا 😀 ", count: 30))),
            .image(image),
            .text(
                NSAttributedString(string: " 链接", attributes: [.foregroundColor: UIColor.systemBlue]),
                actionID: "link"
            ),
            .view(view),
            .text(NSAttributedString(string: String(repeating: " tail", count: 40)))
        ])
    }

    private var configuration: LYGlyphTextConfiguration {
        LYGlyphTextConfiguration(
            textContainerInset: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6), numberOfLines: 4,
            truncationToken: .init(text: "…全文", actionID: "expand")
        )
    }

    func testPrepareRunsOffMainAndMatchesSynchronousLayout() async throws {
        let doc = try document()
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: doc, configuration: configuration, width: 320, traitCollection: traits
        )
        XCTAssertFalse(prepared.wasBuiltOnMainThread)
        let reference = ResolvedText(document: doc, traits: traits).layout(
            width: 320, insets: configuration.insets, scale: 3, numberOfLines: 4,
            truncationToken: configuration.truncationToken
        )
        XCTAssertEqual(prepared.size, reference.size)
        XCTAssertEqual(prepared.layout.lines.count, reference.lines.count)
        XCTAssertEqual(prepared.layout.lines.map(\.visibleSourceRanges), reference.lines.map(\.visibleSourceRanges))
        XCTAssertEqual(prepared.layout.lines.map(\.baseline), reference.lines.map(\.baseline))
        XCTAssertEqual(prepared.layout.attachments.map(\.rect), reference.attachments.map(\.rect))
        XCTAssertEqual(prepared.layout.viewAttachments.map(\.rect), reference.viewAttachments.map(\.rect))
        XCTAssertEqual(prepared.layout.actionIndex.map(\.rects), reference.actionIndex.map(\.rects))
        XCTAssertEqual(prepared.layout.truncationToken?.text, "…全文")
        XCTAssertEqual(prepared.layout.truncationToken?.rects, reference.truncationToken?.rects)
    }

    func testLabelApplyReusesPreparedLayoutWithoutBuilding() async throws {
        let doc = try document()
        var factoryCount = 0
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        label.viewProvider = LYGlyphTextAttachmentViewProvider { _ in
            factoryCount += 1
            return UIView()
        }
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: doc, configuration: configuration, width: 320, traitCollection: label.traitCollection
        )
        label.resetLayoutMeasurementCounts()
        label.apply(prepared)
        XCTAssertTrue(label.document === doc)
        XCTAssertEqual(label.configuration, configuration)
        XCTAssertEqual(label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity)), prepared.size)
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        XCTAssertEqual(factoryCount, 0)
        // 其他宽度仍复用预排版的解析输入正常构建。
        _ = label.sizeThatFits(CGSize(width: 200, height: CGFloat.infinity))
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 1)
    }

    func testApplyBeforeJoiningWindowAdoptsOnceEnvironmentMatches() async throws {
        let doc = try document()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: doc, configuration: configuration, width: 320, traitCollection: host.traitCollection
        )
        // 模拟 cellForRow：label 尚未进入层级时 apply，加入后才布局。
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        label.apply(prepared)
        label.resetLayoutMeasurementCounts()
        host.addSubview(label)
        XCTAssertEqual(label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity)), prepared.size)
        label.layoutIfNeeded()
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        // 替换文档后放弃预排版结果。
        label.document = doc
        label.configuration = .init()
        _ = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 1)
    }

    func testEnvironmentMismatchSetsInputsButRebuilds() async throws {
        let doc = try document()
        let label = LYGlyphTextLabel(frame: .zero)
        let larger = UITraitCollection(traitsFrom: [
            label.traitCollection, UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraLarge)
        ])
        let unlimited = LYGlyphTextConfiguration()
        let prepared = await LYGlyphTextPreparedLayout.prepare(
            document: doc, configuration: unlimited, width: 320, traitCollection: larger
        )
        label.resetLayoutMeasurementCounts()
        label.apply(prepared)
        XCTAssertTrue(label.document === doc)
        let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.infinity))
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 1)
        XCTAssertLessThan(size.height, prepared.size.height)
    }

    func testConcurrentPreparesAreIndependentAndNilDocumentIsInsetsOnly() async throws {
        let documents = try (0 ..< 6).map { index in
            try LYGlyphTextDocument(attributedText: NSAttributedString(
                string: String(repeating: "第\(index)段 ", count: 20 * (index + 1))
            ))
        }
        let environment = traits
        let results = await withTaskGroup(of: (Int, CGSize).self) { group in
            for (index, doc) in documents.enumerated() {
                group.addTask {
                    let prepared = await LYGlyphTextPreparedLayout.prepare(
                        document: doc, width: 240, traitCollection: environment
                    )
                    return await (index, prepared.size)
                }
            }
            var sizes: [Int: CGSize] = [:]
            for await (index, size) in group {
                sizes[index] = size
            }
            return sizes
        }
        for (index, doc) in documents.enumerated() {
            let reference = ResolvedText(document: doc, traits: traits).layout(width: 240, insets: .zero, scale: 3)
            XCTAssertEqual(results[index], reference.size)
        }
        let empty = await LYGlyphTextPreparedLayout.prepare(
            document: nil, configuration: .init(textContainerInset: UIEdgeInsets(top: 5, left: 0, bottom: 7, right: 0)),
            width: 100, traitCollection: traits
        )
        XCTAssertEqual(empty.size, CGSize(width: 0, height: 12))
    }
}
