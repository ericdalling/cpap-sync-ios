import Foundation

public struct SyncReport: Sendable, Equatable {
    public var files = 0
    public var changed = 0
    public var unchanged = 0
    public var skipped = 0
    public var bytes = 0
    public var activeFile: String?
    public var elapsed: TimeInterval = 0
    public var discoverySeconds: TimeInterval = 0
    public var downloadSeconds: TimeInterval = 0
    public var localSeconds: TimeInterval = 0
    public var indexSeconds: TimeInterval = 0
    public var directories = 0
    public var metadataPresent = 0
    public var metadataMissing = 0
    public var slowestDownload: TimeInterval = 0
    public var downloaded: Int { files - skipped }
    public var effectiveKBps: Double { elapsed > 0 ? Double(bytes) / elapsed / 1000 : 0 }
    public var diagnosticSummary: String {
        "Files: \(files), downloaded: \(downloaded), skipped: \(skipped)\nBytes: \(bytes)\nElapsed: \(elapsed)s, effective KB/s: \(effectiveKBps)\nDirectories: \(directories), discovery: \(discoverySeconds)s\nDownload request time (including retries): \(downloadSeconds)s, slowest: \(slowestDownload)s\nLocal processing: \(localSeconds)s, index writes: \(indexSeconds)s\nMetadata present: \(metadataPresent), absent: \(metadataMissing)"
    }
    public init() {}
}

public struct SyncFailure: Error, LocalizedError, Sendable {
    public let path: String
    public let details: String
    public var errorDescription: String? { "Failed at \(path): \(details)" }
}
public struct SyncOptions: Sendable {
    public let concurrentDownloads: Int
    public let forceFullRefresh: Bool
    public init(concurrentDownloads: Int = 1, forceFullRefresh: Bool = false) {
        self.concurrentDownloads = min(2, max(1, concurrentDownloads))
        self.forceFullRefresh = forceFullRefresh
    }
}
public struct CardSync: Sendable {
    public let client: EZShareClient
    public init(client: EZShareClient = EZShareClient()) { self.client = client }
    public static func clearIndex(for root: URL) throws {
        let location = IncrementalIndex.location(for: root)
        if FileManager.default.fileExists(atPath: location.path) {
            try FileManager.default.removeItem(at: location)
        }
    }

