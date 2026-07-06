# Tasks: Distribution flake prerequisites

## Slice 1 - release flake outputs

- [X] T7301 Add `aarch64-darwin` to the flake systems list.
- [X] T7302 Add the `bundlers` flake input and lock entry.
- [X] T7303 Add `nix/linux-release.nix` for `cip113-cli` AppImage, DEB, RPM,
      and `SHA256SUMS` release artifacts.
- [X] T7304 Add `nix/darwin-release.nix` for `cip113-cli` Homebrew release and
      dev artifacts, with the `--help` smoke command override.
- [X] T7305 Expose `linux-release-artifacts`, `linux-dev-release-artifacts`,
      `darwin-release-artifacts`, and `darwin-dev-homebrew-artifacts` from
      `flake.nix`.
- [X] T7306 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [ ] T7307 Re-run `./gate.sh` at HEAD and update PR verification metadata.
- [ ] T7308 Drop `gate.sh` and mark the PR ready.
