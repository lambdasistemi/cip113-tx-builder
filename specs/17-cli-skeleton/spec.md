# Issue #17 — CLI Skeleton

## P1 User Story

As a developer integrating `cip113-tx-builder`, I can run the CLI help
and see the `register`, `transfer`, `freeze`, and `seize` command
skeletons before command-specific transaction builders are implemented.

## Functional Requirements

- Add the CLI executable component without adding modules under `src/`.
- Provide optparse-applicative dispatch for `register`, `transfer`,
  `freeze`, and `seize`.
- Provide a global `--json` flag and pass it to every command handler.
- Document exit codes in `exe/Main.hs`: `0` success, `1` user error,
  `2` unimplemented or internal error.
- Keep all command handlers as stubs that exit with code `2`.
- Define a `UTxOProvider` typeclass in
  `exe/Cardano/CIP113/CLI/Provider.hs`.
- Add an offline provider that reads JSON compatible with
  `cardano-cli query utxo --out-file`.

## Success Criteria

- `nix build .#cip113-cli` succeeds, once the flake exposes the
  executable package.
- `fourmolu --mode check exe/` passes.
- `hlint exe/` passes.
- The help command exits `0` and lists all four subcommands.

## Non-Goals

- No command implementation beyond stubs.
- No signing, submission, or key handling.
- No node, Blockfrost, or Kupo provider backend.
- No new library modules under `src/`.
