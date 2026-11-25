import XCTest
@testable import CPAPSyncCore

private struct FixtureTransport: CardTransport {
    let responses: [String: Data]
    func get(_ url: URL) async throws -> Data {
        guard let data = responses[url.absoluteString] else { throw CardError.badResponse }
        return data
    }
}

final class CoreTests: XCTestCase {
    func testParser() throws {
        let html = """
        <html><pre>
        <a href="/dir?dir=A:%5CDATALOG">DATALOG</a>
        <a href='download?file=A:%5CSTR.edf'>STR.edf</a>
        <a href="download?file=A:%5Chello%20world.edf">hello world.edf</a>
        </pre></html>
        """
        let entries = try DirectoryParser.parse(html, relativeTo: CardAddress.root)
        XCTAssertEqual(entries.map(\.name), ["DATALOG", "STR.edf", "hello world.edf"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false, false])
    }

    func testUnsafeAndMalformed() {
        for html in ["<html>error</html>",
                     "<pre><a href='http://example.org/download?file=x'>x</a></pre>",
                     "<pre><a href='/download?file=x'>../escape</a></pre>",
                     "<pre><a href='/config?x=y'>x</a></pre>",
                     "<pre><a href='/download?file=x'>x</a><a href='/download?file=y'>X</a></pre>"] {
            XCTAssertThrowsError(try DirectoryParser.parse(html, relativeTo: CardAddress.root))
        }
    }

    func testSkipsCardWifiConfiguration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dataURL = "http://192.168.4.1/download?file=A:%5CSTR.edf"
        let responses = [
            CardAddress.root.absoluteString: Data("<pre><a href='/download?file=A:%5Cezshare.cfg'>ezshare.cfg</a><a href='/download?file=A:%5CSTR.edf'>STR.edf</a></pre>".utf8),
            dataURL: Data([1, 2, 3])
        ]
        let report = try await CardSync(client: EZShareClient(transport: FixtureTransport(responses: responses))).sync(to: folder)
        XCTAssertEqual(report.files, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ezshare.cfg").path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("STR.edf")), Data([1, 2, 3]))
    }

    func testRecursiveSyncAndRefresh() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = CardAddress.root.absoluteString
        let dir = "http://192.168.4.1/dir?dir=A:%5CDATALOG"
        let file = "http://192.168.4.1/download?file=A:%5CSTR.edf"
        let nested = "http://192.168.4.1/download?file=A:%5CDATALOG%5Csample.edf"
        let bytes = Data([0, 1, 255, 9])
        var responses = [
            root: Data("<pre><a href='/dir?dir=A:%5CDATALOG'>DATALOG</a><a href='/download?file=A:%5CSTR.edf'>STR.edf</a></pre>".utf8),
            dir: Data("<pre><a href='/download?file=A:%5CDATALOG%5Csample.edf'>sample.edf</a></pre>".utf8),
            file: bytes, nested: bytes
        ]
        func run(_ responses: [String: Data]) async throws -> SyncReport {
            try await CardSync(client: EZShareClient(transport: FixtureTransport(responses: responses))).sync(to: folder)
        }
        let first = try await run(responses)
        XCTAssertEqual(first.changed, 2)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("DATALOG/sample.edf")), bytes)
        let second = try await run(responses)
        XCTAssertEqual(second.unchanged, 2)
        responses[file] = Data([4, 5])
        let third = try await run(responses)
        XCTAssertEqual(third.changed, 1)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("STR.edf")), Data([4, 5]))
    }
}

private actor RetryFixture: CardTransport {
    private var attempts = 0
    private let failPermanently: Bool
    init(failPermanently: Bool = false) { self.failPermanently = failPermanently }
    func get(_ url: URL) async throws -> Data {
        attempts += 1
        if failPermanently { throw CardError.invalidListing }
        if attempts < 3 { throw URLError(.timedOut) }
        return Data([7, 8])
    }
    func count() -> Int { attempts }
}

extension CoreTests {
    func testRetriesTimedOutRequests() async throws {
        let transport = RetryFixture()
        let entry = CardEntry(name: "test.edf", url: URL(string: "http://192.168.4.1/download?file=test.edf")!, isDirectory: false)
        let actual = try await EZShareClient(transport: transport).download(entry)
        XCTAssertEqual(actual, Data([7, 8]))
        let count = await transport.count()
        XCTAssertEqual(count, 3)
    }

    func testDoesNotRetryPermanentErrors() async {
        let transport = RetryFixture(failPermanently: true)
        let entry = CardEntry(name: "test.edf", url: URL(string: "http://192.168.4.1/download?file=test.edf")!, isDirectory: false)
        do {
            _ = try await EZShareClient(transport: transport).download(entry)
            XCTFail("Expected failure")
        } catch { }
        let count = await transport.count()
        XCTAssertEqual(count, 1)
    }

    func testInterruptedSyncPreservesSavedFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let responses = [
            CardAddress.root.absoluteString: Data("<pre><a href='/download?file=first.edf'>first.edf</a><a href='/download?file=missing.edf'>missing.edf</a></pre>".utf8),
            "http://192.168.4.1/download?file=first.edf": Data([4, 5])
        ]
        do {
            _ = try await CardSync(client: EZShareClient(transport: FixtureTransport(responses: responses))).sync(to: folder)
            XCTFail("Expected failure")
        } catch let error as SyncFailure {
            XCTAssertTrue(error.localizedDescription.contains("missing.edf"))
        }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("first.edf")), Data([4, 5]))
    }

    func testTwoDownloadMode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = EZShareClient(transport: FixtureTransport(responses: [
            CardAddress.root.absoluteString: Data("<pre><a href='/download?file=1.edf'>1.edf</a><a href='/download?file=2.edf'>2.edf</a></pre>".utf8),
            "http://192.168.4.1/download?file=1.edf": Data([1]),
            "http://192.168.4.1/download?file=2.edf": Data([2])
        ]))
        let report = try await CardSync(client: client).sync(to: folder, options: SyncOptions(concurrentDownloads: 2))
        XCTAssertEqual(report.files, 2)
    }
}


