# Tasks: opt-env-conf Foundation

## Slice 1 - dependency probe

- [X] T6201 Add `opt-env-conf` to the `cip113-cli` executable dependencies.
- [X] T6202 Verify `nix build .#cip113-cli --no-link --print-build-logs` resolves under the pinned Nix package set.

## Slice 2 - parser foundation

- [ ] T6203 Add `Cardano.CIP113.CLI.Settings` with deployment, node connection, change address, token name, and policy id settings.
- [ ] T6204 Register the new module in `cip113-tx-builder.cabal`.
- [ ] T6205 Rewrite `Main.hs` on `opt-env-conf` commands/config-file wiring and remove `ProviderOptions` manual merging.
- [ ] T6206 Convert `sign` and `vault seal` onto the new parser stack without changing runtime behavior.
- [ ] T6207 Verify help output exposes CLI flag, env var, and config key information.

## Slice 3 - finalization

- [ ] T6208 Run fourmolu, hlint, `nix build .#e2e-tests`, and the CI-shaped e2e invocation.
- [ ] T6209 Update the PR body with help-output evidence and verification results.
- [ ] T6210 Write a merge-review Q-file for the epic owner instead of self-merging.
