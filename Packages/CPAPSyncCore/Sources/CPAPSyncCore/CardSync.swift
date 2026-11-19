import Foundation

public struct SyncReport: Sendable, Equatable {
    public var files = 0
    public var changed = 0
    public var unchanged = 0
    public var bytes = 0
    public init() {}
}

public struct CardSync: Sendable {
    public let client: EZShareClient
    public init(client: EZShareClient = EZShareClient()) { self.client = client }

    // All files are re-read until the actual firmware's change metadata is validated.
    // Atomic writes preserve existing complete files after interruption.
    public func sync(to root: URL, progress: @Sendable (SyncReport) async -> Void = { _ in }) async throws -> SyncReport {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.rejectSymlink(root)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        var report = SyncReport()
        var pending: [(URL, URL, Int)] = [(CardAddress.root, root, 0)]
        var visited = Set<URL>()
        var entriesSeen = 0
        while let (remote, local, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard depth <= 32, visited.insert(remote).inserted, visited.count <= 10_000 else { throw CardError.limitExceeded }
            for entry in try await client.list(remote) {
                try Task.checkCancellation()
                entriesSeen += 1
                guard entriesSeen <= 100_000 else { throw CardError.limitExceeded }
                guard CardAddress.safeName(entry.name) else { throw CardError.unsafePath }
                let destination = local.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
                try Self.rejectSymlink(destination)
                if entry.isDirectory {
                    var isDirectory: ObjCBool = false
                    if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                        guard isDirectory.boolValue else { throw CardError.unsafePath }
                    } else {
                        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                    }
                    pending.append((entry.url, destination, depth + 1))
                } else {
                    let data = try await client.download(entry)
                    try Task.checkCancellation()
                    if let old = try? Data(contentsOf: destination), old == data {
                        report.unchanged += 1
                    } else {
                        #if os(iOS)
                        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        #else
                        try data.write(to: destination, options: .atomic)
                        #endif
                        report.changed += 1
                    }
                    report.files += 1
                    report.bytes += data.count
                    await progress(report)
                }
            }
        }
        return report
    }

    private static func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CardError.unsafePath
        }
    }
}
