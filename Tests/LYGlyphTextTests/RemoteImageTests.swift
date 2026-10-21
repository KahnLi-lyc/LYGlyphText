import ImageIO
@testable import LYGlyphText
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest

/// 本地 URLProtocol 桩：按 URL 返回预设状态码与数据，并统计实际请求数；测试不访问网络。
private final class StubURLProtocol: URLProtocol {
    struct Response: Sendable {
        let status: Int
        let data: Data
    }

    static let responses = OSAllocatedUnfairLock(initialState: [String: Response]())
    static let requestCounts = OSAllocatedUnfairLock(initialState: [String: Int]())

    static func reset() {
        responses.withLock { $0.removeAll() }
        requestCounts.withLock { $0.removeAll() }
    }

    static func count(_ url: URL) -> Int {
        requestCounts.withLock { $0[url.absoluteString, default: 0] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requestCounts.withLock { $0[url.absoluteString, default: 0] += 1 }
        let response = Self.responses.withLock { $0[url.absoluteString] } ?? Response(status: 404, data: Data())
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)
        if let http { client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class RemoteImageTests: XCTestCase {
    private final class MockLoader: LYGlyphTextImageLoading {
        final class Task: LYGlyphTextImageLoadingTask {
            var isCancelled = false

            func cancel() {
                isCancelled = true
            }
        }

        struct Request {
            let url: URL
            let size: CGSize
            let scale: CGFloat
            let task: Task
            let completion: @MainActor (Result<UIImage, any Error>) -> Void
        }

        var requests: [Request] = []
        var synchronousImage: UIImage?

        func loadImage(
            from url: URL, targetSize: CGSize, scale: CGFloat,
            completion: @escaping @MainActor (Result<UIImage, any Error>) -> Void
        ) -> any LYGlyphTextImageLoadingTask {
            let task = Task()
            if let synchronousImage {
                completion(.success(synchronousImage))
                return task
            }
            requests.append(.init(url: url, size: targetSize, scale: scale, task: task, completion: completion))
            return task
        }
    }

    private struct Failure: Error {}

    private let url = URL(string: "https://example.invalid/avatar.png")!
    private let placeholder = UIImage(systemName: "photo")!
    private let failure = UIImage(systemName: "xmark")!

    private func solid(_ color: UIColor, size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func remote(
        id: String = "avatar",
        size: CGSize = CGSize(width: 30, height: 20)
    ) -> LYGlyphTextRemoteImageAttachment {
        .init(id: id, url: url, size: size, placeholder: placeholder, failureImage: failure, alternativeText: "头像")
    }

    private func document(_ attachment: LYGlyphTextRemoteImageAttachment? = nil) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(segments: [
            .text(NSAttributedString(string: "作者 ", attributes: [.font: UIFont.systemFont(ofSize: 20)])),
            .remoteImage(attachment ?? remote()),
            .text(NSAttributedString(string: " 发布了动态", attributes: [.font: UIFont.systemFont(ofSize: 20)]))
        ])
    }

    private func hosted(_ label: LYGlyphTextLabel) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        label.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        window.addSubview(label)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        return window
    }

    private func remoteViews(_ label: LYGlyphTextLabel) -> [RemoteImageView] {
        func collect(_ view: UIView) -> [RemoteImageView] {
            view.subviews.flatMap { ($0 as? RemoteImageView).map { [$0] } ?? collect($0) }
        }
        return collect(label)
    }

    // MARK: - Document

    func testDocumentValidatesRemoteImagesWithOtherAttachments() throws {
        let doc = try document()
        XCTAssertEqual(doc.remoteImages["avatar"]?.url, url)
        XCTAssertEqual(doc.viewAttachments[3]?.viewID, LYGlyphTextDocument.remoteImageViewID)
        XCTAssertEqual(doc.viewAttachments[3]?.isInteractive, false)
        let text = NSAttributedString(string: "a\u{FFFC}b")
        let image = LYGlyphTextAttachment(id: "avatar", image: placeholder, size: CGSize(width: 10, height: 10))
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{FFFC}"), attachments: [0: image],
            remoteImages: [1: remote()]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .duplicateAttachmentID(id: "avatar")) }
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: text, remoteImages: [0: remote()])) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: 0))
        }
        let view = LYGlyphTextViewAttachment(id: "v", viewID: "badge", size: CGSize(width: 10, height: 10))
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: text, viewAttachments: [1: view], remoteImages: [1: remote()]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .conflictingAttachmentLocation(location: 1)) }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: text, remoteImages: [1: remote(size: CGSize(width: 0, height: 10))]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentSize(id: "avatar")) }
    }

    // MARK: - Label lifecycle

    func testMeasurementNeverRequestsAndVisibleMountRequestsOnce() throws {
        let loader = MockLoader()
        let label = LYGlyphTextLabel(frame: .zero)
        label.imageLoader = loader
        label.document = try document()
        _ = label.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        _ = label.intrinsicContentSize
        XCTAssertTrue(loader.requests.isEmpty)
        let window = hosted(label)
        XCTAssertEqual(loader.requests.count, 1)
        let request = try XCTUnwrap(loader.requests.first)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.size, CGSize(width: 30, height: 20))
        XCTAssertEqual(request.scale, window.traitCollection.displayScale > 0 ? window.traitCollection.displayScale : 1)
        let view = try XCTUnwrap(remoteViews(label).first)
        XCTAssertEqual(view.frame.size, CGSize(width: 30, height: 20))
        XCTAssertTrue(view.image === placeholder)
        XCTAssertFalse(view.isUserInteractionEnabled)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        XCTAssertEqual(loader.requests.count, 1)
    }

    func testSuccessAndFailureResultsUpdateImage() throws {
        let loader = MockLoader()
        let label = LYGlyphTextLabel(frame: .zero)
        label.imageLoader = loader
        label.document = try document()
        let window = hosted(label)
        let loaded = solid(.red)
        loader.requests[0].completion(.success(loaded))
        XCTAssertTrue(remoteViews(label).first?.image === loaded)
        label.reloadAttachments()
        label.layoutIfNeeded()
        XCTAssertEqual(loader.requests.count, 2)
        loader.requests[1].completion(.failure(Failure()))
        XCTAssertTrue(remoteViews(label).first?.image === failure)
        withExtendedLifetime(window) {}
    }

    func testHidingReplacingAndLoaderChangeCancelPendingRequests() throws {
        let loader = MockLoader()
        let label = LYGlyphTextLabel(frame: .zero)
        label.imageLoader = loader
        label.document = try document()
        let window = hosted(label)
        let first = try XCTUnwrap(loader.requests.first)
        let firstView = try XCTUnwrap(remoteViews(label).first)
        label.removeFromSuperview()
        XCTAssertTrue(first.task.isCancelled)
        XCTAssertNil(firstView.superview)
        // 取消之后迟到的回调不能改变已卸载视图。
        first.completion(.success(solid(.red)))
        XCTAssertTrue(firstView.image === placeholder)

        window.addSubview(label)
        label.layoutIfNeeded()
        XCTAssertEqual(loader.requests.count, 2)
        label.document = try document(remote(id: "other"))
        XCTAssertTrue(loader.requests[1].task.isCancelled)
        label.layoutIfNeeded()
        XCTAssertEqual(loader.requests.count, 3)
        let replacement = MockLoader()
        label.imageLoader = replacement
        XCTAssertTrue(loader.requests[2].task.isCancelled)
        label.layoutIfNeeded()
        XCTAssertEqual(replacement.requests.count, 1)
    }

    func testSynchronousCacheResultAndMissingLoader() throws {
        let cached = solid(.blue)
        let loader = MockLoader()
        loader.synchronousImage = cached
        let label = LYGlyphTextLabel(frame: .zero)
        label.imageLoader = loader
        label.document = try document()
        let window = hosted(label)
        XCTAssertTrue(remoteViews(label).first?.image === cached)

        let bare = LYGlyphTextLabel(frame: .zero)
        bare.document = try document()
        window.addSubview(bare)
        bare.frame = CGRect(x: 0, y: 100, width: 300, height: 80)
        bare.layoutIfNeeded()
        XCTAssertTrue(remoteViews(bare).first?.image === placeholder)
    }

    func testHostProviderOnlyReceivesHostViewsAndAccessibilityUsesAlternativeText() throws {
        var made: [String] = []
        let provider = LYGlyphTextAttachmentViewProvider { attachment in
            made.append(attachment.id)
            return UIView()
        }
        let badge = LYGlyphTextViewAttachment(id: "badge", viewID: "badge", size: CGSize(width: 12, height: 12))
        let doc = try LYGlyphTextDocument(segments: [.remoteImage(remote()), .view(badge)])
        let label = LYGlyphTextLabel(frame: .zero)
        label.viewProvider = provider
        label.imageLoader = MockLoader()
        label.document = doc
        let window = hosted(label)
        XCTAssertEqual(made, ["badge"])
        XCTAssertEqual(remoteViews(label).count, 1)
        let semantics = TextAccessibility(
            layout: label.measuredLayout(width: label.bounds.width), document: doc, bounds: label.bounds,
            configuration: label.configuration, nativeViews: [:]
        )
        XCTAssertTrue(semantics.items.contains {
            if case let .text(entry) = $0 { return entry.label == "头像" }
            return false
        })
        withExtendedLifetime(window) {}
    }

    func testSwiftUIViewPassesLoaderAndDismantleReleasesIt() throws {
        let loader = MockLoader()
        let view = try LYGlyphTextView(document: document(), imageLoader: loader)
        let controller = UIHostingController(rootView: view.frame(width: 300, height: 80))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        func find(_ view: UIView) -> LYGlyphTextLabel? {
            (view as? LYGlyphTextLabel) ?? view.subviews.lazy.compactMap(find).first
        }
        let label = try XCTUnwrap(find(controller.view))
        XCTAssertTrue(label.imageLoader === loader)
        label.clearForDismantle()
        XCTAssertNil(label.imageLoader)
        withExtendedLifetime(window) {}
    }

    // MARK: - Built-in loader

    private func makeLoader() -> LYGlyphTextURLSessionImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LYGlyphTextURLSessionImageLoader(configuration: configuration)
    }

    private func load(
        _ loader: LYGlyphTextURLSessionImageLoader, _ url: URL, size: CGSize = CGSize(width: 20, height: 20)
    ) -> Result<UIImage, any Error>? {
        let done = expectation(description: "load")
        var result: Result<UIImage, any Error>?
        _ = loader.loadImage(from: url, targetSize: size, scale: 2) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func pngData(_ size: CGSize) -> Data {
        solid(.red, size: size).pngData() ?? Data()
    }

    func testBuiltInLoaderMergesRequestsCachesAndDownsamples() throws {
        StubURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://stub.invalid/merge.png"))
        let data = pngData(CGSize(width: 400, height: 400))
        StubURLProtocol.responses.withLock { $0[url.absoluteString] = .init(status: 200, data: data) }
        let loader = makeLoader()
        let both = expectation(description: "both")
        both.expectedFulfillmentCount = 2
        var images: [UIImage] = []
        for _ in 0 ..< 2 {
            _ = loader.loadImage(from: url, targetSize: CGSize(width: 20, height: 20), scale: 2) {
                if case let .success(image) = $0 { images.append(image) }
                both.fulfill()
            }
        }
        XCTAssertEqual(loader.activeRequestCount, 1)
        wait(for: [both], timeout: 5)
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images[0] === images[1])
        XCTAssertEqual(StubURLProtocol.count(url), 1)
        XCTAssertEqual(try XCTUnwrap(images.first).size, CGSize(width: 20, height: 20))
        XCTAssertEqual(try XCTUnwrap(images.first).scale, 2)
        // 同尺寸命中内存缓存：同步回调且不再请求。
        var synchronous = false
        _ = loader.loadImage(from: url, targetSize: CGSize(width: 20, height: 20), scale: 2) { _ in synchronous = true }
        XCTAssertTrue(synchronous)
        XCTAssertEqual(StubURLProtocol.count(url), 1)
        XCTAssertEqual(loader.activeRequestCount, 0)
    }

    func testBuiltInLoaderCancellationSuppressesCallback() throws {
        StubURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://stub.invalid/cancel.png"))
        let data = pngData(CGSize(width: 8, height: 8))
        StubURLProtocol.responses.withLock { $0[url.absoluteString] = .init(status: 200, data: data) }
        let loader = makeLoader()
        let never = expectation(description: "cancelled callback")
        never.isInverted = true
        let task = loader
            .loadImage(from: url, targetSize: CGSize(width: 8, height: 8), scale: 1) { _ in never.fulfill() }
        task.cancel()
        task.cancel()
        XCTAssertEqual(loader.activeRequestCount, 0)
        wait(for: [never], timeout: 0.5)
    }

    func testBuiltInLoaderReportsStatusAndUndecodableData() throws {
        StubURLProtocol.reset()
        let missing = try XCTUnwrap(URL(string: "https://stub.invalid/missing.png"))
        let broken = try XCTUnwrap(URL(string: "https://stub.invalid/broken.png"))
        StubURLProtocol.responses
            .withLock { $0[broken.absoluteString] = .init(status: 200, data: Data("not image".utf8)) }
        let loader = makeLoader()
        guard case let .failure(first)? = load(loader, missing) else { return XCTFail("应失败") }
        XCTAssertEqual(first as? LYGlyphTextImageLoadingError, .unacceptableStatusCode(404))
        guard case let .failure(second)? = load(loader, broken) else { return XCTFail("应失败") }
        XCTAssertEqual(second as? LYGlyphTextImageLoadingError, .undecodableData)
    }

    func testAnimatedGIFDecodesFramesAndDuration() throws {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, 3, nil
        ))
        for color in [UIColor.red, .green, .blue] {
            let frame = try XCTUnwrap(solid(color, size: CGSize(width: 10, height: 10)).cgImage)
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = try XCTUnwrap(LYGlyphTextURLSessionImageLoader.decode(
            data as Data, scale: 1, maxPixelSize: 0, frameLimit: 300
        ))
        XCTAssertEqual(image.images?.count, 3)
        XCTAssertEqual(image.duration, 0.15, accuracy: 0.02)
        let limited = try XCTUnwrap(LYGlyphTextURLSessionImageLoader.decode(
            data as Data, scale: 1, maxPixelSize: 0, frameLimit: 2
        ))
        XCTAssertEqual(limited.images?.count, 2)
    }
}
