# Main branch governance

The desired branch ruleset is version-controlled in config/github/main-ruleset.json. Import it through repository Settings > Rules > Rulesets > New ruleset > Import a ruleset (or create the equivalent branch ruleset manually). The file is a proposed configuration, not proof of live enforcement.

## Prerequisites

- GitHub Pro (or an eligible higher plan) for this private repository. Do not make the repository public to enable rulesets.
- Merge the CODEOWNERS file into main first.
- CODEOWNERS currently names @ericdalling, the repository owner, for every path. GitHub does not permit authors to approve their own PRs. The current ChatGPT GitHub connector creates PRs as ericdalling; consequently this configuration would block these PRs until a second legitimate, independent reviewer with write access is added to CODEOWNERS, or PRs are created through a genuinely distinct authorized contributor identity. Do not enable an active no-bypass rule until the review path is verified. Do not add invented owners or use self-approval/bypass as a substitute.

## Required rules

Target main only, require PRs, one independent code-owner approval, dismiss stale approvals, require approval of most recent reviewable push by someone other than its pusher, resolve conversations, require up-to-date branches, require the iOS CI test job from GitHub Actions, block deletions and force pushes, linear history, squash merges only, no bypass actors.

The CI job named test covers version resolver tests, bootstrap, unit tests, UI tests, unsigned device archive and packaging. The main-only publish job is deliberately not required for PR merge because it runs after merging; the separately triggered TestFlight workflow is also not a PR gate. Add any future PR validation jobs to required checks. Confirm exact status check context and source against the GitHub UI before activating.

## Verification

1. Confirm plan supports private rulesets and a second eligible reviewer or separate contributor identity is ready.
2. Merge CODEOWNERS, then import the ruleset and verify Active enforcement; inspect the exact check name/source in Settings.
3. Verify a direct push is rejected, a PR with a failing check cannot merge, a green PR without the owner review cannot merge, and a reviewed green PR can merge. Use disposable branches and do not intentionally break main.
4. Link evidence in issue #4. The existing negative CI test demonstrates failing tests fail CI; it does not prove branch enforcement.
