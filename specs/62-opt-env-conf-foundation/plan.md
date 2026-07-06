# Implementation Plan: opt-env-conf Foundation

## Technical Context

- Language: Haskell, `GHC2021`
- CLI today: `optparse-applicative` in `exe/Main.hs` plus command-local parsers.
- Target parser: `opt-env-conf`, using `commands`/`command`, `setting`, and the
  library's XDG YAML config-file support.
- Base branch: `setup`
- Runtime proof: local Nix build and e2e invocation matching `.github/workflows/ci.yaml`.

## Design

1. Probe dependency resolution first by adding `opt-env-conf` to the executable
   build-depends and building `.#cip113-cli`. If this fails because the package
   is absent or version-incompatible in the pinned package set, stop and escalate.
2. Add `Cardano.CIP113.CLI.Settings` under `exe/` for shared settings:
   deployment loading/decoding, node connection, change address, token name, and
   policy id.
3. Move the address and policy-id validation logic currently in `Register.hs`
   into `Settings.hs` rather than copying it. Leave unrelated register parser
   cleanup for #63.
4. Rewrite `Main.hs` around `opt-env-conf` command dispatch and config-file
   wiring. Preserve existing command names and runtime branches.
5. Convert `Sign.parser` and `Seal.parser` to the new parser type as the
   end-to-end proof for commands without provider options.

## Slice Order

- Slice 1, dependency probe: add `opt-env-conf` to the executable dependency
  list and prove `nix build .#cip113-cli` resolves.
- Slice 2, parser foundation: add `Settings.hs`, register it in cabal, rewrite
  `Main.hs`, and convert `sign`/`vault seal`.
- Slice 3, final PR metadata: capture help output, run the full gate, update PR
  body, and request merge review.

## Risks

- `opt-env-conf` may not be available in the pinned package set. The first slice
  is intentionally isolated so that this is discovered before broad edits.
- The exact `opt-env-conf` parser type and config combinator names may differ
  from the issue summary. Workers should inspect installed docs/source through
  the Nix environment before changing command parsers.
- Existing `register`/`transfer`/`freeze`/`seize` code still uses old command
  parser helpers. This ticket may bridge those commands at the top level, but
  command-specific cleanup is owned by later child tickets.

## Verification

- Focused dependency proof: `nix build .#cip113-cli --no-link --print-build-logs`.
- Formatting: `nix develop --command fourmolu --mode check src/ exe/ e2e-test/`.
- Linting: `nix develop --command hlint src/ exe/ e2e-test/`.
- Full gate: `./gate.sh`.
- UX evidence: capture `cip113-cli --help` output in PR metadata.
