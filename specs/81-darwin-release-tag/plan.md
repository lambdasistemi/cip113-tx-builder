# Issue 81 Plan

## Current State

`nix/darwin-release.nix` accepts `releaseTag ? "v${packageVersion}"`. The
release flake call site does not override it, so release-mode formula URLs are
based on the Cabal version. The workflow already knows the real release tag as
`env.TAG`, and the `paolino/dev-assets/darwin-homebrew-release` action exposes
a `release-check-command` hook that runs with `TAG` exported before building.

Amaru's Darwin release uses the same action and the same hook, but Amaru's
public tag is the Cabal version. For this repo, release-please's
`.release-please-manifest.json` is the source of the public release tag.

## Implementation

- Parse the release-please version from `.release-please-manifest.json` in
  `flake.nix` and derive `releasePleaseTag = "v${releasePleaseVersion}"`.
- Pass `releaseTag = releasePleaseTag` to the release-mode
  `nix/darwin-release.nix` import.
- Remove the `releaseTag ? "v${packageVersion}"` default from
  `nix/darwin-release.nix`, making release callers choose the tag explicitly.
  The dev Homebrew call site already passes `releaseTag = "dev-homebrew"`.
- Add `scripts/release/check-darwin-release-tag`, a workflow-safe verifier that:
  - accepts a tag argument or `TAG`,
  - confirms it matches the release-please manifest,
  - confirms the Darwin release package passthru `releaseTag` and `releaseUrl`
    use that tag,
  - optionally resolves the URL with `--resolve-url` for dry-run proof against
    an existing asset.
- Wire `.github/workflows/darwin-release.yml` to run that script through the
  action's `release-check-command`.

## Verification

- Baseline gate: `./gate.sh`.
- Focused RED: before the fix,
  `nix eval --raw .#packages.aarch64-darwin.darwin-release-artifacts.releaseTag`
  returns `v0.1.1.0`, and the new verifier rejects tag `v0.1.2`.
- Focused GREEN:
  `scripts/release/check-darwin-release-tag v0.1.2 --resolve-url`.
- PR gate after extension: `./gate.sh`, including workflow lint, Darwin package
  eval, and the release URL proof.

## Slice Breakdown

One implementation slice is enough: the Nix call site, release checker, and
workflow hook form one release-mode contract and must land together.
