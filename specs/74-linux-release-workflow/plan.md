# Issue 74 Plan

## Current State

D0 merged the flake prerequisites on `setup`: `linux-release-artifacts` and
`linux-dev-release-artifacts` are available on `x86_64-linux`. The current
`.github/workflows/release.yml` only contains the release-please job.

The Amaru reference keeps Linux artifact publication in
`.github/workflows/release.yml`; it does not combine that job with
release-please. Because this repository already owns that file for
release-please, the compatible shape here is a single workflow file with two
jobs: the existing `release-please` job and a new `linux-bundles` job.

## Implementation

- Extend `.github/workflows/release.yml` triggers to include:
  - push to `setup` for release-please,
  - push tags matching `v*` for artifact publication,
  - PR path filters for workflow and Nix files,
  - manual dispatch with modes for release-please, release artifact build, and
    dev Linux artifact build.
- Preserve release-please configuration and permissions.
- Add a `linux-bundles` job on the `nixos` runner with Cachix enabled.
- Use `.#linux-release-artifacts` for release mode and
  `.#linux-dev-release-artifacts` for PR/dev mode.
- Inline the Linux artifact smoke because this repo does not currently expose
  Amaru's `.#linux-artifact-smoke` app and D1 should avoid widening into shared
  Nix files.
- Upload built files as workflow artifacts for all Linux modes.
- Upload files to the GitHub release only when publishing is enabled by a `v*`
  tag push, by a release-please-created release, or by explicit manual
  `publish=yes`.

## Verification

- `./gate.sh`
- PR CI: the release workflow's PR path-filtered Linux dev build and smoke.
- Final PR audit: release-please job remains present and scoped to setup/manual
  release-please mode.

## Slice Breakdown

One implementation slice is enough because all behavior-changing changes are in
one workflow file and must remain internally consistent.

- Slice 1: Extend `.github/workflows/release.yml` with Linux artifact build,
  smoke, upload, and publish gating while preserving release-please.
