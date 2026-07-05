# Plan: CIP-113 Registry Resolver

## Tech Stack

- Haskell library module under `src/Cardano/CIP113/`, exposed by `cip113-tx-builder.cabal`.
- `Cardano.CIP113.Deployment.CIP113Deployment` for the registry address and policy.
- `Cardano.Node.Client.Provider.Provider` as the UTxO source; the library will need `cardano-node-clients` in `build-depends`.
- Conway-era `TxOut` datum lenses from `Cardano.Ledger.Api.Tx.Out` for inline datum extraction.
- Existing `RegistryNode`, `originNode`, `sentinelNext`, and `FromData` decoding from `Cardano.CIP113.Types`.
- Existing e2e devnet harness in `Cardano.CIP113.E2E.Deploy`.

## Slice 1: Live Registry Resolver

Add one vertical slice containing the resolver module, cabal exposure, and live e2e proof.

Recommended API shape:

```haskell
data RegistryResolverError
    = RegistryOriginMissing
    | RegistryDatumMissing TxIn
    | RegistryDatumDecodeFailed TxIn
    | RegistryBrokenLink ByteString
    | RegistryCycle ByteString
    deriving (Show, Eq)

data RegistryNodeUtxo = RegistryNodeUtxo
    { rnuTxIn :: TxIn
    , rnuTxOut :: TxOut ConwayEra
    , rnuNode :: RegistryNode
    }

data ResolvedRegistryNode = ResolvedRegistryNode
    { rrnUtxo :: RegistryNodeUtxo
    , rrnReferenceInputIndex :: Int
    }

findInsertionPoint
    :: (Monad m)
    => CIP113Deployment
    -> Provider m
    -> ByteString
    -> m (Either RegistryResolverError RegistryNodeUtxo)

findNode
    :: (Monad m)
    => CIP113Deployment
    -> Provider m
    -> [TxIn]
    -> ByteString
    -> m (Either RegistryResolverError (Maybe ResolvedRegistryNode))
```

The `[TxIn]` argument to `findNode` is the caller's other reference inputs. The resolver prepends the found registry node and computes `List.elemIndex foundTxIn (List.sort (foundTxIn : otherRefs))`, mirroring `ThirdPartySpec`.

Traversal rules:

- Build a map from `rnKey` to decoded registry UTxO.
- Start from the decoded node whose `rnKey == rnKey originNode`.
- For insertion, return the current node when `targetKey` belongs between `rnKey current` and `rnNext current`, treating `sentinelNext` as the tail bound.
- For lookup, return the node when `rnKey current == targetKey`; return `Right Nothing` only when traversal reaches `sentinelNext`.
- Detect broken links and cycles as `Left` errors.

The RED step should add and wire the e2e spec first, importing the not-yet-existing resolver API. Run `nix build .#e2e-tests` and record the compile failure. The GREEN step then implements the resolver and runs `./gate.sh`.

## E2E Proof

Create `e2e-test/Cardano/CIP113/E2E/RegistryResolverSpec.hs` and wire it into `e2e-test/e2e-main.hs`.

The spec should:

- Use `withCIP113Devnet`, `mkN2CProvider`, `mkN2CSubmitter`, `deployCIP113`, and the fixture blueprint exactly like the current e2e specs.
- Insert at least one policy with a real transaction, following the transaction pattern already in `RegisterSpec.runInsert`.
- After the transaction is submitted, query `queryUTxOs provider dRegistryAddr` again and use only that fresh query through the resolver for assertions.
- Assert `findNode` returns the inserted node, its `RegistryNode` key, and the same reference-input index as `List.elemIndex nodeIn (List.sort (nodeIn : otherRefs))` for a non-empty `otherRefs` set such as locked UTxOs.
- Assert `findInsertionPoint` for a later key returns the inserted node as predecessor, not the in-memory origin.
- Assert an absent key resolves to `Right Nothing`.

## Verification

Each worker slice runs:

```sh
./gate.sh
```

The gate runs `git diff --check`, `fourmolu --mode check`, `hlint`, `nix build .#e2e-tests`, and the built e2e binary from `e2e-test/` with the flake `cardano-node` on `PATH`.
