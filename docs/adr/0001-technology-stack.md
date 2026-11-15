# ADR 0001: Native iOS and cloud delivery
Status: Accepted for Phase 0

Use SwiftUI, Swift, iOS 17 minimum, XCTest, XcodeGen 2.44.1 and GitHub Actions macOS runners with Xcode 26. XcodeGen keeps the project definition reviewable and reproducible. No application dependencies are required.

Use separate unsigned CI and signed TestFlight workflows. Internal TestFlight requires paid Apple Developer membership and owner-managed App Store Connect credentials. Prefer automatic Xcode signing with an App Store Connect team API key to support iPhone-only setup. Retain manual distribution provisioning as a fallback; validate both against the actual Apple team before relying on them. A local Mac is optional for development but physical iPhone testing is mandatory.

Alternatives: Shortcut/Scriptable is less maintainable for recursive downloads; cross-platform frameworks introduce dependencies without a current Android requirement.
