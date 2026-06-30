# Issue 18 - Register Subcommand Tasks

## Slice 1 - Register command implementation

- [X] T018-S1 Parse `register` options and validate user input.
- [X] T018-S1 Load the offline UTxO provider and return exit 1 when the requested registry UTxO is absent.
- [X] T018-S1 Build and print deterministic unsigned CBOR hex, including JSON output when `--json` is set.
- [X] T018-S1 Add a register smoke UTxO fixture and expected exit-code fixture under `e2e-test/`.
- [X] T018-S1 Pass `./gate.sh` and commit with the required trailer.
