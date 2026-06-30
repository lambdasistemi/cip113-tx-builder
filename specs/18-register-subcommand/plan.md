# Issue 18 - Register Subcommand Plan

## Architecture

The `register` command remains in the existing CLI command module. It parses
the ticket-owned options, loads the offline provider, fetches the requested
registry UTxO via `queryUTxOByRef`, validates the policy id and token name, and
prints a deterministic unsigned transaction-body CBOR hex envelope.

The command must stay within the skeleton boundaries: no `exe/Main.hs` changes,
no provider typeclass changes, no `src/` changes, and no live node/indexer
backend work.

## Slice Breakdown

### Slice 1 - Register command implementation

Replace the register stub with option parsing, offline UTxO lookup, tx-body hex
construction, JSON output, and user-error handling. Add a smoke fixture under
`e2e-test/` with a matching expected exit-code file. The gate builds the CLI,
checks formatting/linting for `exe/`, and runs the smoke command against the
fixture.

## Verification

Use `./gate.sh` as the ticket gate. It proves the executable builds, the touched
CLI code is formatted and lint-clean, and the end-to-end register smoke command
exits 0 with non-empty hex output.
