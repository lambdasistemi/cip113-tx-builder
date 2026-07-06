# Spec: Freeze/seize settings parsers

## User Story

As a `cip113-cli freeze` or `cip113-cli seize` user, I want those commands to
use the shared `opt-env-conf` settings foundation so the remaining real
transaction flags behave consistently across CLI arguments, `CIP113_*`
environment variables, and YAML config files.

## Requirements

- `freeze` options are parsed by `Cardano.CIP113.CLI.Command.Freeze.parser`,
  not by a temporary bridge parser in `Main.hs`.
- `seize` options are parsed by `Cardano.CIP113.CLI.Command.Seize.parser`, not
  by a temporary bridge parser in `Main.hs`.
- `Freeze.Options` contains only the real node-backed freeze settings: target
  address, token name, policy id, and optional change address.
- `Seize.Options` contains only the real node-backed seize settings: target
  address, destination address, token name, policy id, and optional change
  address.
- Freeze and seize parsers use shared builders from
  `Cardano.CIP113.CLI.Settings`; target and destination addresses use
  `addressAddrSetting`, and change address uses `changeAddressAddrSetting`.
- `--utxo-file` is removed from `freeze --help`, `seize --help`, and both
  `Options` records.
- The unreachable offline placeholder paths and dead placeholder CBOR encoding
  helpers are removed from `Freeze.hs` and `Seize.hs`.
- Duplicated local parser/validation helpers that now live in `Settings.hs` are
  removed from `Freeze.hs` and `Seize.hs`.
- Real transaction-building helpers that are not settings, including
  `largeFeeUtxos`, remain local where still used.
- `Register.hs`, `Transfer.hs`, `Settings.hs`, `Deployment`, and `Registry` are
  not modified by this ticket.

## Success Criteria

- `cip113-cli freeze --help` exposes `--deployment`, `--socket-path`,
  `--network-magic`, `--target-address`, `--token-name`, `--policy-id`, and
  `--change-address` with opt-env-conf env/config behavior.
- `cip113-cli seize --help` exposes `--deployment`, `--socket-path`,
  `--network-magic`, `--target-address`, `--to-address`, `--token-name`,
  `--policy-id`, and `--change-address` with opt-env-conf env/config behavior.
- Neither help output mentions `--utxo-file`.
- The existing `FreezeSeizeCLISpec` argv strings do not need to change.
- Fourmolu, HLint, CLI help smoke, `nix build .#e2e-tests`, and
  `./result/bin/e2e-tests` pass locally.

## Non-Goals

- No register or transfer parser cleanup.
- No changes to shared settings; #63/#64 already added the required builders.
- No changes to deployment loading, registry resolution, or transaction-building
  semantics beyond consuming decoded addresses from shared settings.
- No docs/tutorial changes; those belong to the serial documentation ticket.
