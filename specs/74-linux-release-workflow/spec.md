# Issue 74: Linux Release Workflow

## User Story

As a maintainer cutting `cip113-cli` releases, I want the existing release
workflow to keep running release-please on `setup` while also building and
publishing Linux AppImage, DEB, and RPM artifacts from the D0 flake outputs.

## Confirmed Reference Shape

Direct comparison against `lambdasistemi/amaru-treasury-tx` showed its
`.github/workflows/release.yml` is the Linux distribution workflow. It contains
one `linux-bundles` job, triggered by `v*` tags, PR path filters, and manual
dispatch, and it does not embed release-please in that file. This repo already
uses the same path for release-please, so this ticket preserves the existing
release-please job and adds a Linux bundles job in the same workflow file.

## Functional Requirements

- FR1: `release-please` still runs for pushes to `setup` and remains manually
  invokable.
- FR2: `v*` tag pushes build `.#linux-release-artifacts` and upload the
  AppImage, DEB, RPM, and checksum files to the matching GitHub release.
- FR3: PR mode uses `pull_request` filters for `.github/workflows/release.yml`,
  `flake.nix`, `flake.lock`, and `nix/**`, and builds
  `.#linux-dev-release-artifacts` without mutating releases.
- FR4: Manual Linux dispatch can build release or dev artifacts, but publishing
  is opt-in and defaults to `no`.
- FR5: The Linux job extracts the AppImage, DEB, and RPM artifacts and runs the
  extracted `cip113-cli --help` offline with exit 0 for each package.
- FR6: The D0 Linux artifact derivation builds successfully under the current
  pinned Nix inputs for both release and dev artifact outputs.

## Non-Goals

- Darwin/Homebrew distribution.
- End-user install documentation.

## Success Criteria

- `actionlint` accepts `.github/workflows/release.yml`.
- `nix eval` resolves both Linux release artifact package outputs.
- `nix build .#linux-release-artifacts` and
  `nix build .#linux-dev-release-artifacts` both succeed locally or in CI.
- The artifact smoke extracts all three Linux package formats and verifies
  `cip113-cli --help` without requiring a node socket.
