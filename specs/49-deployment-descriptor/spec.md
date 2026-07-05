# Spec: CIP-113 Deployment Descriptor

## P1 User Story

As a CIP-113 transaction builder consumer, I want the deployed protocol scripts, hashes, policies, and addresses to be derivable from a blueprint plus the three deployment seed UTxOs without talking to a chain, so a deployment can be recorded once and reused by CLI and resolver code later.

## Functional Requirements

- Add a pure library function in `src/Cardano/CIP113/` that computes the full CIP-113 deployment descriptor from a `Blueprint` and three seed `TxIn`s.
- Preserve the exact derivation chain currently in `e2e-test/Cardano/CIP113/E2E/Deploy.hs::deployCIP113`: `always_fail`, `protocol_params_mint`, `programmable_logic_global`, `programmable_logic_base`, `unfracking`, `issuance_cbor_hex_mint`, `registry_spend`, `registry_mint`, `issuance_mint`, and the third-party publish script.
- Move or expose the descriptor record from library code with all fields currently carried by the e2e `CIP113Deployment` record.
- Refactor `deployCIP113` so its IO remains limited to bootstrap UTxO creation, protocol parameter/registry/issuance minting, registry origin initialization, and PLG reward-account registration; deterministic descriptor derivation must delegate to the pure library function.
- Add JSON serialization and deserialization for the descriptor using stable byte encodings for ledger values that do not have local JSON instances.
- Add a round-trip test proving `decode . encode` preserves the descriptor values derived from the fixture blueprint and deterministic synthetic seed `TxIn`s.

## Success Criteria

- The new pure function has no IO in its type and does not query or submit to a chain.
- The e2e deployment harness no longer duplicates the deterministic script derivation chain inline.
- JSON round-trip preserves script hashes, policy IDs, addresses, and scripts needed by downstream consumers.
- `nix build .#e2e-tests && ./result/bin/e2e-tests` passes locally.
- `fourmolu` and `hlint` pass through `./gate.sh`.

## Non-Goals

- No CLI command wiring under `exe/`.
- No live registry linked-list state resolution.
- No changes to the on-chain Aiken blueprint or validator semantics.
- No changes to `RegisterSpec.hs` or `ThirdPartySpec.hs` test scenarios beyond the import path changes required by the deployment refactor.
