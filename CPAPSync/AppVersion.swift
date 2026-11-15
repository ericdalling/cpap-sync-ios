import Foundation

struct AppVersion: Equatable {
    let version: String
    let build: String

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    static var current: AppVersion {
        let bundle = Bundle.main
        return AppVersion(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        )
    }

    var display: String { "Version \(version) (\(build))" }
}
