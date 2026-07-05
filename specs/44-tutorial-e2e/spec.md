# Issue 44 - Tutorial Walkthrough Backed by Devnet E2E Specification

## User Story

As a CIP-113 operator, I want one narrative tutorial that runs through the full
`cip113-cli` lifecycle and is backed by a live devnet E2E test, so the published
commands stay executable as the CLI evolves.

## Functional Requirements

- Add `docs/tutorial.md` as a continuous walkthrough covering vault sealing,
  register, vault-backed signing, transfer, plaintext signing, freeze, seize,
  and final signing/submission.
- The tutorial must show command chaining with pipes for build-to-sign flows,
  following the stdin/stdout contract documented in `docs/cli.md`.
- The tutorial must use the current real transaction CLI shape:
  `--deployment FILE`, `--socket-path PATH`, `--network-magic MAGIC`, and
  `--change-address ADDR` for register, transfer, freeze, and seize.
- Link the tutorial from `docs/index.md` and `mkdocs.yml`.
- Add a live E2E scenario that runs the same tutorial command sequence against
  the local Conway devnet, signs both vault-backed and plaintext-key
  transactions, submits signed transactions, and asserts `Submitted` for every
  sign-and-submit step.
- The E2E scenario may prepare ledger state with the same direct registry-node
  insertion pattern used by the merged transfer/freeze/seize CLI specs, because
  the register CLI currently creates placeholder logic credentials that collide
  with later mandatory PLG withdrawals.
- Add drift prevention so edits to the tutorial command blocks and edits to the
  E2E command invocations cannot silently diverge.

## Non-Goals

- No new CLI flags or subcommands.
- No changes to `.github/workflows/*`.
- No changes to real transaction builders, deployment descriptor logic, or the
  registry resolver. Any such gap is a parent-level blocker.
- No productization of per-token logic selection during `cip113-cli register`.

## Success Criteria

- `docs/tutorial.md` reads as one coherent walkthrough rather than disconnected
  reference snippets.
- `nix develop --quiet .#docs -c mkdocs build --strict` includes the tutorial.
- The E2E suite fails loudly if a tutorial command block drifts from the command
  sequence used by the live test.
- `nix build .#e2e-tests` and the resulting binary pass with `CIP113_CLI` set
  to the built CLI and `cardano-node` in `PATH`.
- Fourmolu and hlint pass.
