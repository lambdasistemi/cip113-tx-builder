# Issue 76: Distribution Docs and Release Proof

## User Story

As an end user of `cip113-cli`, I want clear install instructions for the
published macOS and Linux distribution channels, and as a maintainer I want a
fresh proof that the release workflows produce artifacts that install or run.

## Context

This is D3, the serial-last child of epic #72. D0 added the release flake
outputs, D1 added the Linux release workflow, and D2 added the Darwin Homebrew
workflow. All three are merged to `setup`, so this ticket should not change
release packaging or workflow behavior unless a proof run exposes a blocking
defect.

The operator explicitly authorized dev-mode workflow dispatches:

- Linux: `.github/workflows/release.yml` with `mode=dev-linux`.
- Darwin: `.github/workflows/darwin-release.yml` with `mode=dev-homebrew`,
  `update_tap=no`.

The operator explicitly forbids real release side effects without a Q-file and
answer: no `v*` tag, no publish-mode release, no real tap update, and no
GitHub release mutation.

## Functional Requirements

- FR1: `README.md` gains an `Install` section that documents macOS Homebrew via
      `brew tap lambdasistemi/tap && brew install cip113-cli`.
- FR2: `README.md` documents Linux AppImage installation with a release-page
      download, `chmod +x`, and `--help` smoke command.
- FR3: `README.md` mentions DEB and RPM packages as alternatives on Linux.
- FR4: `docs/index.md` gains equivalent install guidance for the published
      documentation home page.
- FR5: A fresh dev Linux workflow dispatch succeeds and uploads the expected
      Linux dev release artifact bundle.
- FR6: The Linux AppImage is downloaded from the workflow artifact onto this
      Linux host, made executable, and run directly with `--help` exiting 0.
- FR7: A fresh dev Darwin Homebrew workflow dispatch succeeds with
      `update_tap=no`. Because this operator does not have physical macOS
      hardware, the accepted proof is the real `macos-14` GitHub Actions runner
      building the generated formula through a temporary local tap and running
      `brew test`.
- FR8: The proof report must be explicit that Darwin verification is a
      CI-runner proxy and not hands-on verification on physical Apple hardware.
- FR9: If a real `v*` release exists by final reporting time, the report checks
      whether the GitHub release page shows AppImage, DEB, and RPM assets. If no
      real release exists, the report states that this criterion is not
      applicable without an authorized release.

## Non-Goals

- No release workflow changes.
- No flake or packaging changes.
- No real tag push, publish-mode release, real Homebrew tap update, or release
  asset mutation without parent approval through the Q-file protocol.

## Success Criteria

- `./gate.sh` passes after the install documentation changes.
- The PR links to successful fresh dev Linux and Darwin workflow dispatches.
- The proof file and PR body include the Linux AppImage artifact download and
  direct `--help` execution evidence.
- The proof file and PR body state the Darwin proof boundary precisely:
  `macos-14` GitHub Actions local-tap `brew test`, not physical hardware.
