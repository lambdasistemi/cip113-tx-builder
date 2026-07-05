# Issue 53 - Transfer Real Transaction Tasks

## Slice 1 - Real transfer CLI path and smoke

- [ ] T053-S1 Add transfer-specific node-only deployment plumbing in `exe/Main.hs`, preserving sibling command behavior.
- [ ] T053-S1 Add `--change-address` and a node-provider transfer entry point in `exe/Cardano/CIP113/CLI/Command/Transfer.hs`.
- [ ] T053-S1 Replace the placeholder transfer CBOR map with real `transferTx` construction and definite unsigned Conway body CBOR hex output.
- [ ] T053-S1 Use `findNode` to resolve the registered token's registry proof/reference-input index from live registry UTxOs.
- [ ] T053-S1 Add a CLI subprocess e2e smoke that registers a token for real, transfers it for real, signs, submits, and asserts `Submitted`.
- [ ] T053-S1 Wire the smoke into the e2e suite/package registration and document the transfer node-only constraint in `docs/cli.md`.
- [ ] T053-S1 Pass focused checks and `./gate.sh`, then commit with the required trailer.

## Finalization

- [ ] T053-V1 Update the draft PR body with delivered behavior and verification evidence.
- [ ] T053-V1 Run final `./gate.sh`.
- [ ] T053-V1 Request parent merge review with a Q-file instead of self-merging.
