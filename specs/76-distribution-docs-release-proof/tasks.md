# Issue 76 Tasks

## Slice 1 - Install documentation

- [ ] T7601 Add the macOS Homebrew install command to `README.md`.
- [ ] T7602 Add Linux AppImage download, `chmod +x`, and `--help` guidance to
      `README.md`, with DEB/RPM noted as alternatives.
- [ ] T7603 Mirror the install guidance in `docs/index.md`.
- [ ] T7604 Run `./gate.sh` and commit the documentation update with the
      required `Tasks:` trailer.

## Slice 2 - Fresh release proof

- [ ] T7605 Trigger `release.yml` with `workflow_dispatch` mode `dev-linux`
      and confirm the run succeeds.
- [ ] T7606 Download the Linux workflow artifact on this Linux host, run the
      AppImage directly with `--help`, and confirm exit 0.
- [ ] T7607 Trigger `darwin-release.yml` with `workflow_dispatch` mode
      `dev-homebrew`, `publish=no`, and `update_tap=no`, then confirm the
      `macos-14` local-tap `brew test` run succeeds.
- [ ] T7608 Record proof links, commands, release-page applicability, and the
      Darwin CI-runner proxy boundary in `proof.md` and the PR body.
