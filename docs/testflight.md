# TestFlight setup (owner)

This workflow has not yet been validated against Apple credentials. Do not paste secrets into issues, chat, or source files.

1. Enroll in Apple Developer Program. Register explicit App ID `com.ericdalling.cpapsync` (if unavailable, change project.yml, release script and Apple record consistently). Create an iOS App Store Connect record with that bundle ID.
2. Create an Apple Distribution certificate with its private key and an App Store distribution provisioning profile for that App ID. Export the certificate/private key as password-protected PKCS#12. Apple-side certificate creation/export may require access to a Mac or another secure certificate-generation process.
3. Create an App Store Connect team API key with sufficient upload permissions; download its .p8 once. Keep credentials in secure storage.
4. In repository Settings → Environments, create `testflight` and restrict deployments to trusted main/release tags where supported. Add environment variable `APPLE_TEAM_ID` and secrets:
   - IOS_DISTRIBUTION_P12_BASE64 (base64 of p12)
   - IOS_DISTRIBUTION_P12_PASSWORD
   - IOS_PROVISIONING_PROFILE_BASE64 (base64 of mobileprovision)
   - ASC_API_KEY_BASE64 (base64 of p8)
   - ASC_KEY_ID
   - ASC_ISSUER_ID
5. Merge reviewed foundation PR after CI passes. Run Actions → TestFlight → Run workflow on main (or push a reviewed v* tag). The workflow repeats unsigned tests before signing; build number uses run number and attempt. Verify App Store Connect processing and export compliance prompts.
6. Create internal TestFlight group and add yourself as tester. Install TestFlight on iPhone, accept invitation, install CPAP Sync, verify displayed version/build against Actions run.
7. Run again to validate a unique build and updated installation. Record evidence in #15 without sensitive screenshots or secrets.

Upload success is not equivalent to processed/installed success. If Apple rejects signing, verify team, bundle ID, certificate/profile expiration and matching private key. If encryption compliance is requested, answer based on actual app behavior. Phase 0 stays open until on-device verification.
