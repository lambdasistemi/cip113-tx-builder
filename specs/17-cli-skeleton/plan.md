# Issue #17 Plan

## Scope

This ticket creates the CLI skeleton that later CLI tickets will fill in.
All runtime CLI code stays under `exe/`. The library under `src/` remains
unchanged.

## Implementation Shape

- Add executable wiring to `cip113-tx-builder.cabal`.
- Add `exe/Main.hs` as the optparse-applicative entry point.
- Add command stub modules under `exe/Cardano/CIP113/CLI/Command/`.
- Add the provider abstraction under `exe/Cardano/CIP113/CLI/Provider.hs`.
- Add the offline JSON backend under
  `exe/Cardano/CIP113/CLI/Provider/Offline.hs`.

The parent epic names the production binary as `cip113`, while issue #17
also requires a `cip113-cli` Cabal executable component. The implementation
slice should satisfy the explicit `cip113-cli` component requirement and
may add a `cip113` alias component only if needed to satisfy the help
smoke without changing `src/`.

## Flake Boundary

The brief forbids touching `flake.nix` unless `nix build .#cip113-cli`
requires it. If the executable builds through Cabal but `nix build
.#cip113-cli` fails only because the flake does not expose the component,
the ticket-orchestrator must write `Q-001-flake-wiring.md` and pause.

## Verification

- `./gate.sh`
- Focused help smoke from the built executable.
- `git diff --check`

## Slice Breakdown

One implementation slice is enough because all files form the minimal CLI
contract needed by later command tickets.
