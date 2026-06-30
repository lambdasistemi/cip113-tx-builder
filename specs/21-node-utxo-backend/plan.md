# Issue 21 Plan - Node UTxO Backend

## Existing Shape

`exe/Cardano/CIP113/CLI/Provider.hs` defines the CLI-local `UTxOProvider`
typeclass and simple UTxO data types. `Provider/Offline.hs` parses
cardano-cli-shaped JSON into those types. Each command module currently owns
its parser, loads the offline provider internally, and prints deterministic
unsigned CBOR hex.

`cardano-node-clients` is already pinned in `cabal.project` and exposes
`Cardano.Node.Client.N2C.Connection` plus
`Cardano.Node.Client.N2C.Provider.mkN2CProvider`, which supports
`queryUTxOs` and `queryUTxOByTxIn` over LocalStateQuery.

## Design

Add `Cardano.CIP113.CLI.Provider.Node` with:

- `NodeProviderConfig` containing socket path and network magic.
- `withNodeProvider :: NodeProviderConfig -> (NodeProvider -> IO a) -> IO a`
  that checks the socket exists, starts the N2C client, and brackets the
  background client while commands query it.
- A `UTxOProvider NodeProvider` instance.
- Conversion helpers from CLI address/ref/value shapes to ledger
  `Addr`, `TxIn`, and `TxOut ConwayEra`.

Address parsing in node mode should accept real bech32 Cardano addresses and
base16-encoded serialized ledger addresses. Offline fixture addresses remain
opaque text because they are only compared inside the offline provider.

Main owns provider selection:

- both `--socket-path` and `--network-magic` present: node mode;
- neither present: offline mode;
- only one present: exit 1 with a clear error.

The clean command integration, pending Q-001, is to expose provider-parameterized
command runners so `Main.hs` chooses the provider once and each command consumes
the `UTxOProvider` abstraction. Offline `run` compatibility can remain as a
thin wrapper if useful.

## Dependencies

Expected executable dependency additions:

- `async`
- `base16-bytestring`
- `bech32`
- `bytestring`
- `cardano-crypto-class`
- `cardano-ledger-api`
- `cardano-ledger-conway`
- `cardano-ledger-core`
- `cardano-ledger-mary`
- `cardano-node-clients`
- `microlens`
- `ouroboros-network`

The worker must verify the final minimal set by building; do not add unused
packages.

## Slices

### Slice 1 - Node Provider

Implement `Provider/Node.hs` and cabal wiring. This slice may stop at a
buildable provider module if Q-001 is still unanswered. It must not touch
command modules.

### Slice 2 - CLI Provider Selection

After Q-001 is answered, wire global node flags through `Main.hs` and the
minimal approved command-scope refactor. Keep offline fallback compatible and
preserve `--json`.

### Slice 3 - Gate And Smoke

Run `./gate.sh`, record missing-socket node-mode proof, and document the live
devnet follow-up transcript requirement in PR metadata. Do not require a live
node in CI.

## Verification

Required gate:

- `git diff --check`
- `nix build --quiet .#cip113-cli`
- `nix develop --quiet -c fourmolu --mode check exe`
- `nix develop --quiet -c hlint exe`
- offline fallback smoke against existing fixture
- node missing-socket smoke returns exit code 1

Observed planning caveat: `nix develop --quiet -c cabal build exe:cip113-cli
-O0 --dry-run` currently fails before ticket changes because Cabal cannot find
the `lmdb` pkg-config entry for `cardano-lmdb`. The flake has a haskell.nix
`cardano-lmdb` pkg-config override, so `nix build .#cip113-cli` is the gate's
build path.
