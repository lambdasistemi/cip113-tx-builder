# cip113-tx-builder

An independent implementation of transaction builders for [CIP-113](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0113) — the Cardano programmable token standard.

## What this library provides

Three delivery surfaces for building CIP-113 transactions:

| Surface | Use case |
|---|---|
| **Haskell library** | Compose CIP-113 transactions from Haskell |
| **CLI** | Build transactions from the shell or scripts |
| **WASM-WASI** | Embed transaction building in a browser application |

All three surfaces share the same transaction-building core. The E2E test suite validates every supported operation against a live Conway devnet.

## Supported operations

| Operation | Description |
|---|---|
| **Register** | Enroll a smart wallet in the CIP-113 registry |
| **Transfer** | Move programmable tokens between smart wallets |
| **Freeze** | Lock tokens at an always-fail address (third-party lock) |
| **Seize** | Redirect tokens to a new owner (third-party redirect) |

Each operation is available from the `cip113-cli` binary — see
[CLI usage](cli.md) for commands, flags, and the vault seal/sign workflow, or
follow the [CIP-113 CLI tutorial](tutorial.md) for a full register, transfer,
freeze, and seize walkthrough.

## Quick start

```bash
# Enter the dev shell
nix develop

# Build the library
nix build .#cip113-tx-builder

# Build and run E2E tests (requires cardano-node in PATH)
nix build .#e2e-tests
./result/bin/e2e-tests

# Build the WASM artifact
nix build .#cip113-wasm
```

## Documentation

- [What is CIP-113?](cip-113.md) — the standard, its architecture, and current status
- [CLI usage](cli.md) — commands, flags, and the vault seal/sign workflow
- [CIP-113 CLI tutorial](tutorial.md) — one end-to-end local-devnet walkthrough
- [Contributing](contributing.md) — how this project tracks and implements the spec
