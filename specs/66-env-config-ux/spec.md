# Spec: CLI env/config UX documentation and E2E proof

## User Story

As a `cip113-cli` user building real CIP-113 transactions, I want repeated
settings such as deployment, node connection, and change address to be documented
as CLI flags, environment variables, and YAML config keys so I can run the
register, transfer, freeze, and seize workflow without repeating the same flags
on every command.

## Requirements

- `docs/cli.md` documents the CLI flag, `CIP113_*` environment variable, and
  YAML config key for every setting used by `register`, `transfer`, `freeze`,
  and `seize`.
- `docs/tutorial.md` replaces the old shell-variable workaround for deployment,
  socket path, network magic, and change address with a real YAML config file.
- The tutorial command sequence remains register -> sign -> transfer -> sign ->
  freeze -> seize -> sign; only repeated settings move out of each invocation.
- Existing CLI subprocess specs for register, transfer, freeze/seize, and the
  tutorial continue to pass.
- At least one new live-devnet e2e path proves a command or tutorial chain can
  use only config file plus environment variables for repeated real-build
  settings, without `--deployment`, `--socket-path`, `--network-magic`, or
  `--change-address` flags per invocation.
- PR metadata captures `cip113-cli --help` and `cip113-cli register --help`
  evidence showing CLI, env, and config surfaces.

## Success Criteria

- `docs/cli.md` includes env/config mapping for deployment, socket path,
  network magic, change address, command addresses, token name, policy id, and
  transfer amount.
- `docs/tutorial.md` shows either the default
  `~/.config/cip113-cli/config.yaml` path or an explicit `--config-file`
  workflow and no longer presents deployment/socket/network/change as a shell
  workaround.
- Tutorial docs and `e2e-test/e2e-main.hs` command-block alignment agree.
- Full `./gate.sh` passes, including docs build, fourmolu, HLint, help smoke,
  `nix build .#e2e-tests`, and live e2e execution.

## Non-Goals

- No changes to `Cardano.CIP113.CLI.Settings`, `Main.hs`, or command modules.
- No further CLI behavior changes beyond documentation and e2e proof.
- No release/version metadata changes.
