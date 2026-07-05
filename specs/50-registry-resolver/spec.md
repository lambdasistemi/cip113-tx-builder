# Spec: CIP-113 Registry Resolver

## P1 User Story

As a CIP-113 transaction builder consumer, I want the current registry linked-list state resolved from fresh on-chain UTxOs and a `CIP113Deployment`, so register, transfer, freeze, and seize flows can stop relying on in-memory state from a single test run.

## Functional Requirements

- Add an exposed library module under `src/Cardano/CIP113/` for resolving registry state from `Cardano.Node.Client.Provider.Provider`.
- Query the live registry address from `CIP113Deployment.dRegistryAddr`, read inline datums from those UTxOs, and decode each registry datum with the existing `RegistryNode` `FromData` instance.
- Walk the registry linked list from `originNode` through `rnNext` until `sentinelNext`, rather than choosing arbitrary UTxOs by list order.
- Provide `findInsertionPoint` or an equivalent function that returns the predecessor `TxIn` and `RegistryNode` for a new policy key.
- Provide `findNode` or an equivalent function that returns `Nothing` for an unregistered policy key, or the registered node's `TxIn`, `RegistryNode`, and reference-input index for a registered key.
- Compute the reference-input index with the same convention currently used by `ThirdPartySpec`: the index of the registry node `TxIn` in `List.sort` of the full reference-input set the caller will include.
- Surface malformed registry state clearly: missing inline datum, datum decode failure, missing origin node, broken `rnNext` link, or traversal cycle must not be reported as "not found".
- Prove behavior against the live devnet harness by deploying CIP-113, inserting at least one registry node through an actual transaction, then querying fresh registry UTxOs independently and resolving both the inserted node and the next insertion predecessor from the fresh query alone.

## Success Criteria

- The resolver API is exposed from the library and added to `cip113-tx-builder.cabal`.
- The new e2e spec deploys with `withCIP113Devnet`, performs a real registry insert, discards the in-memory insert result for resolution, re-queries `dRegistryAddr`, and asserts the resolver finds the expected node/predecessor.
- The existing `RegisterSpec.hs` and `ThirdPartySpec.hs` scenarios are not edited.
- No CLI files under `exe/` are changed.
- `./gate.sh` passes locally at HEAD.

## Non-Goals

- No CLI command wiring or provider adapter changes under `exe/`.
- No changes to `Cardano.CIP113.Deployment` unless a hard blocker is escalated first.
- No on-chain validator or blueprint changes.
- No replacement of the existing register, transfer, freeze, or seize transaction builders.
