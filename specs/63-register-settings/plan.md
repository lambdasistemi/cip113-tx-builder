# Plan: Register settings parser

## Context

#62 merged the `opt-env-conf` foundation and temporarily kept
`registerOptionsParser` in `Main.hs`. This ticket replaces that bridge with a
real parser exported by `Register.hs` and deletes register-only offline
placeholder code.

## Slice 1 - register parser relocation

Owned files:

- `exe/Cardano/CIP113/CLI/Command/Register.hs`
- `exe/Main.hs`

Work:

- Add or keep `Register.parser :: OptEnvConf.Parser Register.Options`.
- Build the parser from `tokenNameSetting`, `policyIdSetting`, and
  `optional changeAddressSetting`.
- Remove `optionsUtxoFile` and `optionsRegistryUtxo` from `Register.Options`.
- Delete the unreachable offline `run`, `runWithProvider`,
  `loadProviderOrExit`, `buildRegisterTxHex`, UTxO-ref parser/formatting, and
  placeholder CBOR helpers.
- Delete duplicated token-name, policy-id, address, hex, and large-fee helpers
  that now belong to `Settings.hs`.
- Wire `Main.hs` to call `Register.parser` and leave the
  transfer/freeze/seize bridge parsers unchanged.

Proof:

- RED: demonstrate that current `register --help` still exposes
  `--utxo-file` or `--registry-utxo`.
- GREEN: `register --help` hides those flags while retaining flag/env/config
  output for the remaining register settings.
- Full `./gate.sh` passes.

## Slice 2 - finalization

Owned by the ticket orchestrator:

- Re-run `./gate.sh` at HEAD.
- Update the PR body with help output evidence and verification results.
- Drop `gate.sh`.
- Mark the PR ready and write a merge-review Q-file for the epic owner.
