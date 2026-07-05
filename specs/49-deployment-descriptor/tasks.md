# Tasks: CIP-113 Deployment Descriptor

## Slice 1: Pure Descriptor Extraction

- [ ] T049-S1 Add exposed module `Cardano.CIP113.Deployment` with `CIP113Deployment` and pure `computeDeployment`.
- [ ] T049-S1 Move descriptor-only helper logic out of `Deploy.hs` without changing the derivation chain.
- [ ] T049-S1 Refactor `deployCIP113` to call `computeDeployment` after bootstrap seed selection while keeping its IO transaction flow unchanged.
- [ ] T049-S1 Add the new exposed module to `cip113-tx-builder.cabal`.
- [ ] T049-S1 Run `./gate.sh`.
- [ ] T049-S1 Commit the slice as `feat: extract CIP-113 deployment descriptor` with `Tasks: T049-S1`.

## Slice 2: JSON Round-Trip

- [ ] T049-S2 Add JSON serialization/deserialization for `CIP113Deployment` using stable byte encodings for scripts, hashes, policies, and addresses.
- [ ] T049-S2 Add a pure Hspec round-trip test for a descriptor computed from the fixture blueprint and deterministic seed `TxIn`s.
- [ ] T049-S2 Wire the new test module into `e2e-tests` with only the minimal cabal and `e2e-main.hs` changes required.
- [ ] T049-S2 Run `./gate.sh`.
- [ ] T049-S2 Commit the slice as `feat: serialize CIP-113 deployment descriptor` with `Tasks: T049-S2`.

## Ticket Owner Verification

- [ ] T049-V1 Push each accepted slice to PR #55 after reviewing the driver commit and navigator verification.
- [ ] T049-V1 Verify the final `./gate.sh` run locally at HEAD.
- [ ] T049-V1 Update the PR body with delivered behavior and verification evidence.
- [ ] T049-V1 Drop `gate.sh` in the final ready-for-review commit.
- [ ] T049-V1 Mark PR #55 ready for review.
