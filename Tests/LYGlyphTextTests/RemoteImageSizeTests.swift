@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class RemoteImageSizeTests: XCTestCase {
    private final class Loader: LYGlyphTextImageLoading {
        final class Task: LYGlyphTextImageLoadingTask {
            var isCancelled = false

            func cancel() {
                isCancelled = true
            }
        }

        var completions: [@MainActor (Result<UIImage, any Error>) -> Void] = []
        var tasks: [Task] = []
        var synchronous: UIImage?

        func loadImage(
            from url: URL, targetSize: CGSize, scale: CGFloat,
            completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
        ) -> any LYGlyphTextImageLoadingTask {
            let task = Task()
            if let synchronous {
                completion(.success(synchronous))
                return task
            }
            completions.append(completion)
            tasks.append(task)
            return task
        }
    }

    private struct Failure: Error {}

    private func image(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in }
    }

    private func document(size: CGSize = CGSize(width: 40, height: 40)) throws -> LYGlyphTextDocument {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/cover.png"))
        return try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "封面 ", attributes: [.font: UIFont.systemFont(ofSize: 17)])),
            .remoteImage(.init(id: "cover", url: url, size: size, alternativeText: "封面图")),
            .text(NSAttributedString(string: " 详情"), actionID: "detail")
        ])
    }

    private func hosted(_ label: LYGlyphTextLabel) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        label.frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        window.addSubview(label)
        label.layoutIfNeeded()
        return window
    }

    func testLoadCallbackReportsImageSizeOnlyForSuccess() throws {
        let loader = Loader()
        let label = LYGlyphTextLabel(frame: .zero)
        var events: [(String, CGSize)] = []
        label.onRemoteImageLoad = { events.append(($0, $1)) }
        label.imageLoader = loader
        label.document = try document()
        let window = hosted(label)
        loader.completions[0](.success(image(CGSize(width: 300, height: 150))))
        XCTAssertEqual(events.map(\.0), ["cover"])
        XCTAssertEqual(events.first?.1, CGSize(width: 300, height: 150))
        label.reloadAttachments()
        label.layoutIfNeeded()
        loader.completions[1](.failure(Failure()))
        XCTAssertEqual(events.count, 1)
        label.reloadAttachments()
        label.layoutIfNeeded()
        let pending = loader.completions[2]
        label.removeFromSuperview()
        XCTAssertTrue(try XCTUnwrap(loader.tasks.last).isCancelled)
        pending(.success(image(CGSize(width: 10, height: 10))))
        XCTAssertEqual(events.count, 1)
        loader.synchronous = image(CGSize(width: 64, height: 32))
        window.addSubview(label)
        label.layoutIfNeeded()
        XCTAssertEqual(events.last?.1, CGSize(width: 64, height: 32))
        label.clearForDismantle()
        XCTAssertNil(label.onRemoteImageLoad)
    }

    func testReplacingRemoteImageSizeRebuildsOnlyThatAttachment() throws {
        let original = try document()
        let resized = try original.replacingRemoteImageSize(id: "cover", size: CGSize(width: 300, height: 150))
        XCTAssertFalse(original === resized)
        XCTAssertEqual(original.remoteImages["cover"]?.size, CGSize(width: 40, height: 40))
        XCTAssertEqual(resized.remoteImages["cover"]?.size, CGSize(width: 300, height: 150))
        XCTAssertEqual(resized.remoteImages["cover"]?.alternativeText, "封面图")
        XCTAssertEqual(resized.string, original.string)
        XCTAssertEqual(resized.actions.map(\.actionID), ["detail"])
        XCTAssertEqual(resized.actions.map(\.range), original.actions.map(\.range))
        XCTAssertEqual(resized.styleRuns.count, original.styleRuns.count)
        let traits = UITraitCollection(displayScale: 2)
        let before = ResolvedText(document: original, traits: traits).layout(width: 360, insets: .zero, scale: 2)
        let after = ResolvedText(document: resized, traits: traits).layout(width: 360, insets: .zero, scale: 2)
        XCTAssertGreaterThan(after.size.height, before.size.height + 100)
        XCTAssertEqual(after.viewAttachments.first?.rect.size, CGSize(width: 300, height: 150))
        XCTAssertThrowsError(try original.replacingRemoteImageSize(id: "missing", size: CGSize(width: 1, height: 1))) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unknownAttachmentID(id: "missing"))
        }
        for size in [CGSize(width: 0, height: 10), CGSize(width: CGFloat.nan, height: 10)] {
            XCTAssertThrowsError(try original.replacingRemoteImageSize(id: "cover", size: size)) {
                XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentSize(id: "cover"))
            }
        }
    }

    func testResizedDocumentMountsAtNewSizeAndRequestsAgain() throws {
        let loader = Loader()
        let label = LYGlyphTextLabel(frame: .zero)
        label.imageLoader = loader
        label.document = try document()
        let window = hosted(label)
        let first = try XCTUnwrap(label.subviews.flatMap(\.subviews).compactMap { $0 as? RemoteImageView }.first)
        XCTAssertEqual(first.frame.size, CGSize(width: 40, height: 40))
        label.document = try XCTUnwrap(label.document).replacingRemoteImageSize(
            id: "cover", size: CGSize(width: 120, height: 60)
        )
        label.layoutIfNeeded()
        let second = try XCTUnwrap(label.subviews.flatMap(\.subviews).compactMap { $0 as? RemoteImageView }.first)
        XCTAssertEqual(second.frame.size, CGSize(width: 120, height: 60))
        XCTAssertEqual(loader.completions.count, 2)
        XCTAssertTrue(loader.tasks[0].isCancelled)
        withExtendedLifetime(window) {}
    }
}
