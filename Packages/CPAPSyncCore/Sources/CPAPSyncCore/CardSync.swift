import Foundation

public struct SyncReport: Sendable, Equatable {
    public var files = 0
    public var changed = 0
    public var unchanged = 0
    public var bytes = 0
    public var activeFile: String?
    public init() {}
}

public struct SyncFailure: Error, LocalizedError, Sendable {
    public let path: String
    public let details: String
    public var errorDescription: String? { "Failed at \(path): \(details)" }
}
public struct SyncOptions: Sendable {
    public let concurrentDownloads: Int
    public init(concurrentDownloads: Int = 1) {
        self.concurrentDownloads = min(2, max(1, concurrentDownloads))
    }
}
public struct CardSync: Sendable {
    public let client: EZShareClient
    public init(client: EZShareClient = EZShareClient()) { self.client = client }

    // All files are re-read until the actual firmware's change metadata is validated.
    // Atomic writes preserve existing complete files after interruption.
    public func sync(to root: URL, options: SyncOptions = SyncOptions(), progress: @Sendable (SyncReport) async -> Void = { _ in }) async throws -> SyncReport {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.rejectSymlink(root)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        var report = SyncReport()
        var pending: [(URL, URL, Int, String)] = [(CardAddress.root, root, 0, "")]
        var visited = Set<URL>()
        var entriesSeen = 0
        while let (remote, local, depth, relative) = pending.popLast() {
            try Task.checkCancellation()
            guard depth <= 32, visited.insert(remote).inserted, visited.count <= 10_000 else { throw CardError.limitExceeded }
            let entries: [CardEntry]
            do { entries = try await client.list(remote) }
            catch is CancellationError { throw CancellationError() }
            catch { throw SyncFailure(path: relative.isEmpty ? "root" : relative, details: error.localizedDescription) }
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
                    downloadItems.append((entry, destination, displayPath))
                }
            }
            // Use at most two in-flight downloads per directory. Default is one
            // until ez Share firmware concurrency is validated on real hardware.
            try await withThrowingTaskGroup(of: (Int, Result<Data, Error>).self) { group in
                var index = 0
                var inFlight = 0
                func queue() async {
                    while inFlight < options.concurrentDownloads && index < downloadItems.count {
                        let n = index
                        index += 1
                        inFlight += 1
                        let item = downloadItems[n]
                        report.activeFile = item.2
                        await progress(report)
                        group.addTask {
                            do { return (n, .success(try await client.download(item.0))) }
                            catch { return (n, .failure(error)) }
                        }
                    }
                }
                await queue()
                while inFlight > 0 {
                    guard let result = await group.next() else { break }
                    inFlight -= 1
                    let item = downloadItems[result.0]
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
                    report.files += 1
                    report.bytes += data.count
                    report.activeFile = item.2
                    await progress(report)
                    await queue()
                }
            }
        }
        report.activeFile = nil
        await progress(report)
        return report
    }

    private static func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CardError.unsafePath
        }
    }
}