    // Skip only older DATALOG files with stable listing metadata and a verified
    // local index record. Re-download anything ambiguous. Writes stay atomic.
    public func sync(to root: URL, options: SyncOptions = SyncOptions(), progress: @Sendable (SyncReport) async -> Void = { _ in }) async throws -> SyncReport {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.rejectSymlink(root)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        var report = SyncReport()
        let started = ProcessInfo.processInfo.systemUptime
        func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
        var incrementalIndex = IncrementalIndex.load(for: root)
        var pending: [(URL, URL, Int, String)] = [(CardAddress.root, root, 0, "")]
        var visited = Set<URL>()
        var entriesSeen = 0
        while let (remote, local, depth, relative) = pending.popLast() {
            try Task.checkCancellation()
            guard depth <= 32, visited.insert(remote).inserted, visited.count <= 10_000 else { throw CardError.limitExceeded }
            let entries: [CardEntry]
            let listingStart = now()
            do { entries = try await client.list(remote) }
            catch is CancellationError { throw CancellationError() }
            catch { throw SyncFailure(path: relative.isEmpty ? "root" : relative, details: error.localizedDescription) }
            report.discoverySeconds += now() - listingStart
            report.directories += 1
            report.elapsed = now() - started
            report.elapsed = now() - started
                    await progress(report)
            var downloadItems: [(CardEntry, URL, String)] = []
            for entry in entries {
                try Task.checkCancellation()
                entriesSeen += 1
                guard entriesSeen <= 100_000 else { throw CardError.limitExceeded }
                guard CardAddress.safeName(entry.name) else { throw CardError.unsafePath }
                // The card's Wi-Fi configuration may contain credentials; do not copy it.
                if !entry.isDirectory && entry.name.lowercased() == "ezshare.cfg" { continue }
                let destination = local.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
                let displayPath = relative.isEmpty ? entry.name : relative + "/" + entry.name
                try Self.rejectSymlink(destination)
                if entry.isDirectory {
                    var isDirectory: ObjCBool = false
                    if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                        guard isDirectory.boolValue else { throw CardError.unsafePath }
                    } else {
                        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                    }
                    pending.append((entry.url, destination, depth + 1, displayPath))
                } else {
                    // Root, settings and recent records may be rewritten at the same
                    // size: they must always be fetched and compared.
                    if entry.stamp == nil { report.metadataMissing += 1 } else { report.metadataPresent += 1 }
                    let stableDatalog = displayPath.uppercased().hasPrefix("DATALOG/")
                    if stableDatalog && incrementalIndex.shouldSkip(displayPath, stamp: entry.stamp,
                                                           file: destination, force: options.forceFullRefresh) {
                        report.files += 1
                        report.unchanged += 1
                        report.skipped += 1
                        report.elapsed = now() - started
                    await progress(report)
                    } else {
                        downloadItems.append((entry, destination, displayPath))
                    }
                }
            }
            // Use at most two in-flight downloads per directory. Default is one
            // until ez Share firmware concurrency is validated on real hardware.
            try await withThrowingTaskGroup(of: (Int, Result<Data, Error>, TimeInterval).self) { group in
                var index = 0
                var inFlight = 0
                func queue() async {
                    while inFlight < options.concurrentDownloads && index < downloadItems.count {
                        let n = index
                        index += 1
                        inFlight += 1
                        let item = downloadItems[n]
                        report.activeFile = item.2
                        report.elapsed = now() - started
                    await progress(report)
                        group.addTask {
                            let began = ProcessInfo.processInfo.systemUptime
                            do {
                                let data = try await client.download(item.0)
                                return (n, .success(data), ProcessInfo.processInfo.systemUptime - began)
                            } catch { return (n, .failure(error), ProcessInfo.processInfo.systemUptime - began) }
                        }
                    }
                }
                await queue()
                while inFlight > 0 {
                    guard let result = try await group.next() else { break }
                    inFlight -= 1
                    let item = downloadItems[result.0]
                    report.downloadSeconds += result.2
                    report.slowestDownload = max(report.slowestDownload, result.2)
                    let data: Data
                    switch result.1 {
                    case .success(let bytes):
                        data = bytes
                    case .failure(let error):
                        group.cancelAll()
                        if error is CancellationError { throw CancellationError() }
                        throw SyncFailure(path: item.2, details: error.localizedDescription)
                    }
                    try Task.checkCancellation()
                    let localStart = now()
                    do {
                        if let old = try? Data(contentsOf: item.1), old == data {
                            report.unchanged += 1
                        } else {
                            #if os(iOS)
                            try data.write(to: item.1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                            #else
                            try data.write(to: item.1, options: .atomic)
                            #endif
                            report.changed += 1
                        }
                    } catch {
                        group.cancelAll()
                        throw SyncFailure(path: item.2, details: error.localizedDescription)
                    }
                    report.localSeconds += now() - localStart
                    // Commit index only after the bytes are safely present. The
                    // manifest survives cancellation and allows resuming.
                    if let stamp = item.0.stamp {
                        let indexStart = now()
                        do {
                            try incrementalIndex.record(item.2, stamp: stamp, file: item.1)
                            try incrementalIndex.save(for: root)
                            report.indexSeconds += now() - indexStart
                        } catch {
                            throw SyncFailure(path: item.2, details: "Incremental index error: " + error.localizedDescription)
                        }
                    }
                    report.files += 1
                    report.bytes += data.count
                    report.activeFile = item.2
                    report.elapsed = now() - started
                    await progress(report)
                    await queue()
                }
            }
        }
        report.activeFile = nil
        report.elapsed = now() - started
                    await progress(report)
        return report
    }

    private static func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CardError.unsafePath
        }
    }
}
