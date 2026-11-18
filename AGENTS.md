# Engineering instructions

- Read the assigned GitHub issue and epic #1 before implementation. Issues own feature requirements; do not duplicate them in docs.
- Shared core and iPad lab may proceed alongside Phase 0; signed iPhone validation remains mandatory before production MVP completion. Keep changes small, focused and testable. Use branches and PRs; link issue numbers, and close only after acceptance criteria are verified.
- SwiftUI, iOS 17+, Swift concurrency. Favor value types, protocol boundaries and dependency injection when needed; no speculative architecture or dependencies.
- Use project.yml as the XcodeGen source of truth. Pin tooling; do not edit generated Xcode project files. Run CI and report actual evidence, not assumed success.
- Never write to the CPAP card. Never commit real patient data, device identifiers, credentials or signing material. Use synthetic fixtures; keep diagnostics sanitized.
- No external data transmission without explicit user consent. Preserve raw bytes and directory structure when implementing sync.
- Release secrets are limited to trusted refs; do not run untrusted code with signing credentials. Do not merge or deploy automatically unless authorized.

- Every change to main must use a PR, with an independent code owner approval on the latest changes, all review conversations resolved, and all required CI checks green. Do not bypass branch protections. If plan or identity limitations prevent enforcement, report the blocker and do not represent the policy as active. See docs/main-branch-governance.md.

- Shared CPAPSyncCore is canonical. The lab ZIP embeds exact Swift source from that package because iPad Playgrounds has local package limitations; never edit a generated copy. CI must validate both artifacts.
