# Issue 75: Darwin Release Workflow

## User Story

As a maintainer cutting `cip113-cli` releases, I want a macOS Apple Silicon
release workflow that builds the D0 Darwin/Homebrew flake outputs, verifies the
generated formula through Homebrew, and publishes the stable formula to the
shared `lambdasistemi/homebrew-tap` on `v*` tags.

## Confirmed Reference Shape

The live `lambdasistemi/amaru-treasury-tx` Darwin workflow uses
`paolino/dev-assets/darwin-homebrew-release@6864b20eb75c3578796e7f667562b5aea8780643`.
That action builds the selected flake package, smoke-tests the tarball, uploads
workflow artifacts, and in PR mode tests the generated formula through a local
temporary tap after rewriting only the `url` to the fresh tarball.

Early GitHub API verification confirmed the `lambdasistemi-ci` App installation
is org-wide (`repository_selection=all`) with `contents: write`, and org
`CI_APP_ID`, `CI_APP_PRIVATE_KEY`, and `CACHIX_AUTH_TOKEN` are visible to all
repositories. The workflow must use the App token for `homebrew-tap` writes and
must not introduce a per-repo PAT.

## Functional Requirements

- FR1: Add `.github/workflows/darwin-release.yml` with `v*` tag triggers,
      pull-request path filters for this workflow and release flake files, and
      manual dispatch modes for `release` and `dev-homebrew`.
- FR2: Run the Darwin job on a macOS Apple Silicon-capable runner and build
      `.#darwin-release-artifacts` for release mode.
- FR3: In PR mode, build `.#darwin-dev-homebrew-artifacts`, upload the generated
      artifacts, install the generated dev formula through a temporary local tap
      with only the formula `url` rewritten to the fresh tarball, and run
      `brew test` without mutating the real tap.
- FR4: For publishing paths, mint a scoped token from org `vars.CI_APP_ID` and
      `secrets.CI_APP_PRIVATE_KEY` with `repositories: homebrew-tap`, then use
      that token for tap pushes.
- FR5: Use the formula filenames and class names established by D0:
      `cip113-cli.rb` / `Cip113Cli` and `cip113-cli-dev.rb` / `Cip113CliDev`.
- FR6: Keep release side effects gated: tag pushes publish, default manual
      dispatch does not publish unless `publish=yes`, and PRs never push to the
      tap or mutate GitHub releases.

## Non-Goals

- Linux artifact workflow changes.
- End-user install documentation.
- Reworking release-please behavior.

## Success Criteria

- `./gate.sh` passes from the Linux orchestration worktree by cross-evaluating
  both Darwin artifact outputs.
- The PR workflow runs on macOS and proves the dev Homebrew path by building
  `.#darwin-dev-homebrew-artifacts`, installing the generated formula through
  the local tap, and running `brew test`.
- The workflow references the org GitHub App token path for tap writes and has
  no `TAP_TOKEN` or per-repo PAT dependency.
