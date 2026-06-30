# Issue 22 Tasks - Indexer UTxO Provider Backends

## Slice 1 - HTTP Indexer Providers

- [X] T022-S1 Add `Cardano.CIP113.CLI.Provider.Blockfrost` with config,
  endpoint selection from project id prefix, HTTP request handling, JSON
  decoders, and a `UTxOProvider BlockfrostProvider` instance.
- [X] T022-S1 Add `Cardano.CIP113.CLI.Provider.Kupo` with config, HTTP request
  handling, JSON decoders, and a `UTxOProvider KupoProvider` instance.
- [X] T022-S1 Convert Blockfrost and Kupo values into the CLI-local `UTxO`,
  `UTxORef`, and `UTxOValue` shapes, including hex UTF-8 asset-name decoding.
- [X] T022-S1 Add only the executable modules/dependencies required by the
  indexer providers and verify the CLI builds.

## Slice 2 - CLI Provider Selection

- [X] T022-S2 Parse `--blockfrost-project-id` and `--kupo-url` through the
  existing global and command-local provider option parser.
- [X] T022-S2 Select providers with parent-brief precedence: node >
  Blockfrost > Kupo > offline.
- [X] T022-S2 Preserve existing offline/node behavior, missing-node validation,
  command-local override behavior, and `--json` threading.
- [X] T022-S2 Verify clear exit-code-1 behavior for unreachable/misconfigured
  indexer providers without requiring a live Blockfrost or Kupo service in CI.
- [X] T022-S2 Run `./gate.sh` and record the result.
