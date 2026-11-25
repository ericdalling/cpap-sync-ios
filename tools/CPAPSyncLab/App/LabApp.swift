import SwiftUI
import UniformTypeIdentifiers
#if canImport(CPAPSyncCore)
import CPAPSyncCore
#endif

@main
struct LabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

struct LabView: View {
    @State private var status = "Connect manually to ez Share Wi-Fi."
    @State private var entries: [CardEntry] = []
    @State private var report = SyncReport()
    @State private var task: Task<Void, Never>?
    @State private var completed = false
    @State private var parallelDownloads = false
    @State private var forceRefresh = false
    @State private var exportFolder = false
    @State private var resetConfirmation = false
    private let client = EZShareClient()

    private var hasSavedFiles: Bool {
        guard let enumerator = FileManager.default.enumerator(at: backup, includingPropertiesForKeys: [.isRegularFileKey]) else { return false }
        for case let file as URL in enumerator {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        }
        return false
    }
    private var backup: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CPAPData", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Text("192.168.4.1 · manual Wi-Fi").font(.caption)
                    Text(status)
                    Button("Test connection / list root") {
                        start {
                            entries = try await client.list()
                            status = "Root listing: \(entries.count) entries."
                        }
                    }.disabled(task != nil)
                    ForEach(entries, id: \.name) { entry in
                        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                    }
                }
                Section("Download") {
                    Text("Use one SD card only. Already saved files survive a failed sync.")
                    Toggle("Experimental: 2 parallel downloads", isOn: $parallelDownloads).disabled(task != nil)
                    Toggle("Force full refresh", isOn: $forceRefresh).disabled(task != nil)
                    Text("Files: \(report.files) · Updated: \(report.changed) · Unchanged: \(report.unchanged) · Skipped downloads: \(report.skipped)")
                    Text("Read: \(report.bytes) bytes")
                    if let active = report.activeFile { Text("Last active: \(active)").font(.caption).lineLimit(2) }
                    Button("Sync CPAP data") {
                        completed = false
                        report = SyncReport()
                        start {
                            report = try await CardSync(client: client).sync(to: backup, options: SyncOptions(concurrentDownloads: parallelDownloads ? 2 : 1, forceFullRefresh: forceRefresh)) { update in
                                await MainActor.run { report = update }
                            }
                            completed = true
                            status = "Sync complete. Export locally, then reconnect to home Wi-Fi."
                        }
                    }.disabled(task != nil)
                    Button("Cancel sync") { task?.cancel() }.disabled(task == nil)
                    Button(completed ? "Export complete backup to Files" : "Export partial backup to Files") { exportFolder = true }
                        .disabled(task != nil || !hasSavedFiles)
                    Button("Delete local backup", role: .destructive) { resetConfirmation = true }
                        .disabled(task != nil)
                }
                Section("Privacy") {
                    Text("No automatic external upload. Choose On My iPad for export; iCloud destinations may sync to your account. Card access is read-only. This lab is experimental.")
                }
            }
            .navigationTitle("CPAP Sync Lab")
            .confirmationDialog("Delete the local backup? The SD card is not changed.", isPresented: $resetConfirmation) {
                Button("Delete local backup", role: .destructive) {
                    do {
                        if FileManager.default.fileExists(atPath: backup.path) {
                            try FileManager.default.removeItem(at: backup)
                        }
                        try CardSync.clearIndex(for: backup)
                        completed = false
                        report = SyncReport()
                        status = "Local backup deleted."
                    } catch { status = "Could not delete local backup." }
                }
            }
            .fileImporter(isPresented: $exportFolder, allowedContentTypes: [.folder]) { result in
                do {
                    let directory = try result.get()
                    let scoped = directory.startAccessingSecurityScopedResource()
                    defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
                    let target = directory.appendingPathComponent("CPAPData-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.copyItem(at: backup, to: target)
                    status = completed ? "Complete folder exported. Reconnect to home Wi-Fi." : "PARTIAL backup exported; retry sync before using SleepHQ."
                } catch { status = "Export failed. Select a writable folder in On My iPad." }
            }
        }
    }

    @MainActor private func start(_ operation: @escaping @MainActor () async throws -> Void) {
        status = "Working…"
        task = Task {
            defer { task = nil }
            do { try await operation() }
            catch is CancellationError { status = "Cancelled. Complete files retained." }
            catch let error as CardError { status = error.localizedDescription }
            catch let error as SyncFailure { status = error.localizedDescription }
            catch { status = "Operation failed. Check Wi-Fi, local network permission and available storage." }
        }
    }
}
