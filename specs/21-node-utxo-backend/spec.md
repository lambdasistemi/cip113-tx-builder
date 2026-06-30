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

Q-001 approved a narrow mechanical scope expansion in the four command modules.
The implementation keeps offline `run` entry points, adds provider-parameterized
`runWithProvider` entry points, and leaves transaction-building behavior
unchanged while `Main.hs` owns node/offline provider selection.

## Test Approach

The required CI gate does not require a live Cardano node. It builds
`cip113-cli`, checks formatting and linting on `exe/`, keeps an offline smoke
for fallback behavior, and verifies node mode reports a missing socket as exit
code 1. The local final smoke also covers the issue-style flag placement:
`cip113-cli register --socket-path <missing.sock> --network-magic <magic> ...`
exits 1 with a node socket error.

A live devnet smoke remains the production boundary proof: run
`cip113-cli register --socket-path <node.sock> --network-magic <magic> ...`
against a funded devnet and retain the transcript before the draft PR is marked
ready.
