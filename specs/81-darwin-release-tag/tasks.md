# Issue 81 Tasks

## Slice 1 - Darwin release tag contract

- [X] T8101 Remove the Cabal-derived `releaseTag` default from
      `nix/darwin-release.nix`.
- [X] T8102 Pass the release-please tag explicitly from `flake.nix` to the
      release-mode Darwin artifact package.
- [X] T8103 Add a release-tag verifier script for the Darwin formula URL and
      wire it into `.github/workflows/darwin-release.yml` as the
      `release-check-command`.
- [X] T8104 Prove the live `v0.1.2` Darwin asset URL resolves from the generated
      release package metadata, while `dev-homebrew` remains unchanged.
- [X] T8105 Run `./gate.sh` and commit the slice with the required `Tasks:`
      trailer.

## Slice 2 - CI version invariant correction

- [X] T8106 Replace the `CI / build` Cabal-vs-manifest equality check with a
      non-failing report of the separate Cabal artifact version and
      release-please tag.
- [X] T8107 Prove the old CI shell condition fails on current versions, the new
      workflow step succeeds, and `./gate.sh` still passes.

## Slice 3 - Darwin tap trust action pin

- [X] T8108 Repin `.github/workflows/darwin-release.yml` from
      `paolino/dev-assets/darwin-homebrew-release@6864b20...` to the
      Amaru-proven tap-trust revision `9ac7c6280196ca7cea154ec78f091e2b6481abec`.
- [X] T8109 Prove the old action revision lacks the tap-trust fix, the new
      revision includes it, and local workflow lint plus `./gate.sh` pass.
