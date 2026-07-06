# Spec: Distribution flake prerequisites

## User Story

As a release operator, I want the flake to expose Linux and Darwin release
artifact packages so the follow-up workflow tickets can build and publish
`cip113-cli` binaries without embedding packaging logic in GitHub Actions.

## Requirements

- `flake.nix` declares both `x86_64-linux` and `aarch64-darwin`.
- `flake.nix` adds the NixOS `bundlers` input required for AppImage, DEB, and
  RPM artifact derivations.
- `flake.nix` exposes `linux-release-artifacts` and
  `linux-dev-release-artifacts` on Linux systems.
- `flake.nix` exposes `darwin-release-artifacts` and
  `darwin-dev-homebrew-artifacts` on Darwin systems.
- `nix/linux-release.nix` stages the AppImage, DEB, RPM, and `SHA256SUMS`
  files for `cip113-cli`, adapted from `lambdasistemi/amaru-treasury-tx`.
- `nix/darwin-release.nix` stages the Darwin/Homebrew bundle for
  `cip113-cli`, adapted from Amaru's inline `mkDarwinHomebrewBundle` pattern
  and the distribution skill's current flake-owned shape.
- The Darwin bundle uses `smokeCommands = [ "cip113-cli --help >/dev/null" ]`
  because bare `cip113-cli` exits 1.
- `nix build .#cip113-cli` still succeeds after adding the extra system and
  release outputs.
- The new release outputs evaluate on Linux CI; Darwin outputs are not built on
  the Linux runner.

## Success Criteria

- `nix build .#cip113-cli --no-link --print-build-logs` exits 0.
- `nix eval .#packages.x86_64-linux.linux-release-artifacts.name --raw` exits 0.
- `nix eval .#packages.x86_64-linux.linux-dev-release-artifacts.name --raw`
  exits 0.
- `nix eval .#packages.aarch64-darwin.darwin-release-artifacts.name --raw`
  exits 0.
- `nix eval .#packages.aarch64-darwin.darwin-dev-homebrew-artifacts.name --raw`
  exits 0.
- No Haskell source changes are made.

## Non-Goals

- No GitHub Actions workflow changes.
- No release publication.
- No Homebrew tap update.
- No Linux artifact smoke app beyond the release package outputs required by
  this ticket.
