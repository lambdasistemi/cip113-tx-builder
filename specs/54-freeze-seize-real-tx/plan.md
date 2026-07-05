# Issue 54 - Freeze/Seize Real Transactions Plan

## Architecture

`exe/Main.hs` will mirror the merged register/transfer routing for `freeze` and
`seize`: load the selected deployment, require it, reject non-node providers
with command-specific exit-1 messages, and pass a live
`Cardano.Node.Client.Provider.Provider IO` to new node-provider entry points in
the command modules.

`Freeze.hs` and `Seize.hs` will keep the existing offline placeholder path for
`run`/`runWithProvider`, but add real node-backed builders. Each builder should:

- parse target, destination/change addresses, policy id, and token name into
  ledger values;
- query funding/change UTxOs, the target smart-wallet UTxOs, registry UTxOs,
  and locked always-fail reference UTxOs;
- select target smart-wallet UTxOs carrying the requested asset;
- call `findNode deployment provider (map fst lockedUtxos) policyKey`;
- use `rrnReferenceInputIndex` from the resolved node as
  `tpRegistryNodeIdx`;
- build `ThirdPartyInput` and outputs matching the library-level
  `ThirdPartySpec` pattern;
- call `thirdPartyTx` with deployment PLB/PLG scripts, add collateral and
  required reference inputs, withdraw from the authorizing third-party account,
  balance with `--change-address`, and serialize with
  `serialize' (eraProtVerLow @ConwayEra)`.

The CLI e2e smoke should follow `TransferCLISpec` for the executable boundary
and `ThirdPartySpec` for the third-party transaction shape. Because the register
CLI's placeholder registry node credentials collide with substandard
third-party withdrawals, the smoke should locally insert the registry node with
a distinct compatible third-party credential, as #53 did for transfer.

## Slice Breakdown

### Slice 1 - Real freeze/seize CLI paths and smoke

Implement the node-only routing, real `thirdPartyTx` builders for both command
modules, registry `findNode` proof resolution, CLI subprocess e2e smokes for
both operations, package/test-suite wiring, and CLI documentation. This remains
one vertical slice because neither command is acceptance-complete without the
live executable proof.

## Verification

The ticket gate is `./gate.sh`. It runs:

- `git diff --check`
- `fourmolu -m check` over tracked Haskell files
- `hlint src exe e2e-test`
- `nix build .#cip113-cli`
- `nix build .#cardano-node`
- `nix build .#e2e-tests`
- the e2e test binary from `e2e-test/` with `CIP113_CLI` and `PATH` set as in
  GitHub Actions

Focused checks are allowed before the full gate, but the implementation slice
and finalization both require a green `./gate.sh`.
