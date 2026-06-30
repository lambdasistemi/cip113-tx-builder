# Issue 21 Tasks - Node UTxO Backend

## Slice 1 - Node Provider

- [x] T021-S1 Add `Cardano.CIP113.CLI.Provider.Node` with node config,
  bracketed N2C provider startup, socket existence validation, and a
  `UTxOProvider NodeProvider` instance.
- [x] T021-S1 Convert ledger `TxIn` and `TxOut ConwayEra` values into the
  CLI-local `UTxO`, `UTxORef`, and `UTxOValue` shapes.
- [x] T021-S1 Add only the executable dependencies required by the node
  provider and verify the provider builds.

## Slice 2 - CLI Provider Selection

- [x] T021-S2 Resolve Q-001 before editing command modules.
- [x] T021-S2 Parse global `--socket-path` and `--network-magic` flags and
  select node mode only when both are present.
- [x] T021-S2 Preserve offline fallback when node flags are absent and keep
  `--json` behavior unchanged.
- [x] T021-S2 Return exit code 1 with a clear error when exactly one node flag
  is present or the node socket path is missing.

## Slice 3 - Gate And Smoke

- [ ] T021-S3 Run `./gate.sh` and record the result.
- [ ] T021-S3 Capture the missing-socket node-mode smoke evidence.
- [ ] T021-S3 Update PR metadata with the live devnet smoke follow-up and
  final implementation notes.
