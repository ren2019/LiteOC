---
name: release
description: Publish and verify one complete LiteOC release.
disable-model-invocation: true
---

# Release LiteOC

Treat explicit invocation as authorization for this run's release-note commit, push, annotated tag, GitHub Release, and proven released-issue comments and closures. Do not request a second confirmation.

Honor any narrower instruction such as plan-only or no-execution; authorization never expands the user's requested scope. For plan-only or no-execution, do not inspect the repository: state the requested scope, render a natural-language skip as **Post-release Acceptance: skipped — REASON**, and end. For a Release Run, record Post-release Acceptance as default, naturally skipped with its reason, or explicitly expanded to a real VPN check before running commands, then carry that scope to the final report.

## 1. Preflight

- Work only in `ren2019/LiteOC` on `main`.
- Fetch `origin/main` and version tags. Require an empty worktree and `HEAD` equal to `origin/main`; stop with the exact mismatch otherwise.
- Use the user's valid explicit version. If omitted, advance the latest version tag's minor component (`v1.5` → `v1.6`). Require a forward version with no existing tag or Release.
- Resolve the issue closure set from issue numbers explicitly supplied for the release, closing references (`Closes`, `Fixes`, or `Resolves`) in released commit or pull-request metadata, and unambiguous `#N` references whose issue scope matches the release diff. Read every candidate in `ren2019/LiteOC`; treat a supplied candidate that cannot be proven as a blocking mismatch. Record proven open targets, already-closed matches, or none. Leave every pull request, title-only match, and other unproven issue unchanged.

Complete this phase only when clean, synchronized main, the unused target version, and the issue closure set are proven.

## 2. Prepare

- Read the diff and verification evidence since the latest tag. Overwrite `RELEASE_NOTES.md`; translate outcomes for users instead of copying commit subjects.
- Keep this exact structure: `# LiteOC vX.Y`, `## 中文`, summary, `### 用户可感知变化` with 2–5 bullets, `### 验证`, then the equivalent `## English` sections, followed by `## Full Changelog` and the comparison URL.
- Run every `gui/test/*_test.sh` contract suite and `git diff --check`. Run any additional targeted check justified by the changed release path.
- Run `scripts/release-gate.sh notes TARGET_TAG PREVIOUS_TAG RELEASE_NOTES.md`.
- Require `RELEASE_NOTES.md` to be the only changed path. Stage only that file, verify the staged path, commit it, and require a clean worktree again.

Complete this phase only when the curated note is the sole release commit and every local check passes.

## 3. Publish

- Create the annotated target tag on the release-note commit, then push `main` and that tag.
- Follow the tag-triggered `build` workflow to a terminal result. On failure, report the failing gate and stop; never create or repair a Release outside CI.
- Verify the published tag, title, target commit, bilingual body, single `LiteOC-X.Y.pkg` asset, and nonempty GitHub `sha256` digest against local expectations.

Complete this phase only when CI succeeds and the live Release matches the tracked note and artifact identity.

## 4. Accept

Follow the recorded acceptance scope. By default, download the published package to a temporary directory, compare its SHA-256 with GitHub's digest, install it, and verify:

- receipt `local.liteoc.pkg` and `/Applications/LiteOC.app` both report `X.Y`;
- installed `/usr/local/sbin/vpnctl` matches the helper payload extracted from that package;
- LiteOC launches from `/Applications`, and `vpnctl status` returns through the configured profile without mutation.

Keep real VPN connection attempts out of default acceptance. If the user explicitly requests one, record the initial state, connect, verify, disconnect, and verify cleanup. For a recorded skip, omit install/launch/status and report **Post-release Acceptance: skipped** with the user's reason.

Complete this phase only when acceptance passes or the user's recorded skip is preserved. A failed acceptance blocks issue closure.

## 5. Close released issues

Run this phase only after Publish completes and Post-release Acceptance passes or is explicitly skipped.

- Use the issue closure set recorded in Preflight. Keep recorded already-closed matches unchanged and report their existing state.
- Close each proven open target with `gh issue close NUMBER -R ren2019/LiteOC --reason completed --comment ...`; the closing comment records the exact tag and Release URL plus `Post-release Acceptance: passed` or the explicit skipped reason.
- Read back `state`, `stateReason`, and the closing comment. Require `CLOSED`, `COMPLETED`, the exact tag, and the Release URL. If closing or verification fails, report the issue and stop; the published Release remains live, but the Release Run is incomplete.
- If no proven open target exists, report **Issue Closure: none — no proven released issue** and continue without mutation. Report an already-closed proven issue without changing its reason or labels.

Complete this phase only when every proven open target is closed and verified, or the absence of a proven open target is reported explicitly.

Report the workflow URL, Release URL, digest comparison, installed identities, launch/status result, real-VPN scope, issue numbers and closure URLs, and every failed or skipped check.
