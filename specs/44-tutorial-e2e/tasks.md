# Issue 44 - Tutorial Walkthrough Backed by Devnet E2E Tasks

## Slice 1 - Tutorial document and navigation

- [X] T044-S1 Add `docs/tutorial.md` as one continuous walkthrough covering
      vault seal, register, vault-backed sign/submit, transfer,
      plaintext-key sign/submit, freeze, seize, and final signing.
- [X] T044-S1 Use pipe-shaped command blocks that match the `docs/cli.md`
      stdin/stdout contract and current node-backed deployment flags.
- [X] T044-S1 Link the tutorial from `docs/index.md` and `mkdocs.yml`.
- [X] T044-S1 Pass the docs-focused check, then commit with the required
      trailer.

## Slice 2 - Tutorial E2E and drift check

- [X] T044-S2 Add an E2E tutorial spec that compares the tutorial command
      blocks to the command sequence used by the test.
- [X] T044-S2 Run the tutorial sequence against a live devnet using the built
      `cip113-cli`, including vault-backed signing and plaintext signing.
- [X] T044-S2 Prepare transfer/freeze/seize ledger state with distinct
      registry credentials using the existing CLI smoke workaround pattern.
- [X] T044-S2 Assert decoded signed transactions submit successfully for every
      sign-and-submit step.
- [X] T044-S2 Wire the spec into the E2E suite and pass focused E2E checks plus
      `./gate.sh`, then commit with the required trailer.

## Slice 3 - CI parity for tutorial vault seal

- [X] T044-S3 Add `util-linux`/`script` to the GitHub Actions E2E test PATH so
      `cip113-cli vault seal` has a pseudo-TTY in CI.
- [X] T044-S3 Add the same `util-linux` PATH setup to `gate.sh` so local and CI
      tutorial E2E execution stay aligned.
- [X] T044-S3 Verify with the exact CI-shaped E2E command and `./gate.sh`, then
      commit with the required trailer.

## Slice 4 - CI util-linux output selection

- [X] T044-S4 Use the single `nixpkgs#util-linux.bin` output for CI and
      `gate.sh` so `$util_linux/bin` resolves to a real directory.
- [X] T044-S4 Assert `script` exists in the selected Nix output before running
      E2E so ambient local PATH cannot mask the failure.
- [X] T044-S4 Verify with the exact CI-shaped E2E command and `./gate.sh`, then
      commit with the required trailer.

## Finalization

- [ ] T044-V1 Update the draft PR body with delivered behavior, drift
      prevention mechanism, and verification evidence.
- [ ] T044-V1 Run final `./gate.sh`.
- [ ] T044-V1 Check off finalization boxes in this task file.
- [ ] T044-V1 Request parent merge review with a Q-file instead of self-merging.
