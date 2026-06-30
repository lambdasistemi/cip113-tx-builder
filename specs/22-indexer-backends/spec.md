# Issue 22 - Indexer UTxO Provider Backends

## P1 User Story

As a browser-side or lightweight backend developer, I can add
`--blockfrost-project-id <id>` or `--kupo-url <url>` to any `cip113-cli`
subcommand and have the CLI fetch the required UTxOs from an indexer instead
of a local node or offline JSON file.

## Requirements

- `--blockfrost-project-id` is a provider flag accepted globally and after the
  `register`, `transfer`, `freeze`, and `seize` subcommands.
- `--kupo-url` is a provider flag accepted globally and after all four
  subcommands.
- Provider precedence follows the parent brief: node wins when `--socket-path`
  is present, then Blockfrost, then Kupo, then offline `--utxo-file`.
- Blockfrost mode authenticates with the `project_id` HTTP header and derives
  the Cardano network endpoint from the project id prefix
  (`mainnet`, `preprod`, or `preview`).
- Kupo mode queries the configured HTTP base URL with `/matches/{pattern}` and
  the `?unspent` flag.
- Both indexer providers implement the existing `UTxOProvider` typeclass.
- Both indexer providers convert lovelace and native assets into the CLI-local
  `UTxOValue` shape. Native asset names are decoded from hex to UTF-8, matching
  the node provider's token-name behavior.
- An unreachable service, HTTP error response, invalid JSON response, or
  unsupported Blockfrost project id prefix exits with code 1 and a clear
  user-facing error.
- The CLI continues to produce unsigned transaction-body CBOR hex only. It
  never signs, submits, or holds keys.
- The existing `--json` output flag continues to thread through command
  execution.
- Internal/unimplemented failures remain exit code 2; user errors remain exit
  code 1.

## Non-Goals

- No transaction submission.
- No Ogmios-only backend.
- No changes to the command modules, `src/`, or `flake.nix`.
- No live Blockfrost or Kupo service requirement in CI.

## Scope Note

The live issue body still mentions older Blockfrost flag names and Kupo-before-
Blockfrost precedence. This ticket follows the parent ticket brief as the
current contract: `--blockfrost-project-id`, `--kupo-url`, and node >
Blockfrost > Kupo > offline precedence.

`Main.hs` on `origin/setup` does not already parse the Blockfrost or Kupo flags.
The implementation will add them to the existing provider option parser and
reuse the command modules' already-provider-parameterized `runWithProvider`
entry points.

## Test Approach

The CI gate does not require live indexer services. It builds `cip113-cli`,
checks formatting and linting under `exe/`, keeps the existing offline fallback
smoke, and keeps the existing missing-node smoke.

Indexer-specific proof uses a documented missing-service smoke:

- Kupo: run a subcommand with `--kupo-url http://127.0.0.1:<unused-port>` and
  verify exit code 1 plus a Kupo/unreachable error.
- Blockfrost: verify unsupported project id prefixes fail locally with exit
  code 1, and retain an operator follow-up for a real `mainnet`, `preprod`, or
  `preview` project id against the corresponding live Blockfrost endpoint.

The live-boundary follow-up before ready-for-review is:
`cip113-cli register --blockfrost-project-id <project-id> ...` or
`cip113-cli register --kupo-url <url> ...` against a funded/indexed testnet
UTxO, retaining the transcript outside CI.
