# Issue 19 - Transfer Subcommand Tasks

## Slice 1 - Transfer command implementation

- [X] T019-S1 Parse `transfer` options and validate user input.
- [X] T019-S1 Load the offline UTxO provider and return exit 1 when the sender has no matching spendable token UTxOs.
- [X] T019-S1 Build and print deterministic unsigned transfer CBOR hex, including JSON output when `--json` is set.
- [X] T019-S1 Add transfer smoke UTxO and expected exit-code fixtures under `e2e-test/fixtures/`.
- [X] T019-S1 Pass `./gate.sh` and commit with the required trailer.
