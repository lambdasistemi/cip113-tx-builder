# Plan: Freeze/seize settings parsers

## Context

#62 added the shared `opt-env-conf` settings foundation, #63 converted
register, and #64 converted transfer. This ticket is the final CLI-wiring child:
it removes the freeze/seize temporary bridge parsers from `Main.hs`, moves
parsing into each command module, and deletes the remaining dead offline
placeholder code in those modules.

## Slice 1 - freeze/seize parser relocation

Owned files:

- `exe/Cardano/CIP113/CLI/Command/Freeze.hs`
- `exe/Cardano/CIP113/CLI/Command/Seize.hs`
- `exe/Main.hs`

Work:

- Build `Freeze.parser` and `Seize.parser` from shared settings builders.
- Use `addressAddrSetting` for `target-address` and `to-address` so command
  options carry decoded `Addr` values directly.
- Use `tokenNameSetting`, `policyIdSetting`, and optional
  `changeAddressAddrSetting` for the remaining settings.
- Remove `optionsUtxoFile` from both `Options` records.
- Remove offline-only `run`, `runWithProvider`, and UTxO-file loading paths if
  they are unreachable after `--utxo-file` is removed.
- Delete duplicated helpers now supplied by `Settings.hs`:
  `parseTokenNameArgument`, `parsePolicyIdArgument`, `parseCardanoAddress`,
  `decodeBech32Address`, `decodeHexText`, `hexText`, and
  `sourceAuthorization` where no longer used.
- Delete the placeholder CBOR map/array/text/integer/hex encoding helpers and
  their callers.
- Keep `largeFeeUtxos` local in both command modules.
- Wire `Main.hs` to use `Freeze.parser` and `Seize.parser`, then remove now
  unused bridge-parser imports from `Main.hs`.

Proof:

- RED: demonstrate the current help output still exposes `--utxo-file`.
- GREEN: `freeze --help` and `seize --help` hide `--utxo-file` while retaining
  the remaining command-specific flags.
- Full `./gate.sh` passes.

## Slice 2 - finalization

Owned by the ticket orchestrator:

- Re-run `./gate.sh` at HEAD.
- Update the PR body with help-output evidence and verification results.
- Drop `gate.sh`.
- Mark the PR ready and write a merge-review Q-file for the epic owner.
