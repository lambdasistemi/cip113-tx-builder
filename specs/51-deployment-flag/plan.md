# Plan: CLI Deployment Descriptor Flag

## Existing Shape

`exe/Main.hs` owns global CLI parsing, command dispatch, and provider option
precedence. The four transaction-building commands each receive command-local
provider options plus command-specific options. `sign` and `vault seal` do not
use providers and remain unrelated.

`src/Cardano/CIP113/Deployment.hs` already exposes `CIP113Deployment` with a
`FromJSON` instance. This ticket must consume that API only; it must not edit
the deployment or registry library modules.

## Design

Extend the existing provider-options plumbing with an optional deployment file
path. Parse `--deployment FILE` wherever the provider flags are accepted:
globally before the subcommand and locally after `register`, `transfer`,
`freeze`, or `seize`.

Before selecting/running the provider, resolve the effective deployment path
with command-local precedence over global. If a path is present, decode it as
`CIP113Deployment` with `aeson`; catch read errors and decode errors and report
them through the existing `dieUser` style. Force the decoded value so successful
commands prove the descriptor was actually loaded, but do not thread it into the
transaction builders yet. Later tickets can replace that no-op boundary with
real registry/transaction logic.

Keep implementation scoped to `exe/Main.hs` unless the worker finds a small
shared CLI module materially clearer. If a new executable module is introduced,
update `cip113-tx-builder.cabal` only for that module registration.

## Slice

### Slice 1 - Shared Deployment Flag And Loader

Add the shared flag, decode-on-use behavior, user-facing errors, docs updates,
and smoke evidence. The smoke must prove:

- help/parser visibility for `register`, `transfer`, `freeze`, and `seize`;
- a real descriptor JSON from the existing blueprint fixture loads without
  error;
- missing and malformed descriptor files exit 1 with clear stderr.

## Verification

Required gate:

- `./gate.sh`

Focused commands for the implementation slice:

- `nix build --quiet .#cip113-cli --no-link`
- `nix develop --quiet -c fourmolu --mode check exe src e2e-test`
- `nix develop --quiet -c hlint exe src e2e-test`
- CLI smoke commands covering successful descriptor load plus missing and
  malformed descriptor errors.

Observed baseline caveat: direct `cabal repl`/`cabal build` resolution can fail
on `cardano-lmdb` pkg-config outside the flake path. Use `nix build` for the
build gate, matching prior CLI provider tickets.
