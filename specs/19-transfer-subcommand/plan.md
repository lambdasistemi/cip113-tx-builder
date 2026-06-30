# Issue 19 - Transfer Subcommand Plan

## Architecture

The `transfer` command remains in the existing CLI command module. It
parses the ticket-owned options, loads the offline provider, fetches
sender UTxOs via `queryUTxOsByAddress`, selects UTxOs carrying the
requested policy/token pair, validates the requested amount, and prints
a deterministic unsigned transfer transaction-body CBOR hex envelope.

The command mirrors the `register` implementation style: local option
parsers, local user-error exits, no provider typeclass changes, no live
node/indexer backend, and JSON output only through the global flag
threaded by `Main`.

## Slice Breakdown

### Slice 1 - Transfer command implementation

Replace the transfer stub with option parsing, offline UTxO lookup,
token balance validation, tx-body hex construction, JSON output, and
user-error handling. Add a transfer smoke UTxO fixture and expected
exit-code file under `e2e-test/fixtures/`. The gate builds the CLI,
checks formatting/linting for `exe/`, and runs human plus JSON smoke
commands against the fixture.

## Verification

Use `./gate.sh` as the ticket gate. It proves the executable builds, the
touched CLI code is formatted and lint-clean, and the transfer smoke
commands exit 0 with non-empty hex output.
