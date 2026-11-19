import SwiftUI
import CPAPSyncCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("CPAP Sync").font(.largeTitle.bold())
            Text("Hello, CPAP Sync!")
                .font(.title2)
                .accessibilityIdentifier("helloMessage")
            Text("Foundation release · core ready")
                .foregroundStyle(.secondary)
            Text(CardAddress.host).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(AppVersion.current.display)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("appVersion")
        }
        .padding()
    }
}
