# Issue 81 Tasks

## Slice 1 - Darwin release tag contract

- [ ] T8101 Remove the Cabal-derived `releaseTag` default from
      `nix/darwin-release.nix`.
- [ ] T8102 Pass the release-please tag explicitly from `flake.nix` to the
      release-mode Darwin artifact package.
- [ ] T8103 Add a release-tag verifier script for the Darwin formula URL and
      wire it into `.github/workflows/darwin-release.yml` as the
      `release-check-command`.
- [ ] T8104 Prove the live `v0.1.2` Darwin asset URL resolves from the generated
      release package metadata, while `dev-homebrew` remains unchanged.
- [ ] T8105 Run `./gate.sh` and commit the slice with the required `Tasks:`
      trailer.
