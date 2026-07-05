# Issue 52 - Register Real Transaction Tasks

## Slice 1 - Node-only deployment plumbing

- [X] T052-S1 Load `--deployment` into a value that can be passed to the register command path.
- [X] T052-S1 Add a register-specific node-provider branch in `exe/Main.hs` and clear exit-1 errors for missing deployment or non-node real register builds.
- [X] T052-S1 Preserve sibling command behavior and avoid edits to transfer/freeze/seize modules.
- [X] T052-S1 Pass the focused CLI build/lint command and commit with the required trailer.

## Slice 2 - Real register builder output

- [X] T052-S2 Replace `buildRegisterTxHex` placeholder output with real `registerTx` construction.
- [X] T052-S2 Use `findInsertionPoint` to resolve the predecessor from live registry UTxOs.
- [X] T052-S2 Construct updated predecessor, new node, and `RegistryInsert` datum/redeemer values from resolved chain state.
- [X] T052-S2 Emit real unsigned Conway transaction-body CBOR hex in plain and JSON modes.
- [X] T052-S2 Pass the focused register build command and `./gate.sh`, then commit with the required trailer.

## Slice 3 - CLI e2e smoke and docs

- [X] T052-S3 Add a CLI subprocess e2e smoke that pipes `register` output through `sign`, submits through the N2C submitter, and asserts `Submitted`.
- [X] T052-S3 Wire the new smoke into the e2e test suite/package registration.
- [X] T052-S3 Document the node-only `register --deployment` constraint in `docs/cli.md`.
- [X] T052-S3 Pass `./gate.sh` and commit with the required trailer.

## Finalization

- [ ] T052-V1 Update PR #58 body with delivered behavior and verification evidence.
- [ ] T052-V1 Run final `./gate.sh`.
- [ ] T052-V1 Request parent merge review with a Q-file instead of self-merging.
