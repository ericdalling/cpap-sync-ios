# Architecture

Phase 0 contains a minimal SwiftUI application and independent CI/release workflows. The app has no network access, health data storage or external service integration.

## Boundaries
- Presentation: SwiftUI views and observable state when necessary.
- Domain: pure Swift models and synchronization rules.
- Networking: future read-only WirelessFileSource protocol and ez Share adapter.
- Persistence: future local file store and manifest.

Only presentation and a small bundle-version value type are needed today. Add other boundaries when their issues are implemented. Future synchronization must be local-first, preserve bytes/paths, validate untrusted paths, and never mutate the card.

## Delivery
PR → unsigned macOS simulator build/tests → review → main → manually triggered or tagged signed release → App Store Connect processing → internal TestFlight → physical iPhone verification. Release reruns must use distinct build numbers. No external beta or App Store publishing is in scope.
