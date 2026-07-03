# Implementation Plan: Vault Seal and Sign CLI

## Context

Issue #39 adds CLI wiring only. The upstream `cardano-wallet-tools` library at
`cf70a316573d8e2b97134a856e2f9e9869925efb` exposes:

- `Cardano.Wallet.Tools.Cli.Vault.signingKeySourceParser`
- `loadSignerFromSource`, `promptPassphrase`, `mkVaultPassphrase`,
  `encryptVault`, `defaultWorkFactor`, `renderVaultError`
- `Cardano.Wallet.Tools.Sign.transactionBodyBytes`, `signTxBody`,
  `attachWitnesses`

The upstream fixed-output hash for `source-repository-package` is
`1qsx10wrd1qmqzir6vr1zbf56b64qfynaw92ah60dr0a34pb3zcd`.

## Slices

### Slice 1: Dependency Wiring

Add `cardano-wallet-tools` as a pinned source repository package in
`cabal.project`, and add it to the `cip113-cli` executable build-depends only.
The slice proves the dependency graph resolves before CLI code depends on it.

Owned files:

- `cabal.project`
- `cip113-tx-builder.cabal`

### Slice 2: CLI Commands

Add executable modules for `cip113 vault seal` and `cip113 sign`, then wire them
into `exe/Main.hs`. The implementation mirrors upstream `cwt` pipe semantics:
strip trailing whitespace from stdin, decode CBOR hex, extract body bytes, sign,
attach the witness, and write hex to stdout.

Owned files:

- `exe/Main.hs`
- `exe/Cardano/CIP113/CLI/Command/Seal.hs`
- `exe/Cardano/CIP113/CLI/Command/Sign.hs`
- `cip113-tx-builder.cabal`

## Verification

- `./gate.sh` after each slice.
- CLI help smoke after Slice 2:
  `nix run .#cip113-cli -- --help`,
  `nix run .#cip113-cli -- vault seal --help`, and
  `nix run .#cip113-cli -- sign --help`.
