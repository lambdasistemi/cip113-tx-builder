# Tasks: CIP-113 Registry Resolver

## Slice 1: Live Registry Resolver

- [X] T050-S1 Add exposed module `Cardano.CIP113.Registry` or equivalent with registry UTxO decoding, linked-list traversal, insertion-point resolution, existing-node lookup, and explicit malformed-state errors.
- [X] T050-S1 Add any required library dependency and exposed-module entry to `cip113-tx-builder.cabal`.
- [X] T050-S1 Add `RegistryResolverSpec` under `e2e-test/Cardano/CIP113/E2E/` and wire it into `e2e-main.hs` / the e2e test component.
- [X] T050-S1 Prove RED by running `nix build .#e2e-tests` after wiring the failing spec and before implementing the resolver.
- [X] T050-S1 Prove GREEN by running `./gate.sh`.
- [X] T050-S1 Commit the slice as `feat: add CIP-113 registry resolver` with `Tasks: T050-S1`.

## Ticket Owner Verification

- [X] T050-V1 Review the driver commit and navigator verification for owned-file scope, RED/GREEN evidence, and commit shape.
- [X] T050-V1 Amend this task file into the accepted slice commit with all `T050-S1` boxes checked.
- [X] T050-V1 Push the accepted slice to PR #56.
- [X] T050-V1 Verify the final `./gate.sh` run locally at HEAD.
- [X] T050-V1 Update the PR body with delivered behavior and verification evidence.
- [X] T050-V1 Drop `gate.sh` in the final ready-for-review commit.
- [X] T050-V1 Write a Q-file asking the epic owner to review and merge PR #56.
