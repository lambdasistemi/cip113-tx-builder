# Issue 81 Spec: Darwin Formula Release Tag

## P1 User Story

As a release operator publishing `cip113-cli` for macOS, I need the generated
Homebrew formula to point at the exact GitHub release tag being published, so a
successful release workflow cannot leave `brew install cip113-cli` pointing at a
nonexistent tag.

## Background

The real `v0.1.2` Darwin publish run uploaded
`cip113-cli-0.1.1.0-aarch64-darwin.tar.gz` to the correct release, but the
formula URL used `releases/download/v0.1.1.0/...`. That tag came from
`nix/darwin-release.nix` defaulting `releaseTag` to `v${packageVersion}`, where
`packageVersion` is the Cabal version. In this repo, Cabal versions and
release-please tags are intentionally separate schemes.

`lambdasistemi/amaru-treasury-tx` avoids this class of mismatch by making Cabal
own release tags and by running a workflow release check before Darwin builds.
That exact invariant does not apply here because release-please owns the public
tag, but the release-check-command pattern does fit.

## Functional Requirements

- **FR-001**: The release-mode Darwin package must pass an explicit
  `releaseTag` derived from release-please metadata, not the Cabal package
  version.
- **FR-002**: `nix/darwin-release.nix` must no longer provide a Cabal-derived
  release-tag default that release callers can accidentally inherit.
- **FR-003**: The Darwin release workflow must validate that its runtime
  `TAG` equals the release-please manifest tag before it builds and publishes.
- **FR-004**: The repository must include a repeatable proof command that, for
  a supplied tag, verifies the generated release URL contains that tag and that
  the URL resolves.
- **FR-005**: The existing PR/dev Homebrew path must continue to use
  `dev-homebrew` and may continue to rewrite formula URLs for local-tap tests.
- **FR-006**: CI must not enforce equality between the Cabal artifact version
  and the release-please public release tag.
- **FR-007**: Darwin PR-mode verification must continue to install and test the
  generated dev formula through the local tap under current Homebrew tap-trust
  rules.

## Success Criteria

- `nix eval --raw .#packages.aarch64-darwin.darwin-release-artifacts.releaseTag`
  returns `v0.1.2` at the current release commit.
- The same release artifact reports a URL under
  `releases/download/v0.1.2/`, while the tarball name continues to use the Cabal
  artifact version.
- `scripts/release/check-darwin-release-tag v0.1.2 --resolve-url` exits 0
  against the live release asset.
- `./gate.sh` passes after the issue-specific proof is added.
- The ordinary PR `CI / build` workflow does not fail solely because Cabal and
  release-please versions differ.
- The Darwin PR-mode workflow uses the same tap-trust-capable dev-assets action
  revision as Amaru's current Darwin release workflow.

## Non-Goals

- Do not change Linux release behavior.
- Do not trigger a real publish-mode release workflow for this ticket.
- Do not make Cabal version and release-please version the same scheme.
