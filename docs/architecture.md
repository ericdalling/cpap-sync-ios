# Architecture

Phase 0 contains a minimal SwiftUI application and independent CI/release workflows. The production UI is still a foundation screen; shared CPAPSyncCore provides the experimental read-only client and sync logic. The separate iPad lab invokes the same source.

## Boundaries
- Presentation: SwiftUI views and observable state when necessary.
- Domain: pure Swift models and synchronization rules.
- Networking: future read-only WirelessFileSource protocol and ez Share adapter.
- Persistence: future local file store and manifest.

Shared core code lives in Packages/CPAPSyncCore; iPad lab source is in tools/CPAPSyncLab. XcodeGen links the package; release packaging embeds its exact Swift source to avoid unsupported local package dependencies on iPad. Add other boundaries when their issues are implemented. Future synchronization must be local-first, preserve bytes/paths, validate untrusted paths, and never mutate the card.

## Delivery
PR → unsigned macOS simulator build/tests → review → main → manually triggered or tagged signed release → App Store Connect processing → internal TestFlight → physical iPhone verification. Release reruns must use distinct build numbers. No external beta or App Store publishing is in scope.

Release verification and signing run as separate jobs; the verification job never receives signing secrets. Automatic signing with a team API key is preferred; manual distribution signing remains a fallback.

The lab uses manual Wi-Fi, local network permission, conservative re-download and byte comparison, atomic local replacement and explicit folder export. No remote mutation or upload. Physical firmware and SleepHQ import remain unverified.
