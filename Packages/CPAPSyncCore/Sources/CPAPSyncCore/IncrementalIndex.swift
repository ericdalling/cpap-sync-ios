import Foundation

// Stored beside, never inside, the CPAP backup so exported folders stay clean.
// Cache misses and inconsistencies only cause redundant downloads.
struct IncrementalIndex: Codable {
    struct Record: Codable {
        let remoteSignature: String
        let localSize: UInt64
        let localModified: Date
    }
    var records: [String: Record] = [:]

    static func location(for root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent(".CPAPSyncIndex-" + root.lastPathComponent + ".json")
    }
    static func load(for root: URL) -> Self {
        guard let data = try? Data(contentsOf: location(for: root)),
              let index = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return index
    }
    mutating func record(_ relative: String, stamp: CardStamp, file: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date else { throw CocoaError(.fileReadUnknown) }
        records[relative] = Record(remoteSignature: stamp.signature, localSize: size, localModified: modified)
    }
    func shouldSkip(_ relative: String, stamp: CardStamp?, file: URL, force: Bool) -> Bool {
        guard !force, let stamp, let old = records[relative],
              old.remoteSignature == stamp.signature,
              stamp.modifiedAt <= Date().addingTimeInterval(-15 * 60),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              (attrs[.size] as? NSNumber)?.uint64Value == old.localSize,
              let modified = attrs[.modificationDate] as? Date,
              modified == old.localModified else { return false }
        return true
    }
    func save(for root: URL) throws {
        let url = Self.location(for: root)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        var fileURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try fileURL.setResourceValues(values)
    }
}
