# Issue 53 - Transfer Real Transaction Tasks

## Slice 1 - Real transfer CLI path and smoke

- [X] T053-S1 Add transfer-specific node-only deployment plumbing in `exe/Main.hs`, preserving sibling command behavior.
- [X] T053-S1 Add `--change-address` and a node-provider transfer entry point in `exe/Cardano/CIP113/CLI/Command/Transfer.hs`.
- [X] T053-S1 Replace the placeholder transfer CBOR map with real `transferTx` construction and definite unsigned Conway body CBOR hex output.
- [X] T053-S1 Use `findNode` to resolve the registered token's registry proof/reference-input index from live registry UTxOs.
- [X] T053-S1 Add a CLI subprocess e2e smoke that locally inserts a transfer-test registry node, transfers it for real, signs, submits, and asserts `Submitted`.
- [X] T053-S1 Wire the smoke into the e2e suite/package registration and document the transfer node-only constraint in `docs/cli.md`.
- [X] T053-S1 Pass focused checks and `./gate.sh`, then commit with the required trailer.

## Finalization

- [X] T053-V1 Update the draft PR body with delivered behavior and verification evidence.
- [X] T053-V1 Run final `./gate.sh`.
- [X] T053-V1 Request parent merge review with a Q-file instead of self-merging.
