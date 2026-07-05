# Plan: CIP-113 Deployment Descriptor

## Tech Stack

- Haskell library module under `src/Cardano/CIP113/`.
- Existing blueprint/script helpers from `Cardano.CIP113.Scripts`.
- Ledger Conway-era `Script`, `ScriptHash`, `PolicyID`, `Addr`, and `TxIn` types already used by the e2e deploy harness.
- Aeson JSON instances with base16 text for byte-oriented ledger values.
- Existing `e2e-tests` Hspec suite for both pure round-trip coverage and live devnet regression coverage.

## Slice 1: Pure Descriptor Extraction

Move the descriptor type and deterministic derivation chain into a new exposed module, `Cardano.CIP113.Deployment`.

The new function should have a pure shape equivalent to:

```haskell
computeDeployment :: Blueprint -> (TxIn, TxIn, TxIn) -> CIP113Deployment
```

The three seed inputs are, in order, the protocol-params seed, registry seed, and issuance-CBOR seed currently selected from the bootstrap split in `deployCIP113`.

The slice should relocate helper logic that is part of descriptor derivation, including issuance mint script byte derivation and the varying-script split used to build `IssuanceCborHex`. The e2e `Deploy.hs` module should import the descriptor type and function, call it after bootstrap UTxO selection, and keep only chain IO and transaction assembly locally.

## Slice 2: JSON Round-Trip

Add JSON instances or equivalent manual Aeson wiring for `CIP113Deployment`.

Use stable representations:

- Scripts: serialised ledger CBOR or another canonical byte representation that round-trips to `Script ConwayEra`.
- Script hashes and policy IDs: base16 raw hash bytes, following the existing `scriptHashBytes` / provider `policyText` style.
- Addresses: base16 `serialiseAddr` with `decodeAddrEither`.

The round-trip test should construct three deterministic synthetic `TxIn`s, load `fixtures/cip113-blueprint.json`, compute the descriptor, encode it, decode it, and assert that the decoded descriptor preserves the descriptor values needed by consumers. Keep this as a pure Hspec test module added to the existing `e2e-tests` suite.

## Verification

- Each implementation slice runs `./gate.sh` before returning.
- The ticket owner reruns `./gate.sh` after accepting each slice.
- Final local acceptance requires:

```sh
./gate.sh
```

`gate.sh` expands to `git diff --check`, `fourmolu --mode check`, `hlint`, `nix build .#e2e-tests`, and `./result/bin/e2e-tests`.
