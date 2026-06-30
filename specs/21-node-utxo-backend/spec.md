# Issue 21 - Node UTxO Backend

## P1 User Story

As a node operator, I can add `--socket-path /run/cardano-node/node.socket`
and `--network-magic 2` to any `cip113-cli` subcommand and have the CLI fetch
the required UTxOs from my local Cardano node instead of an offline JSON file.

## Requirements

- `--socket-path` and `--network-magic` are global CLI flags accepted for
  `register`, `transfer`, `freeze`, and `seize`.
- When both node flags are present, the node provider is selected
  automatically.
- When node flags are absent, existing offline `--utxo-file` behavior remains
  the fallback.
- A missing socket path in node mode exits with code 1 and a clear user-facing
  error.
- Node mode queries UTxOs through the node-to-client LocalStateQuery path using
  the existing Cardano package set.
- Node mode never signs, submits, or holds keys. It only supplies UTxOs to the
  existing unsigned transaction-body builders.
- The existing `--json` output flag continues to thread through command
  execution.
- Internal/unimplemented failures remain exit code 2; user errors remain exit
  code 1.

## Non-Goals

- No Blockfrost, Kupo, or indexer provider.
- No transaction submission.
- No change to CIP-113 transaction-building semantics.
- No changes under `src/` or `flake.nix`.

## Scope Note

The current `origin/setup` command modules require `--utxo-file` and load
`OfflineUTxOProvider` internally. Clean node selection therefore needs a narrow
scope decision before implementation touches command modules. The ticket owner
wrote `/tmp/epic-23/cip113-tx-builder-21/questions/Q-001-provider-wiring-scope.md`
and recommends allowing a mechanical provider-injection refactor in the four
command modules.

## Test Approach

The required CI gate does not require a live Cardano node. It builds
`cip113-cli`, checks formatting and linting on `exe/`, keeps an offline smoke
for fallback behavior, and verifies node mode reports a missing socket as exit
code 1. A live devnet smoke remains the production boundary proof: run
`cip113-cli --socket-path <node.sock> --network-magic <magic> register ...`
against a funded devnet and retain the transcript before the PR leaves draft.
