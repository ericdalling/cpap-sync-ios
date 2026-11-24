# TestFlight setup from iPhone

Phase 0 requires an active paid Apple Developer membership. No Apple credentials or actual upload have been tested yet. Do not paste secrets into chat, issues, PRs, or source files.

## Preferred: automatic signing on GitHub's Mac
1. Complete enrollment and accept required agreements at https://developer.apple.com/account/.
2. Register explicit App ID `com.ericdalling.cpapsync` at https://developer.apple.com/account/resources/identifiers/list. If unavailable, update all bundle-ID references consistently.
3. Create the iOS app record in https://appstoreconnect.apple.com/ with that bundle ID and a unique SKU.
4. Under Users and Access → Integrations → App Store Connect API, request API access if necessary and create a **team** API key with appropriate signing/upload permissions (Admin may be needed for certificate/profile creation). Download its .p8 once; store it securely. Use the least privilege that supports the workflow.
5. In GitHub repository Settings → Environments, create `testflight`; restrict to trusted main/release tags if supported. Set environment variable APPLE_TEAM_ID and secrets ASC_KEY_ID, ASC_ISSUER_ID, and ASC_API_PRIVATE_KEY (raw complete PEM text from the .p8, including header/footer). Alternatively use ASC_KEY_BASE64 instead of the raw key. For raw text on iPhone, use a trusted local text viewer; do not use an online base64/PEM converter.
6. If the private repository's plan does not support environment secrets/variables, use repository Actions secrets and variables with the same names, restrict write access and review changes to all workflows. Do not expose secrets to PR jobs.
7. Leave IOS_SIGNING_MODE unset or set it to automatic. Successful main CI automatically triggers TestFlight through `workflow_run` after all CI jobs (including preview publication) succeed; it verifies the upstream event is a same-repository `main` push, checks out the tested SHA, and reuses the upstream test evidence instead of rerunning simulator tests. Manual Actions → TestFlight → Run workflow on main and trusted user-created `v*` tags remain supported and rerun tests in a job without signing secrets. The release job signs and uploads separately.
8. Verify processing in App Store Connect, answer export compliance according to actual app behavior, add yourself to an internal TestFlight group, install via TestFlight, and confirm the displayed version/build. Repeat deployment to verify build numbers.

Automatic signing with an App Store Connect team API key and xcodebuild -allowProvisioningUpdates is the preferred computer-free path, but its cloud certificate/provisioning behavior must be verified with the actual Apple team. It may require additional permission or manual distribution signing. Do not claim success until tested.

## Manual fallback
Set IOS_SIGNING_MODE=manual. Provide IOS_DISTRIBUTION_P12_BASE64, IOS_DISTRIBUTION_P12_PASSWORD and IOS_PROVISIONING_PROFILE_BASE64 in addition to the API key and team configuration. The .p12 must contain the certificate and its private key. Use an App Store distribution profile for the bundle ID. If a cloud-generated certificate is needed, use a reviewed dedicated signing setup on a hosted Mac with private key retained securely; never upload signing material as a workflow artifact or put it in logs. Do not revoke existing team certificates without owner approval.

## Reference
- https://developer.apple.com/help/account/certificates/cloud-managed-certificates/
- https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/
- https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets

## Verification
Record workflow run links and displayed build numbers in #15, never secret values. Upload success is not evidence of processing or installation. Phase 0 remains open until two TestFlight deployments and physical verification.

## Version identity
Both CI and TestFlight use [the shared version resolver](versioning.md). A manually dispatched TestFlight build of a commit has the same marketing version as its GitHub preview but a distinct build number. Explicit `vX.Y.Z` tags must equal the resolved marketing version. Xcode upload must not manage or override the version/build number.

## First signing run diagnosis (Nov 24, 2026)
[Run #45493330948](https://github.com/ericdalling/cpap-sync-ios/actions/runs/45493330948): verification passed, all three App Store Connect API key environment values and Apple Team ID were present, API private key parsed, then xcodebuild archive failed with `No profiles for ... were found` while trying to generate an **iOS App Development** provisioning profile because no devices were registered. TestFlight requires distribution signing; release archive now explicitly selects `Apple Distribution` while keeping automatic provisioning. This is a candidate correction requiring a new trusted signed run; do not register a physical device merely to work around a development signing request. If Apple still refuses automatic distribution, inspect new error and determine whether an App Store Connect distribution profile/certificate setup is required. Do not commit or print credentials.
