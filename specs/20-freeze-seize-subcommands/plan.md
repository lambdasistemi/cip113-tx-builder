# Issue 20 - Freeze and Seize Subcommands Plan

## Architecture

The `freeze` and `seize` commands remain in their existing CLI command
modules. Each command parses only the ticket-owned options, loads the
offline provider, fetches target UTxOs via `queryUTxOsByAddress`,
selects UTxOs carrying the requested policy/token pair, and prints a
deterministic unsigned third-party transaction-body CBOR hex envelope.

The implementation should mirror the `Register.hs` and `Transfer.hs`
style: local option parsers, local user-error exits, no provider
typeclass changes, no live node/indexer backend, and JSON output only
through the global flag already threaded by `Main`.

`freeze` and `seize` share the same target-input selection mechanics.
`freeze` records the target address as the frozen destination in the
unsigned envelope. `seize` records both the target address and
`--to-address` destination in the unsigned envelope.

## Slice Breakdown

### Slice 1 - Freeze and seize command implementation

Replace both command stubs with option parsing, offline UTxO lookup,
token presence validation, tx-body hex construction, JSON output, and
user-error handling. Add freeze and seize smoke UTxO fixtures plus
expected exit-code files under `e2e-test/fixtures/`. The gate builds the
CLI, checks formatting/linting for `exe/`, and runs human plus JSON
smoke commands for both subcommands against the fixtures.

## Verification

Use `./gate.sh` as the ticket gate. It proves the executable builds, the
touched CLI code is formatted and lint-clean, and the freeze/seize smoke
commands exit 0 with non-empty hex output in both human and JSON modes.