// Listing metadata is intentionally absent from older fixture HTML, causing
// a full refresh for backward compatibility.
private actor CountingTransport: CardTransport {
    private var responses: [String: Data]
    private var counts: [String: Int] = [:]
    init(responses: [String: Data]) { self.responses = responses }
    func set(_ url: String, bytes: Data) { responses[url] = bytes }
    func get(_ url: URL) async throws -> Data {
        counts[url.absoluteString, default: 0] += 1
        guard let data = responses[url.absoluteString] else { throw CardError.badResponse }
        return data
    }
    func calls(_ url: String) -> Int { counts[url, default: 0] }
}

extension CoreTests {
    private func listing(_ size: String = "4B", _ date: String = "2021-11- 6 16:17: 0") -> Data {
        Data("<pre>\n\(date) \(size) <a href='/dir?dir=A:%5CDATALOG'>DATALOG</a>\n</pre>".utf8)
    }

    func testIncrementalSkipsStableDatalogAndRefreshesChangedMetadata() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: IncrementalIndex.location(for: folder))
        }
        let dir = "http://192.168.4.1/dir?dir=A:%5CDATALOG"
        let file = "http://192.168.4.1/download?file=A:%5CDATALOG%5Csample.edf"
        let transport = CountingTransport(responses: [
            CardAddress.root.absoluteString: Data("<pre><a href='/dir?dir=A:%5CDATALOG'>DATALOG</a></pre>".utf8),
            dir: Data("<pre>\n2021-11- 6 16:17: 0 4B <a href='/download?file=A:%5CDATALOG%5Csample.edf'>sample.edf</a>\n</pre>".utf8),
            file: Data([1,2,3,4])
        ])
        let sync = CardSync(client: EZShareClient(transport: transport))
        let first = try await sync.sync(to: folder)
        XCTAssertEqual(first.changed, 1)
        let callCount1 = await transport.calls(file)
        XCTAssertEqual(callCount1, 1)
        let second = try await sync.sync(to: folder)
        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(second.bytes, 0)
        let callCount1 = await transport.calls(file)
        XCTAssertEqual(callCount1, 1)
        await transport.set(dir, bytes: Data("<pre>\n2021-11- 7 16:17: 0 4B <a href='/download?file=A:%5CDATALOG%5Csample.edf'>sample.edf</a>\n</pre>".utf8))
        await transport.set(file, bytes: Data([9,8,7,6]))
        let third = try await sync.sync(to: folder)
        XCTAssertEqual(third.changed, 1)
        let callCount2 = await transport.calls(file)
        XCTAssertEqual(callCount2, 2)
        let forced = try await sync.sync(to: folder, options: SyncOptions(forceFullRefresh: true))
        XCTAssertEqual(forced.skipped, 0)
        let callCount3 = await transport.calls(file)
        XCTAssertEqual(callCount3, 3)
    }

    func testIncrementalMissesDoNotSkipAndLocalMutationsTriggerRefresh() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: IncrementalIndex.location(for: folder))
        }
        let url = "http://192.168.4.1/download?file=A:%5CDATALOG%5Csample.edf"
        let dir = "http://192.168.4.1/dir?dir=A:%5CDATALOG"
        let response = Data("<pre>\n2021-11- 6 16:17: 0 4B <a href='/download?file=A:%5CDATALOG%5Csample.edf'>sample.edf</a>\n</pre>".utf8)
        let transport = CountingTransport(responses: [
            CardAddress.root.absoluteString: Data("<pre><a href='/dir?dir=A:%5CDATALOG'>DATALOG</a></pre>".utf8),
            dir: response, url: Data([1,2,3,4])
        ])
        let sync = CardSync(client: EZShareClient(transport: transport))
        _ = try await sync.sync(to: folder)
        let local = folder.appendingPathComponent("DATALOG/sample.edf")
        try Data([1,2,3]).write(to: local, options: .atomic)
        let repaired = try await sync.sync(to: folder)
        XCTAssertEqual(repaired.changed, 1)
        XCTAssertEqual(repaired.skipped, 0)
        await transport.set(dir, bytes: Data("<pre><a href='/download?file=A:%5CDATALOG%5Csample.edf'>sample.edf</a></pre>".utf8))
        let legacy = try await sync.sync(to: folder)
        XCTAssertEqual(legacy.skipped, 0)
        let callCount3 = await transport.calls(url)
        XCTAssertEqual(callCount3, 3)
    }

    func testParsesEzshareTimestampAndRejectsMalformedDate() throws {
        let good = "<pre>\n2021-11- 6 16:17: 0 7750KB <a href='/download?file=x.edf'>x.edf</a></pre>"
        XCTAssertNotNil(try DirectoryParser.parse(good, relativeTo: CardAddress.root)[0].stamp)
        let malformed = "<pre>\n2021-13- 6 16:17: 0 7750KB <a href='/download?file=x.edf'>x.edf</a></pre>"
        XCTAssertNil(try DirectoryParser.parse(malformed, relativeTo: CardAddress.root)[0].stamp)
    }
}
