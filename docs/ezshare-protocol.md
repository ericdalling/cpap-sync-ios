# ez Share protocol discovery — #3

Status: literature research only; physical card behavior unverified. No CPAP feature code is introduced before the Phase 0 exit gate.

## Known candidate behavior
Existing independent implementations describe a local Wi-Fi access point, commonly SSID ez Share and default passphrase 88888888, with a directory endpoint at http://192.168.4.1/dir?dir=A:. These are defaults, not guarantees for the owner's actual firmware. Do not hardcode credentials in production.
- https://github.com/adrianRfeeger/ezShareCPAP — desktop sync, preserves structure for OSCAR.
- https://github.com/JCOvergaar/CPAP-data-from-EZShare-SD — directory traversal, configurable exclusion list and incremental behavior.
- https://github.com/johnlago/ezShareToSleepHQ — sync plus optional external upload.

Review source and license at a pinned commit before reusing implementation code. No upstream code copied here.

## Physical verification checklist (owner, iPhone)
- Identify CPAP model, ez Share card model/firmware if displayed; do not expose serial number.
- Outside active therapy, connect to the card Wi-Fi in Settings. Keep CPAP powered and follow manufacturer instructions; do not modify or remove the card during therapy.
- Open the root directory URL in Safari; verify it lists folders/files, not just a photo gallery.
- Follow a nested folder and identify the actual link format, escaping and whether size/date metadata exists.
- Verify binary downloads work via a non-sensitive synthetic test card/fixture where possible. Do not upload actual therapy files to GitHub or chat. Hash comparison with originals remains a later on-device acceptance test.
- Record sanitized endpoint patterns, status codes and listing structure. Replace identifiers, dates, filenames or personal information with synthetic equivalents.

## Client requirements to validate
Only read directory/download URLs on the configured local host; reject external redirects, traversal, duplicate or malformed entries; preserve original relative paths and bytes; handle missing size/mtime, pagination, timeout and power loss. If modification cannot reliably be ruled out, refresh files conservatively. Do not use card configuration endpoints. Determine root and nested download link format from actual firmware before coding parser fixtures.
