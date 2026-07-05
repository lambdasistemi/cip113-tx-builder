# Issue 54 - Freeze/Seize Real Transaction Tasks

## Slice 1 - Real freeze/seize CLI paths and smoke

- [x] T054-S1 Add freeze/seize node-only deployment plumbing in `exe/Main.hs`,
      preserving register and transfer behavior.
- [x] T054-S1 Add `--change-address` and node-provider entry points in
      `exe/Cardano/CIP113/CLI/Command/Freeze.hs` and
      `exe/Cardano/CIP113/CLI/Command/Seize.hs`.
- [x] T054-S1 Replace the placeholder real-build output with real
      `thirdPartyTx` construction and definite unsigned Conway body CBOR hex for
      both commands.
- [x] T054-S1 Use `findNode` to resolve the registered token's registry
      proof/reference-input index from live registry UTxOs.
- [x] T054-S1 Add CLI subprocess e2e smokes for both freeze and seize that
      locally insert a compatible registry node, fund a smart wallet, run the
      command, sign, submit, and assert `Submitted`.
- [x] T054-S1 Wire the new smoke into the e2e suite/package registration and
      document the freeze/seize node-only constraint in `docs/cli.md`.
- [x] T054-S1 Pass focused checks and `./gate.sh`, then commit with the
      required trailer.

## Finalization

- [x] T054-V1 Update the draft PR body with delivered behavior and verification
      evidence.
- [x] T054-V1 Run final `./gate.sh`.
- [x] T054-V1 Check off finalization boxes in this task file.
- [x] T054-V1 Request parent merge review with a Q-file instead of self-merging.
