# Automated main build publication

Every successful iOS CI run on main (push or manually dispatched on main) builds a Release configuration for a generic iOS device with signing disabled, then publishes a GitHub **prerelease**. PRs also validate packaging and retain the candidate temporarily, but never publish a release. Failed tests, packaging failures, or integrity failures prevent publication. Superseded PR runs are canceled; main runs are independent so each successful main build can be retained.

## Release contents

- CPAPSync-v<version>-b<build>-unsigned.ipa (unsigned engineering package; not directly installable)
- CPAPSync-v<version>-b<build>-dSYMs.zip
- SHA256SUMS.txt
- build-info.json (version, build, commit, run, Xcode, signing state)
- Release notes link the corresponding CI run.

Tags use v<version>-b<build>-<12-char-commit> so each attempt is distinct and matches the v* TestFlight tag scheme. GitHub's own GITHUB_TOKEN-created tags do not trigger push workflows; a separate verified workflow_run of completed successful main CI starts TestFlight. Releases target the exact tested commit, are prereleases and do not replace the latest stable release. The publisher verifies checksums and metadata before creating a draft with all assets, then publishes it. An interrupted publication can leave a draft; inspect it before deleting it or its tag. Rerun the entire workflow for a new candidate and tag, rather than rerunning only the publish job, because artifacts are scoped to the run attempt.

## Trust and retention

The build job has read-only repository access and no Apple signing credentials. Only the main-only publisher has contents:write, and it does not check out or execute repository code. No real CPAP data, signing certificates, provisioning profiles or secrets may enter release artifacts. GitHub Releases are retained until deleted, subject to GitHub limits and repository access; CI artifacts expire after seven days. Monitor storage and prune obsolete preview releases deliberately if needed.

## TestFlight

Unsigned packages are not signed IPAs, and Apple enrollment is not required for this preview workflow. Signed distribution remains a separate trusted workflow on manual dispatch or semantic v* tags, with Apple credentials in the testflight environment. TestFlight runs automatically after successful main CI via workflow_run, because the GITHUB_TOKEN-created preview tag cannot itself trigger a push workflow. Signed delivery and physical install remain mandatory in issue #15.

## Acceptance checks

1. A green PR packages an unsigned IPA and dSYMs; publisher is skipped.
2. A failing test prevents packaging and publication, with test evidence retained.
3. A successful main run publishes exactly one prerelease for that attempt; verify target SHA, all four assets and matching checksums.
4. A second successful main run (or full rerun) creates a distinct prerelease; no Apple credentials are necessary.
5. The signed TestFlight workflow resolves the same marketing version from the same commit; it is triggered by a validated successful CI completion, not by the GITHUB_TOKEN tag push.

See [versioning policy](versioning.md) for automatic patch increments and build identity.
