# Project map: HytaleArabic

This is a scoped map of the artifact storage policy, not a full application architecture review.

## [TECH_STACK]

GitHub-hosted Actions; Node.js 24 for maintenance checks; Python/PyYAML and actionlint for workflow validation. Application dependencies were not changed.

## [SYSTEM_FLOW]

`ARTIFACT-01`: workflow edits trigger policy checks; release workflows produce durable release assets; temporary uploads expire after one day.

## [ARCHITECTURE]

Existing product workflows remain repository-specific. Maintenance is isolated under `.github/scripts/` and `.github/workflows/`.

## [ORPHANS & PENDING]

Application behavior and native/UI acceptance are outside this scoped policy change.

## Artifact storage policy — 2026-10-19

- `ARTIFACT-01` is implemented in `.github/workflows/artifact-maintenance.yml` and `.github/scripts/artifact-policy.cjs`; behavioral checks are in `.github/scripts/artifact-policy.test.cjs`.
- Direct artifact uploads retain files for one day. Policy checks also reject future upload steps that omit this limit. Where present, Flatpak's implicit upload is replaced by an explicit one-day upload.
- Every six hours, maintenance deletes expired (>24h) or superseded artifacts from completed runs only. Commit-suffixed names are grouped by platform; current runs are protected and checked again immediately before deletion. Manual dispatch defaults to preview-only. Maintenance never modifies release assets or caches.
- Distribution builds run on explicit manual/release triggers where separated from verification. Existing tests remain automatic; site/container deployment and platform-managed delivery retain their existing purpose. Publishing requires its existing release trigger or an explicit manual publishing choice.
- Verification: policy behavior and workflow checks run on GitHub-hosted Ubuntu for this source commit; see the **Artifact storage policy** Actions run attached to the commit for its actual result. No application tests, builds, downloads, or installations were run on the user's device. Application packaging/updater behavior was not exercised by a policy-only check.
- Pending: GitHub may take 6–12 hours to recalculate storage after deletions. Existing artifacts do not receive shorter expiry retroactively; scheduled maintenance applies the same policy to them. Quota recovery and a future authorized release/upload must be observed separately. Scheduled workflows can be delayed or disabled by GitHub after inactivity; one-day upload retention remains the primary limit.

