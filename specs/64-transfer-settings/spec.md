# Spec: Transfer settings parser

## User Story

As a `cip113-cli transfer` user, I want transfer options to use the shared
`opt-env-conf` settings foundation so the command has consistent CLI,
environment, and YAML config behavior without carrying dead offline parser code.

## Requirements

- `transfer` options are parsed by `Cardano.CIP113.CLI.Command.Transfer`, not
  by a temporary bridge parser in `Main.hs`.
- `Transfer.Options` contains only the real node-backed transfer settings:
  from address, to address, token name, policy id, amount, and optional change
  address.
- Transfer parsing uses shared builders from `Cardano.CIP113.CLI.Settings`.
- If no decoded generic address setting exists, add one narrowly to
  `Settings.hs` without changing existing export signatures.
- `--utxo-file` is removed from `transfer --help` and from `Transfer.Options`.
- The unreachable offline placeholder path in `Transfer.hs` is removed,
  including dead placeholder CBOR encoding helpers.
- The existing real transaction path remains node-only and continues to be
  called through `runWithNodeProvider`.
- `Register`, `Freeze`, and `Seize` are not changed.

## Success Criteria

- `cip113-cli transfer --help` exposes `--deployment`, `--socket-path`,
  `--network-magic`, `--from-address`, `--to-address`, `--token-name`,
  `--policy-id`, `--amount`, and `--change-address` with their `CIP113_*`
  environment variables and YAML config keys.
- `cip113-cli transfer --help` does not mention `--utxo-file`.
- Formatting, HLint, CLI build, and the CI-shaped e2e suite pass.

## Non-Goals

- No register/freeze/seize parser cleanup.
- No changes to deployment loading, registry logic, or transaction-building
  semantics beyond replacing parser-provided `Text` with decoded `Addr` where
  appropriate.
- No docs/tutorial changes; those belong to the serial documentation ticket.
