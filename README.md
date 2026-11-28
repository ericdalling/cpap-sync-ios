# CPAP Sync iOS

Local-first wireless CPAP data synchronization. Phase 0 (v0.0.1) is a Hello World delivery skeleton; the production UI remains a foundation screen while CPAPSyncCore and the iPad lab validate read-only card synchronization.

Specifications and priorities live in [GitHub Issues](https://github.com/ericdalling/cpap-sync-ios/issues/1). See [architecture](docs/architecture.md), [technology ADR](docs/adr/0001-technology-stack.md), and [TestFlight setup](docs/testflight.md).

## Build locally (macOS)
Install Xcode 26 and XcodeGen 2.44.1. Run:
```sh
bash scripts/bootstrap.sh
xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync -showdestinations
bash scripts/test-ios.sh
```
The checked-in project.yml is the canonical project definition; generated Xcode files are intentionally ignored. Deployment target is iOS 17. The app displays its bundle version and build number.

## Workflow
Branch from main, implement a GitHub issue, test, open a PR and link the issue. CI runs unsigned simulator tests and packages an unsigned device build. Every successful main run automatically publishes a GitHub prerelease; PRs never publish. Signed TestFlight releases run independently on trusted main/tag refs after CI succeeds. Never commit credentials or real therapy data.

Phase 0 is complete only when the owner installs the matching TestFlight build on a physical iPhone and a second release verifies distinct build numbering.

See [CI verification](docs/ci-verification.md) and [ez Share protocol discovery](docs/ezshare-protocol.md). The preferred signing path uses Xcode automatic signing with a team API key on GitHub-hosted macOS; manual signing is a fallback, both still require Apple-side validation.

See [automated main build releases](docs/main-build-releases.md) for assets, tagging, verification and retention. GitHub preview IPAs are not installable; use TestFlight for device installation.

[Automatic versioning](docs/versioning.md) keeps app bundle versions, release tags, filenames and metadata consistent for each commit; local builds retain project.yml defaults unless version overrides are supplied.

## iPad lab
Download the `.swiftpm.zip` asset from a successful main release, extract in Files and open `CPAPSyncLab.swiftpm` in Swift Playgrounds. Connect manually to ez Share outside therapy, allow local network access, list root, sync, then export into On My iPad and reconnect to home Wi-Fi for manual SleepHQ upload. See [lab guide](docs/ipad-lab.md).

## Contributing

Community contributions are welcome, especially device compatibility, wireless SD card protocols, sync reliability and privacy-preserving integrations. See [CONTRIBUTING.md](CONTRIBUTING.md) and [GitHub Issues](https://github.com/ericdalling/cpap-sync-ios/issues).

## License

Licensed under the [MIT License](LICENSE). Third-party materials retain their respective licenses. This independent project is not affiliated with CPAP device manufacturers, ez Share or SleepHQ. It is a data transfer utility, not medical advice or a therapy-control tool.
