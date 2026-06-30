# Issue 20 - Freeze and Seize Subcommands Tasks

## Slice 1 - Freeze and seize command implementation

- [ ] T020-S1 Parse `freeze` and `seize` options and validate user input.
- [ ] T020-S1 Load the offline UTxO provider and return exit 1 when the target address has no matching token UTxOs.
- [ ] T020-S1 Build and print deterministic unsigned freeze/seize CBOR hex, including JSON output when `--json` is set.
- [ ] T020-S1 Add freeze and seize smoke UTxO fixtures plus expected exit-code fixtures under `e2e-test/fixtures/`.
- [ ] T020-S1 Pass `./gate.sh` and commit with the required trailer.
