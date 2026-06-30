# Issue 22 Plan - Indexer UTxO Provider Backends

## Existing Shape

`exe/Cardano/CIP113/CLI/Provider.hs` defines the CLI-local `UTxOProvider`
typeclass and UTxO data types. `Provider/Offline.hs` parses cardano-cli-shaped
JSON, while `Provider/Node.hs` implements node-to-client UTxO queries.

`Main.hs` currently parses `--socket-path` and `--network-magic` in both global
and command-local provider option positions. Provider selection is specialized
to node/offline today, but each command already exposes a polymorphic
`runWithProvider :: UTxOProvider provider => provider -> Bool -> Options -> IO
()`.

The executable cabal stanza already depends on `aeson`, `bytestring`,
`containers`, `text`, and `base16-bytestring`. It does not currently depend on
HTTP client packages.

## External API Shapes

Blockfrost:

- Official OpenAPI: `https://docs.blockfrost.io/blockfrost-openapi.yaml`
- Auth header: `project_id: <project-id>`
- Project id prefixes identify Cardano networks: `mainnet`, `preprod`,
  `preview`.
- Address UTxOs: `GET /addresses/{address}/utxos?count=100&page=N`
- Tx UTxOs: `GET /txs/{hash}/utxos`
- UTxO entries expose `address`, `tx_hash`, `output_index`, and `amount`, where
  each amount has `unit` and `quantity`.

Kupo:

- Official OpenAPI: `https://cardanosolutions.github.io/kupo/api/v2.11.0.yaml`
- Address matches: `GET /matches/{address}?unspent`
- Output-reference matches: `GET /matches/{index}@{txid}?unspent`
- Match entries expose `transaction_id`, `output_index`, `address`, and
  `value`, where `value.coins` is lovelace and `value.assets` maps
  `policyId.assetNameHex` to quantity.

## Design

Add `Cardano.CIP113.CLI.Provider.Blockfrost` with:

- `BlockfrostProviderConfig` containing the project id.
- `BlockfrostProvider` holding an HTTP manager and config.
- `withBlockfrostProvider :: BlockfrostProviderConfig -> (BlockfrostProvider
  -> IO a) -> IO a`.
- A `UTxOProvider BlockfrostProvider` instance.
- JSON decoders for address UTxOs and transaction UTxO outputs.
- Conversion from Blockfrost asset units into nested policy/token maps, decoding
  asset names from hex UTF-8.
- HTTP exception/status/JSON error wrapping as clear user errors.

Add `Cardano.CIP113.CLI.Provider.Kupo` with:

- `KupoProviderConfig` containing the base URL.
- `KupoProvider` holding an HTTP manager and normalized base URL.
- `withKupoProvider :: KupoProviderConfig -> (KupoProvider -> IO a) -> IO a`.
- A `UTxOProvider KupoProvider` instance.
- JSON decoders for Kupo `Match` and `Value` objects.
- Conversion from Kupo asset keys into nested policy/token maps, decoding asset
  names from hex UTF-8.
- HTTP exception/status/JSON error wrapping as clear user errors.

Update `Main.hs` only to:

- Import the new providers.
- Extend `ProviderOptions` and `providerOptionsParser` with
  `--blockfrost-project-id` and `--kupo-url`.
- Generalize `runWithSelectedProvider` to accept a rank-2 polymorphic command
  runner constrained by `UTxOProvider`.
- Select providers with parent-brief precedence: node if socket path is present
  (requiring network magic), Blockfrost if project id is present, Kupo if URL is
  present, otherwise offline.

## Dependencies

Expected executable dependency additions:

- `http-client`
- `http-client-tls`
- `http-types`

The worker must verify the final minimal set by building and must not add
`blockfrost-client` unless it is already available in the package set and
materially simplifies the implementation.

## Slices

### Slice 1 - HTTP Indexer Providers

Implement `Provider/Blockfrost.hs`, `Provider/Kupo.hs`, and cabal wiring. Keep
`Main.hs` untouched in this slice. The modules should build and expose provider
constructors/configs plus `UTxOProvider` instances.

### Slice 2 - CLI Provider Selection

Wire `--blockfrost-project-id` and `--kupo-url` into `Main.hs`, generalize the
provider runner, and preserve offline/node behavior. This slice adds the
missing-service smoke evidence for Kupo and the unsupported-prefix smoke
evidence for Blockfrost.

## Verification

Required gate:

- `./gate.sh`

Focused build/lint commands:

- `nix build --quiet .#cip113-cli`
- `nix develop --quiet -c fourmolu --mode check exe`
- `nix develop --quiet -c hlint exe`

Observed baseline caveat: `nix develop --quiet -c cabal build cip113-cli`
fails on untouched `origin/setup` because direct Cabal resolution cannot find
the `lmdb` pkg-config package for `cardano-lmdb`. The flake package build is
the correct build gate and passed before implementation.
