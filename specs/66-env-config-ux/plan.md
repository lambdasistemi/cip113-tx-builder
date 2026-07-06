# Plan: CLI env/config UX documentation and E2E proof

## Context

#62 through #65 moved all real transaction commands onto shared
`opt-env-conf` settings. This final child makes that UX visible in the docs and
proves the real config/env path against the live devnet e2e suite.

## Slice 1 - docs and config-backed e2e proof

Owned files:

- `docs/cli.md`
- `docs/tutorial.md`
- `e2e-test/e2e-main.hs`
- `e2e-test/Cardano/CIP113/E2E/*.hs` if the driver decides the proof belongs
  in a command-specific spec instead of the tutorial spec.

Work:

- Rewrite stale CLI documentation that still describes removed offline/provider
  flags.
- Add per-command setting tables with flag, environment variable, and config
  key columns for register, transfer, freeze, and seize.
- Replace tutorial deployment/socket/network/change shell variables with a YAML
  config file workflow.
- Keep token/address/signing variables where they are still useful for command
  readability.
- Update the tutorial command-block renderer in `e2e-main.hs` so the
  docs-alignment test matches the new tutorial.
- Add live e2e coverage that invokes at least one real command or tutorial phase
  using config file plus environment variables, with no repeated
  `--deployment`, `--socket-path`, `--network-magic`, or `--change-address`
  flags in the command invocation.
- Preserve existing CLI flag smoke specs unchanged unless a test-only helper is
  required.

Proof:

- RED: show the current tutorial command-block alignment and/or e2e proof does
  not cover config/env-only invocations.
- GREEN: focused tutorial/e2e proof passes.
- Full `./gate.sh` passes.

## Slice 2 - finalization

Owned by the ticket orchestrator:

- Re-run `./gate.sh` at HEAD.
- Capture `cip113-cli --help` and `cip113-cli register --help` output for the PR
  body.
- Update the PR body with delivered behavior and verification evidence.
- Drop `gate.sh`.
- Mark the PR ready and write the merge-review Q-file for the epic owner.
