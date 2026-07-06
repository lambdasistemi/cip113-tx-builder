# Issue 75 Plan

## Current State

D0 merged the Darwin artifact outputs:

- `.#darwin-release-artifacts`
- `.#darwin-dev-homebrew-artifacts`

The current base cross-evaluates both outputs from Linux. The actual
aarch64-darwin build and Homebrew formula installation must run on macOS; Linux
CI cannot provide that proof.

D1 added Linux release artifacts to `.github/workflows/release.yml`. This ticket
is disjoint except for shared release flake inputs and should add a new
Darwin-specific workflow file.

## Implementation

- Add `.github/workflows/darwin-release.yml` modelled on the current Amaru
  Darwin workflow, but with `branches: [setup]` for PR filters.
- Configure events:
  - `push.tags: ["v*"]` for real release publication,
  - `pull_request` path filters for `.github/workflows/darwin-release.yml`,
    `flake.nix`, `flake.lock`, and `nix/**`,
  - `workflow_dispatch` with `mode`, `tag`, `publish`, and `update_tap`.
- Use `macos-14`, `actions/checkout@v6`, `cachix/install-nix-action@v30`, and
  `cachix/cachix-action@v17`.
- Mint a scoped `homebrew-tap` token with `actions/create-github-app-token@v1`
  using org `vars.CI_APP_ID` and `secrets.CI_APP_PRIVATE_KEY`.
- Invoke `paolino/dev-assets/darwin-homebrew-release@6864b20eb75c3578796e7f667562b5aea8780643`
  with:
  - `release-package: darwin-release-artifacts`
  - `dev-package: darwin-dev-homebrew-artifacts`
  - `release-formula: cip113-cli.rb`
  - `dev-formula: cip113-cli-dev.rb`
  - `tarball-pattern: cip113-cli-*-aarch64-darwin.tar.gz`
  - `installed-commands: cip113-cli`
  - `cleanup-formulae: cip113-cli cip113-cli-dev`
  - `tap-name: lambdasistemi/tap`
  - `tap-repository: lambdasistemi/homebrew-tap`
  - `github-token: ${{ github.token }}`
  - `tap-token: ${{ steps.tap-token.outputs.token }}`
  - `tarball-smoke-script` and `brew-smoke-script` that run
    `cip113-cli --help`.
- Include workflow-level `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"` to match
  the D1 workflow posture.

If the first actual macOS `nix build` surfaces a D0 Darwin packaging defect,
the implementation slice may apply a narrow follow-up in
`nix/darwin-release.nix` only. That exception follows the D1 precedent and must
be documented in the PR body as a D0 follow-up. Wider changes require a Q-file
to the epic owner.

## Verification

- Local Linux gate: `./gate.sh`.
- PR CI: the new Darwin Release workflow in PR mode builds
  `.#darwin-dev-homebrew-artifacts`, tests the generated formula through the
  local tap, and uploads the tarball/formula workflow artifact.
- Final PR audit: no tap updates or release mutations are possible from
  `pull_request`; publishing paths use the App-scoped tap token.

## Slice Breakdown

One implementation slice is enough because the workflow is the deliverable and
the PR cannot satisfy acceptance until the macOS PR-mode build/install test is
wired end to end.

- Slice 1: Add the Darwin release workflow and, only if an actual macOS build
  exposes a D0 Darwin packaging bug, apply the narrow `nix/darwin-release.nix`
  follow-up needed for the workflow to pass.
