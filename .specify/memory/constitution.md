# cip113-tx-builder Constitution

## Purpose

Provide humans, scripts, and browser applications with tools to build
CIP-113 programmable-token transactions (transfer, freeze, seize) on Cardano.

Three delivery surfaces:
- **CLI** — human-friendly output, `--json` flag for scripting
- **Haskell library** — composable building blocks for Haskell callers
- **WASM-WASI** — browser-embeddable artifact, usable via `@bjorn3/browser_wasi_shim`

This is a living implementation: it tracks the CIP-113 spec toward Active
status, documents supported substandards, and adds new ones as they emerge.

## Non-Goals

- Not a wallet. Does not hold keys or sign.
- Not a chain indexer. Does not query UTxOs or submit transactions.
- Not tied to any single frontend or application.

## Core Principles

### I. Every operation is E2E-tested against a real devnet (NON-NEGOTIABLE)

Transaction-building logic cannot be validated by unit tests or mocks.
Each supported operation (register, transfer, freeze, seize) must have a
passing integration test against a live Conway devnet before any release.
RED → GREEN → REFACTOR against real devnet, never against mocks.

### II. CLI is dual-mode: human and machine

Default output is human-readable. `--json` emits newline-delimited JSON on
stdout. Exit codes: 0 = success, 1 = user error, 2 = internal error.

### III. WASM build is always real — never a placeholder

`nix build .#cip113-wasm` must produce a loadable `.wasm` artifact. The
build is gated in CI. A placeholder WASM is a build failure.

### IV. CIP-113 version is explicit

Every release declares which CIP-113 draft revision it implements. Breaking
spec changes → major bump. New substandard support → minor bump.

### V. New substandards are documented before they are implemented

A substandard lands in three steps: (a) written use-case description,
(b) failing E2E test (RED), (c) implementation (GREEN). No speculative
substandard code without a documented use case.

### VI. No key material

The library accepts unsigned transaction bodies or pre-signed witnesses.
Signing is the caller's responsibility.

## Quality Gates

Every PR must pass before merge:

- `fourmolu --mode check src/ e2e-test/` — format clean
- `hlint src/ e2e-test/` — no warnings
- `nix build .#cip113-tx-builder` — library builds
- `nix build .#e2e-tests` — test binary builds
- `nix build .#cip113-wasm` — real WASM artifact (not placeholder)
- Full E2E suite green against devnet

## Conventions

- **Haskell**: fourmolu, GHC2021, explicit exports, Haddock on public API
- **Cabal flags**: `build-e2e-tests` (default False), `werror` (default False, enabled in nix builds)
- **Branches**: `feat/`, `fix/`, `chore/`, `docs/`
- **Commits**: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`)
- **History**: linear, rebase-merge only, default branch is `setup`
- **Versioning**: SemVer, every release documents its CIP-113 draft revision

## Governance

This constitution supersedes all other practices. Amendments require a PR
with a rationale comment. All PRs must be verified for compliance before merge.

**Version**: 1.0.0 | **Ratified**: 2026-06-29
