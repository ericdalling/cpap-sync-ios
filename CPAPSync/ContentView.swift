import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CPAPSyncCore

struct ContentView: View {
    @State private var status = "Join the ez Share Wi-Fi network in Settings before connecting."
    @State private var entries: [CardEntry] = []
    @State private var report = SyncReport()
    @State private var operation: Task<Void, Never>?
    @State private var exportFolder = false
    @State private var resetConfirmation = false
    @State private var completed = false
    @State private var forceRefresh = false
    @State private var networkSummary = "No measurements yet"
    @State private var benchmarkSummary = "Not run"
    @State private var syncStarted: Double?
    @State private var syncClock: Double = 0

    private let client = EZShareClient()

    private var backup: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CPAPData", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Connect to ez Share") {
                    Label("Card address: \(CardAddress.host)", systemImage: "wifi")
                        .font(.subheadline)
                    Text("In iPhone Settings → Wi-Fi, join your ez Share card. Return here and test the connection. Keep this app open during sync.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(status)
                        .accessibilityIdentifier("syncStatus")
                    Button("Test connection / list root") {
                        start {
                            entries = try await client.list()
                            status = "Connected. Found \(entries.count) root entries."
                        }
                    }
                    .accessibilityIdentifier("testConnectionButton")
                    .disabled(operation != nil)
                    ForEach(entries, id: \.name) { entry in
                        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                    }
                }

                Section("Sync CPAP files") {
                    Text("Read-only download. Nothing is deleted or changed on the card.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Force full refresh", isOn: $forceRefresh)
                        .disabled(operation != nil)
                    Text("Files: \(report.files) · Updated: \(report.changed) · Unchanged: \(report.unchanged) · Skipped downloads: \(report.skipped)")
                        .accessibilityIdentifier("syncCounts")
                    Text("Read: \(ByteCountFormatter.string(fromByteCount: Int64(report.bytes), countStyle: .file))")
                    Button("Sync CPAP data") {
                        completed = false
                        report = SyncReport()
                        start {
                            await client.diagnostics.reset()
                            syncStarted = ProcessInfo.processInfo.systemUptime
                            defer { syncStarted = nil }
                            report = try await CardSync(client: client).sync(to: backup, options: SyncOptions(forceFullRefresh: forceRefresh)) { update in
                                await MainActor.run { report = update }
                            }
                            completed = true
                            status = "Sync complete. Export the folder, then reconnect to your normal Wi-Fi."
                        }
                    }
                    .accessibilityIdentifier("syncButton")
                    .disabled(operation != nil)
                    Button("Cancel sync") { operation?.cancel() }
                        .disabled(operation == nil)
                    Button("Export folder to Files") { exportFolder = true }
                        .accessibilityIdentifier("exportButton")
                        .disabled(operation != nil || !completed)
                    Button("Delete local backup", role: .destructive) {
                        resetConfirmation = true
                    }
                    .disabled(operation != nil)
                }

                Section("Sync performance") {
                    Text(report.diagnosticSummary + "\n" + networkSummary)
                    if syncStarted != nil { Text("Live elapsed: \(Int(syncClock)) seconds") }
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy diagnostic report") {
                        UIPasteboard.general.string = report.diagnosticSummary + "\n" + networkSummary + "\nBenchmark: " + benchmarkSummary
                    }
                }

                Section("Read-only network benchmark") {
                    Text("Samples up to four historical or current data files; discards downloaded bytes and does not change the backup.")
                        .font(.footnote)
                    Text(benchmarkSummary).font(.footnote)
                    Button("Run network benchmark") {
                        start {
                            let probe = EZShareClient()
                            let began = ProcessInfo.processInfo.systemUptime
                            var pending = [CardAddress.root]
                            var seen = Set<URL>()
                            var samples: [CardEntry] = []
                            while let directory = pending.popLast(), seen.count < 20, samples.count < 4 {
                                try Task.checkCancellation()
                                guard seen.insert(directory).inserted else { continue }
                                for entry in try await probe.list(directory) {
                                    if entry.isDirectory { pending.append(entry.url) }
                                    else if directory != CardAddress.root && entry.name.lowercased().hasSuffix(".edf") && samples.count < 4 { samples.append(entry) }
                                }
                            }
                            let discovery = ProcessInfo.processInfo.systemUptime - began
                            guard !samples.isEmpty else { benchmarkSummary = "No eligible sample files found"; return }
                            var lines = [String(format: "Discovery: %.2fs", discovery)]
                            for width in [1, 2, 4] {
                                let start = ProcessInfo.processInfo.systemUptime
                                var bytes = 0
                                for offset in stride(from: 0, to: samples.count, by: width) {
                                    let batch = Array(samples[offset..<min(offset + width, samples.count)])
                                    bytes += try await withThrowingTaskGroup(of: Int.self) { group in
                                        for entry in batch { group.addTask { try await probe.download(entry).count } }
                                        var total = 0
                                        for try await count in group { total += count }
                                        return total
                                    }
                                }
                                let seconds = ProcessInfo.processInfo.systemUptime - start
                                lines.append(String(format: "%d concurrent: %d bytes, %.2fs, %.2f KB/s", width, bytes, seconds, Double(bytes)/max(seconds, 0.001)/1000))
                                benchmarkSummary = lines.joined(separator: "\n")
                            }
                            benchmarkSummary += "\n" + (await probe.diagnostics.summary())
                            status = "Benchmark complete."
                        }
                    }.disabled(operation != nil)
                }

                Section("Export to SleepHQ") {
                    Text("Export a folder to On My iPhone, reconnect to your regular Wi-Fi, then choose the exported data in SleepHQ's manual upload. Upload compatibility must still be validated.")
                        .font(.footnote)
                    Text("Files may contain sensitive health data. No automatic uploads occur. Avoid iCloud destinations unless you intend to sync the exported files to iCloud. Delete temporary exported copies when finished.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Text(AppVersion.current.display)
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("appVersion")
                }
            }
            .task {
                while !Task.isCancelled {
                    networkSummary = await client.diagnostics.summary()
                    if let started = syncStarted { syncClock = ProcessInfo.processInfo.systemUptime - started }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .navigationTitle("CPAP Sync")
            .confirmationDialog("Delete downloaded data from this iPhone? The SD card will not be modified.", isPresented: $resetConfirmation) {
                Button("Delete local backup", role: .destructive) {
                    do {
                        if FileManager.default.fileExists(atPath: backup.path) {
                            try FileManager.default.removeItem(at: backup)
                        }
                        try CardSync.clearIndex(for: backup)
                        report = SyncReport()
                        completed = false
                        status = "Local backup deleted."
                    } catch {
                        status = "Could not delete local backup."
                    }
                }
            }
            .fileImporter(isPresented: $exportFolder, allowedContentTypes: [.folder]) { result in
                do {
                    guard completed else {
                        status = "Complete a sync before exporting."
                        return
                    }
                    let directory = try result.get()
                    let scoped = directory.startAccessingSecurityScopedResource()
                    defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
                    let target = directory.appendingPathComponent("CPAPData-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.copyItem(at: backup, to: target)
                    status = "Exported to Files. Reconnect to normal Wi-Fi for SleepHQ."
                } catch {
                    status = "Export failed. Select a writable location under On My iPhone."
                }
            }
        }
    }

    @MainActor
    private func start(_ work: @escaping @MainActor () async throws -> Void) {
        status = "Working…"
        operation = Task {
            defer { operation = nil }
            do {
                try await work()
            } catch is CancellationError {
                status = "Cancelled. Previously downloaded complete files were retained."
            } catch let error as CardError {
                status = error.localizedDescription
            } catch {
                status = "Could not complete the operation. Check Wi-Fi, local network access, and available storage."
            }
        }
    }
}
