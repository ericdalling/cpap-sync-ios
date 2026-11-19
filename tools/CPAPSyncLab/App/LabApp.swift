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
    @State private var exportFolder = false
    @State private var resetConfirmation = false
    private let client = EZShareClient()

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
                    Text("Use one SD card only. Sync again after reconnecting if interrupted.")
                    Text("Files: \(report.files) · Updated: \(report.changed) · Identical: \(report.unchanged)")
                    Text("Read: \(report.bytes) bytes")
                    Button("Sync CPAP data") {
                        completed = false
                        report = SyncReport()
                        start {
                            report = try await CardSync(client: client).sync(to: backup) { update in
                                await MainActor.run { report = update }
                            }
                            completed = true
                            status = "Sync complete. Export locally, then reconnect to home Wi-Fi."
                        }
                    }.disabled(task != nil)
                    Button("Cancel sync") { task?.cancel() }.disabled(task == nil)
                    Button("Export folder to Files") { exportFolder = true }
                        .disabled(task != nil || !completed)
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
                    status = "Folder exported. Reconnect to home Wi-Fi and select it in SleepHQ."
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
            catch { status = "Operation failed. Check Wi-Fi, local network permission and available storage." }
        }
    }
}
