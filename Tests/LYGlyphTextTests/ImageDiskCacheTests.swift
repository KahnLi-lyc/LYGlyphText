@testable import LYGlyphText
import Network
import os
import UIKit
import XCTest

/// 回环地址上的最小 HTTP 服务器：返回带 `Cache-Control: max-age` 的 PNG，并统计到达服务器的请求数。
/// 使用真实 HTTP 协议栈，缓存命中由 URLSession 按响应头判断（自定义 URLProtocol 收不到 `cachedResponse`）。
private final class LocalImageServer: Sendable {
    private let listener: NWListener
    private let payload: Data
    let requests = OSAllocatedUnfairLock(initialState: 0)

    init(payload: Data) throws {
        self.payload = payload
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// 启动并等待系统分配端口；3 秒内未就绪返回 nil。
    func start() async throws -> UInt16? {
        listener.newConnectionHandler = { [self] connection in serve(connection) }
        listener.start(queue: .global())
        for _ in 0 ..< 150 {
            if let port = listener.port, port.rawValue != 0 { return port.rawValue }
            try await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, _, _ in
            guard data?.isEmpty == false else { return connection.cancel() }
            requests.withLock { $0 += 1 }
            let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(payload.count)\r\n"
                + "Cache-Control: max-age=3600\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

@MainActor
final class ImageDiskCacheTests: XCTestCase {
    private var directory: URL!
    private var server: LocalImageServer!
    private var port: UInt16 = 0

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }.pngData() ?? Data()
        server = try LocalImageServer(payload: png)
        let started = try await server.start()
        port = try XCTUnwrap(started, "回环服务器未就绪")
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func loader(capacity: Int) -> LYGlyphTextURLSessionImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        return LYGlyphTextURLSessionImageLoader(
            configuration: configuration, diskCacheCapacity: capacity, diskCacheDirectory: directory
        )
    }

    private func load(_ loader: LYGlyphTextURLSessionImageLoader, _ url: URL) {
        let done = expectation(description: "load")
        _ = loader.loadImage(from: url, targetSize: CGSize(width: 16, height: 16), scale: 2) { result in
            if case .failure = result { XCTFail("加载失败") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    private func count(_: URL) -> Int {
        server.requests.withLock { $0 }
    }

    private func url(_ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(name)"))
    }

    /// URLCache 异步读写磁盘；等待条目真实出现或消失，而不是固定延时。
    private func waitForDiskEntry(_ cache: URLCache, _ url: URL, exists: Bool = true) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if (cache.cachedResponse(for: URLRequest(url: url)) != nil) == exists { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    func testDiskCacheServesAfterMemoryIsClearedAndRemoveAllForcesReload() throws {
        let url = try url("a.png")
        let loader = loader(capacity: 10 * 1024 * 1024)
        let cache = try XCTUnwrap(loader.urlCache)
        XCTAssertFalse(cache === URLCache.shared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path), "应创建缺失的缓存目录")
        load(loader, url)
        XCTAssertEqual(count(url), 1)
        XCTAssertTrue(waitForDiskEntry(cache, url))
        loader.removeMemoryCachedImages()
        load(loader, url)
        XCTAssertEqual(count(url), 1, "内存清空后应由磁盘缓存提供")
        loader.removeAllCachedImages()
        XCTAssertTrue(waitForDiskEntry(cache, url, exists: false))
        load(loader, url)
        XCTAssertEqual(count(url), 2)
    }

    func testZeroCapacityDisablesDiskCache() throws {
        let url = try url("b.png")
        let loader = loader(capacity: 0)
        XCTAssertNil(loader.urlCache)
        load(loader, url)
        loader.removeMemoryCachedImages()
        load(loader, url)
        XCTAssertEqual(count(url), 2)
        XCTAssertNil(URLCache.shared.cachedResponse(for: URLRequest(url: url)))
    }
}
