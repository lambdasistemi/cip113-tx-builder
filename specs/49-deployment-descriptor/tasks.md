# Tasks: CIP-113 Deployment Descriptor

## Slice 1: Pure Descriptor Extraction

- [X] T049-S1 Add exposed module `Cardano.CIP113.Deployment` with `CIP113Deployment` and pure `computeDeployment`.
- [X] T049-S1 Move descriptor-only helper logic out of `Deploy.hs` without changing the derivation chain.
- [X] T049-S1 Refactor `deployCIP113` to call `computeDeployment` after bootstrap seed selection while keeping its IO transaction flow unchanged.
- [X] T049-S1 Add a pure Hspec descriptor test that fails before `Cardano.CIP113.Deployment` exists and passes without starting a devnet.
- [X] T049-S1 Wire the new exposed module and pure test module into `cip113-tx-builder.cabal` / `e2e-main.hs`.
- [X] T049-S1 Run `./gate.sh`.
- [X] T049-S1 Commit the slice as `feat: extract CIP-113 deployment descriptor` with `Tasks: T049-S1`.

## Slice 2: JSON Round-Trip

- [X] T049-S2 Add JSON serialization/deserialization for `CIP113Deployment` using stable byte encodings for scripts, hashes, policies, and addresses.
- [X] T049-S2 Extend the pure descriptor spec with an encode/decode round-trip for a descriptor computed from the fixture blueprint and deterministic seed `TxIn`s.
- [X] T049-S2 Run `./gate.sh`.
- [X] T049-S2 Commit the slice as `feat: serialize CIP-113 deployment descriptor` with `Tasks: T049-S2`.

## Ticket Owner Verification

- [ ] T049-V1 Push each accepted slice to PR #55 after reviewing the driver commit and navigator verification.
- [ ] T049-V1 Verify the final `./gate.sh` run locally at HEAD.
- [ ] T049-V1 Update the PR body with delivered behavior and verification evidence.
- [ ] T049-V1 Drop `gate.sh` in the final ready-for-review commit.
- [ ] T049-V1 Mark PR #55 ready for review.
