# cip113-tx-builder

An independent implementation of transaction builders for [CIP-113](https://github.com/cardano-foundation/CIPs/tree/master/CIP-0113) — the Cardano programmable token standard.

**[Documentation](https://lambdasistemi.github.io/cip113-tx-builder)**

## What this provides

Three delivery surfaces sharing the same transaction-building core:

| Surface | Use case |
|---|---|
| Haskell library | Compose CIP-113 transactions from Haskell |
| CLI | Build transactions from the shell or scripts |
| WASM-WASI | Embed transaction building in a browser application |

## Supported operations

Register · Transfer · Freeze · Seize

Every operation has an E2E test against a live Conway devnet.

## Install

On macOS, install the CLI with Homebrew:

```bash
brew tap lambdasistemi/tap && brew install cip113-cli
```

On Linux, download the AppImage asset from the
[latest GitHub release](https://github.com/lambdasistemi/cip113-tx-builder/releases/latest):

```bash
curl -L -o cip113-cli.AppImage <release-asset-url>
chmod +x cip113-cli.AppImage
./cip113-cli.AppImage --help
```

DEB and RPM packages are available as Linux alternatives on the same release
page when packaged builds are published.

## Quick start

```bash
nix develop          # enter dev shell
nix build .#cip113-tx-builder   # build library
nix build .#e2e-tests           # build E2E test binary
nix build .#cip113-wasm         # build WASM artifact
```

## Docs

```bash
nix develop .#docs
just serve-docs      # preview at http://localhost:8000
```

Full documentation is published at **https://lambdasistemi.github.io/cip113-tx-builder**.

Pull requests publish rendered docs previews at `https://preview.dev.plutimus.com/lambdasistemi/cip113-tx-builder/pr-<N>/`.
