# Plan: Transfer settings parser

## Context

#62 added the `opt-env-conf` foundation and #63 converted register. This ticket
removes the temporary transfer bridge parser from `Main.hs`, moves transfer
parsing into `Transfer.hs`, and deletes transfer-only offline placeholder code.

## Slice 1 - transfer parser relocation

Owned files:

- `exe/Cardano/CIP113/CLI/Command/Transfer.hs`
- `exe/Main.hs`
- `exe/Cardano/CIP113/CLI/Settings.hs` (narrow additive decoded-address
  setting only, if needed)

Work:

- Export `Transfer.parser :: OptEnvConf.Parser Transfer.Options`.
- Build the parser from shared settings builders.
- Add an address setting helper returning decoded `Addr` if needed for
  `from-address` and `to-address`; do not change existing `Settings.hs` export
  signatures because freeze/seize still consume the `Text` helpers.
- Use `changeAddressAddrSetting` for transfer's change address.
- Remove `optionsUtxoFile` from `Transfer.Options`.
- Delete unreachable offline `run`, `runWithProvider`, `loadProviderOrExit`,
  placeholder transfer CBOR helpers, and UTxO-file parsing.
- Delete duplicated transfer parser/validation helpers that have moved to
  `Settings.hs`.
- Keep `largeFeeUtxos` and `sourceAuthorization` local if still used by the real
  node-backed transfer path.
- Keep runtime policy-id decoding and transaction serialization helpers local
  if still needed by transaction construction.
- Wire `Main.hs` to call `Transfer.parser` and leave freeze/seize bridge
  parsers unchanged.

Proof:

- RED: demonstrate current `transfer --help` still exposes `--utxo-file`.
- GREEN: `transfer --help` hides `--utxo-file` while retaining flag/env/config
  output for remaining transfer settings.
- Full `./gate.sh` passes.

## Slice 2 - finalization

Owned by the ticket orchestrator:

- Re-run `./gate.sh` at HEAD.
- Update the PR body with help output evidence and verification results.
- Drop `gate.sh`.
- Mark the PR ready and write a merge-review Q-file for the epic owner.
