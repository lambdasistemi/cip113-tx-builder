# Tasks: Vault Seal and Sign CLI

## Slice 1: Dependency Wiring

- [ ] T039-S1 Add pinned `cardano-wallet-tools` source repository package.
- [ ] T039-S1 Add executable-only `cardano-wallet-tools` build dependency.
- [ ] T039-S1 Run `./gate.sh` and commit dependency wiring.

## Slice 2: CLI Commands

- [ ] T039-S2 Add `vault seal` command module delegating vault crypto upstream.
- [ ] T039-S2 Add `sign` command module reusing upstream key parser and signer.
- [ ] T039-S2 Wire `vault seal` and `sign` into `exe/Main.hs`.
- [ ] T039-S2 Register new executable modules in `cip113-tx-builder.cabal`.
- [ ] T039-S2 Run `./gate.sh`, help smokes, and commit CLI wiring.
