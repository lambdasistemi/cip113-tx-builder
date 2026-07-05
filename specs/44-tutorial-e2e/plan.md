# Issue 44 - Tutorial Walkthrough Backed by Devnet E2E Plan

## Architecture

Keep the tutorial and executable proof connected by storing the tutorial command
templates in E2E-owned Haskell code and having the test compare those rendered
commands against fenced blocks in `docs/tutorial.md`. The doc remains ordinary
Markdown for MkDocs, while the E2E test owns the exact argument vectors it runs
against the devnet.

The live scenario should reuse the current CLI smoke infrastructure:

- deploy CIP-113 with `deployCIP113`;
- write a deployment descriptor and genesis signing key into a temp directory;
- prepare a vault with `cip113-cli vault seal` and sign one transaction with
  `cip113-cli sign --signing-key-vault --passphrase-file`;
- run `register`, `transfer`, `freeze`, and `seize` through the CLI with node
  provider flags and `--deployment`;
- sign/register with the vault-backed key and sign later operations with the
  plaintext key, then decode and submit each signed transaction;
- prepare transfer/freeze/seize state using the direct registry insertion helper
  pattern from `TransferCLISpec` and `FreezeSeizeCLISpec`, avoiding the known
  placeholder credential collision from CLI-created registry nodes.

The test should assert both command drift and live behavior. Drift assertions
run before expensive devnet work so a documentation-only mismatch fails quickly.

## Slice Breakdown

### Slice 1 - Tutorial document and navigation

Add `docs/tutorial.md` with the full narrative and command blocks, then link it
from the documentation home page and MkDocs nav. The command blocks should be
tagged or structured so the E2E drift check can identify the tutorial sequence.

### Slice 2 - Tutorial E2E and drift check

Add `TutorialCLISpec` and wire it into `e2e-test/e2e-main.hs`. Reuse or factor
only within `e2e-test/` as needed. The new spec must compare the tutorial
command blocks to the literal commands it runs, then execute the sequence
against the devnet and assert successful sign-and-submit for register,
transfer, freeze, and seize.

## Verification

The ticket gate is `./gate.sh`. It runs:

- `git diff --check`
- `fourmolu -m check` over tracked Haskell files
- `hlint src exe e2e-test`
- `nix develop --quiet .#docs -c mkdocs build --strict`
- `nix build .#cip113-cli`
- `nix build .#cardano-node`
- `nix build .#e2e-tests`
- the e2e test binary from `e2e-test/` with `CIP113_CLI` and `PATH` set as in
  GitHub Actions

Focused checks are allowed inside a slice, but each accepted implementation
slice and finalization require a green `./gate.sh`.
