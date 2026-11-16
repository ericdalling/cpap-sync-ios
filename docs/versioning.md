# Automatic version identity

A single resolver (scripts/resolve-version.sh) is used by simulator CI, unsigned device packaging and signed TestFlight. It needs complete Git history. The marketing version is the baseline in config/version-baseline.txt plus the number of first-parent commits since its anchor. Baseline 0.0.1 is anchored at the merged main-build publication change. Each new main commit increments the patch, including documentation changes. A rerun of the same commit retains its marketing version. PR merge commits use provisional versions; only main publishes. Never rewrite main history.

For example, the first merge after the anchor is 0.0.2, then 0.0.3. A deliberate milestone bump changes the baseline and anchor together in a reviewed PR. To make the next main merge exactly 0.1.0, set config/version-baseline.txt to `0.1.0 <previous-main-sha> 1` (offset 1); the next merge is 0.1.0 and later commits increment its patch. The initial offset is 0. No automatic minor/major guesses are made. project.yml contains fallback defaults for local builds; CI always overrides both Xcode settings.

Build string format: <workflow run number>.<channel>.<attempt>, channel 10 for preview, 20 for TestFlight. This separates the workflows' independent counters, avoids collision with historical two-component build strings, and gives monotonically increasing signed build numbers within TestFlight. Reruns get a distinct build number, not a new marketing version. Guard against the 4/2/2 digit limits; migrate the counter scheme before 10,000 runs or 100 attempts. Build numbers need not be globally chronological across channels; the marketing version aligns by commit.

A preview release tag, title, IPA/dSYM filename, metadata, release notes and bundled Info.plist all use the resolved version/build. Signed archives validate both keys before upload. A signed semantic tag vX.Y.Z must match the computed marketing version. GitHub main-* tags never trigger signing.

No automated source commits, mutable version files, tag races, or Apple credentials are needed to calculate the version. Historical releases remain unchanged.
