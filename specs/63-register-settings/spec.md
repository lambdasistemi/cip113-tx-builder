# Spec: Register settings parser

## User Story

As a `cip113-cli register` user, I want register options to use the shared
`opt-env-conf` settings foundation so the command has the same CLI, environment,
and YAML config behavior as the rest of the migrated CLI without carrying dead
offline parser code.

## Requirements

- `register` options are parsed by `Cardano.CIP113.CLI.Command.Register`, not
  by a temporary bridge parser in `Main.hs`.
- `Register.Options` contains only the real node-backed register settings:
  token name, policy id, and optional change address.
- Register parsing uses the shared builders from
  `Cardano.CIP113.CLI.Settings` for token name, policy id, and change address.
- `--utxo-file` and `--registry-utxo` are removed from `register --help` and
  from `Register.Options`.
- The unreachable offline placeholder path in `Register.hs` is removed,
  including dead placeholder CBOR encoding helpers.
- The existing real transaction path remains node-only and continues to be
  called through `runWithNodeProvider`.
- `Transfer`, `Freeze`, and `Seize` bridge parsers remain untouched for #64 and
  #65.

## Success Criteria

- `cip113-cli register --help` exposes `--deployment`, `--socket-path`,
  `--network-magic`, `--token-name`, `--policy-id`, and `--change-address`
  with their `CIP113_*` environment variables and YAML config keys.
- `cip113-cli register --help` does not mention `--utxo-file` or
  `--registry-utxo`.
- Formatting, HLint, CLI build, and the CI-shaped e2e suite pass.

## Non-Goals

- No transfer/freeze/seize parser cleanup.
- No changes to `Settings.hs`, deployment loading, registry logic, or
  transaction-building semantics.
- No docs/tutorial changes; those belong to the serial documentation ticket.
