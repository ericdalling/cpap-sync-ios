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
