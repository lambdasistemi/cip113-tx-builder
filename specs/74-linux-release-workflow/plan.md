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

During the first D1 gate, the D0 Linux output failed when the DEB/RPM bundlers
invoked `fpm` under Ruby 3.3. The failure is a real prerequisite bug in the
Linux artifact derivation: `fpm` 1.13.1 calls `File.exists?`, which Ruby 3.3
removed. Parent Q-001 authorized widening D1 to include the narrow Nix changes
needed to make both Linux artifact outputs build.

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
- Apply a narrow D0 follow-up fix in the Linux packaging path so
  `.#linux-release-artifacts` and `.#linux-dev-release-artifacts` actually build
  under the pinned Nix inputs. Document this in the PR body as
  "D0 follow-up: fpm/ruby 3.3 compat".

## Verification

- `./gate.sh`, including actual builds of both Linux artifact outputs.
- PR CI: the release workflow's PR path-filtered Linux dev build and smoke.
- Final PR audit: release-please job remains present and scoped to setup/manual
  release-please mode.

## Slice Breakdown

The work remains one implementation slice because the workflow cannot pass its
required PR/dev mode until the Linux artifact output builds. The widened owned
files are limited to the Linux workflow plus the Nix files needed for the D0
follow-up compatibility fix.

- Slice 1: Extend `.github/workflows/release.yml` with Linux artifact build,
  smoke, upload, and publish gating while preserving release-please; fix the
  Linux packaging prerequisite so both artifact outputs build.
