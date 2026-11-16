# CI quality-gate evidence

Baseline PR #16 passed iOS CI run 43670727282: https://github.com/ericdalling/cpap-sync-ios/actions/runs/43670727282

Positive test: ordinary PR builds and runs unit and UI tests.

Negative test (temporary PR branch only): add a deterministic failing XCTest, run CI, verify the test step and job fail and test evidence is uploaded, then remove the temporary test. Never merge a deliberately failing test. Record actual run links and final green status in issue #4.

Configure a required PR check named test (iOS CI) for main in repository Rules/Branches when supported by the plan. Private repository protection may require a paid plan. Do not claim enforcement until verified.

The release workflow independently repeats unsigned tests before accessing signing credentials, so a failing test blocks release.

Main CI also archives and packages an unsigned iOS device build. The publisher runs only after successful test and packaging steps and only for main pushes/manual runs; see [main build releases](main-build-releases.md). Superseded PR runs are canceled; independent main runs are retained for publication.
