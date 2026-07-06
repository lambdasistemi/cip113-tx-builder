# Plan: Distribution flake prerequisites

## Context

Epic #72 will add binary distribution for `cip113-cli`. This first child only
prepares the flake outputs that later Linux and Darwin workflow tickets will
call.

Amaru's `nix/linux-release.nix` exists and is the direct Linux template. Its
Darwin release logic currently lives inline in Amaru's `flake.nix`, so this
ticket extracts that shape into the requested `nix/darwin-release.nix` file for
this repo.

## Slice 1 - release flake outputs

Owned files:

- `flake.nix`
- `flake.lock`
- `nix/linux-release.nix`
- `nix/darwin-release.nix`

Work:

- Add `aarch64-darwin` to `systems`.
- Add the `bundlers` input, following `nixpkgs`.
- Add package-version and dev-artifact-version values derived from
  `cip113-tx-builder.cabal` and the current flake revision.
- Wrap the `cip113-cli` executable in a `symlinkJoin` with
  `meta.mainProgram = "cip113-cli"` for the NixOS bundlers.
- Import `nix/linux-release.nix` under Linux-only package attrs for release and
  dev artifact outputs.
- Import `nix/darwin-release.nix` under Darwin-only package attrs for release
  and dev Homebrew outputs.
- Keep the existing `cip113-cli` package output name usable for normal builds.

Proof:

- Run `./gate.sh`.
- Confirm the gate builds `.#cip113-cli` and evaluates all four release output
  names.

## Slice 2 - finalization

Owned by the ticket orchestrator:

- Review the implementation commit and task accounting.
- Re-run `./gate.sh` at HEAD.
- Update the PR body with delivered behavior and verification evidence.
- Drop `gate.sh`.
- Mark the draft PR ready for review.
- Tell the epic owner the merge method for this repo is `merge`, not squash.
