# Contributing

## What "independent implementation" means

This project implements CIP-113 from the specification alone — it does not wrap or depend on any other CIP-113 implementation. The goal is a second implementation that:

- Validates the spec is implementable and internally consistent
- Serves as a reference for anyone building CIP-113 tooling
- Surfaces ambiguities in the spec before they become bugs in production

When the spec and this implementation disagree, either the spec is unclear or the implementation has a bug. Both are worth filing and fixing.

## Tracking the spec

CIP-113 is in _Proposed_ status. The spec can change. This project's policy:

- Every release records which CIP-113 draft revision it implements (see `CHANGELOG.md`)
- Breaking spec changes trigger a **major** version bump
- Additive changes (new substandards, new operations) trigger a **minor** bump
- When a spec change requires removing behaviour, the removal is documented in the changelog

Watch [CIP-0113 pull requests](https://github.com/cardano-foundation/CIPs/pulls) to catch incoming changes early.

## Adding a new substandard

Substandards follow a strict sequence. No code before the spec is written and proven by a failing test.

### Step 1: Document the use case

Open an issue describing:

- What the substandard does
- What invariant the transfer-logic script enforces
- What the staking withdrawal credential looks like on-chain
- Why it fits within the CIP-113 extension model

### Step 2: Write a failing E2E test (RED)

Add a test case to `e2e-test/` that:

1. Deploys the new substandard script to the devnet
2. Registers it in a token's registry node
3. Attempts a transfer that should satisfy (or violate) the substandard rule
4. Asserts the expected outcome

The test must fail because the implementation does not yet exist.

### Step 3: Implement (GREEN)

Add the transaction-building code to `src/Cardano/CIP113/`. Keep the library module for each substandard in its own file.

### Step 4: Verify and merge

Run `nix build .#e2e-tests` and execute the suite against a devnet. All tests — including the new one — must pass.

## Running the E2E tests

The test suite requires a live Conway devnet.

```bash
# Build the test binary
nix build .#e2e-tests

# Get cardano-node in PATH (comes from the flake)
nix build .#cardano-node
export PATH=$PWD/result/bin:$PATH

# Run all tests
./result/bin/e2e-tests
```

The tests are intentionally slow: each test case deploys real validators and submits real transactions. They are the source of truth for whether the implementation is correct.

## Quality gates

Before a PR can merge, every check must pass locally:

```bash
nix develop --command fourmolu --mode check src/ e2e-test/
nix develop --command hlint src/ e2e-test/
nix build .#cip113-tx-builder
nix build .#e2e-tests
nix build .#cip113-wasm
```

**Never push to discover lint or format errors.** Run these locally first.

## Building the docs

```bash
# Enter the docs dev shell
nix develop .#docs

# Preview locally
just serve-docs

# Build static site
just build-docs
```

## Versioning

This project uses [SemVer](https://semver.org/). The version in `cip113-tx-builder.cabal` is the canonical version.

- `major`: breaking spec change or incompatible API change
- `minor`: new substandard, new operation, or additive API
- `patch`: bug fix, docs, or tooling change

Every release entry in `CHANGELOG.md` must record the CIP-113 draft revision it targets.
