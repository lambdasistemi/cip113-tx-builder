# Issue 76 Plan

## Current State

The `setup` branch contains the merged outputs from D0, D1, and D2:

- D0: release flake outputs for Linux bundles and Darwin Homebrew artifacts.
- D1: Linux release workflow with `workflow_dispatch` mode `dev-linux`.
- D2: Darwin Homebrew workflow with `workflow_dispatch` mode `dev-homebrew` and
  `update_tap=no` dry-run behavior.

The existing README and docs home page describe development builds and CLI
usage, but not end-user installation from release artifacts.

## Implementation

Add an `Install` section to both `README.md` and `docs/index.md`.

The section should be concise and concrete:

- macOS:
  `brew tap lambdasistemi/tap && brew install cip113-cli`
- Linux AppImage:
  point users at the latest GitHub release, use `curl -L -o cip113-cli.AppImage
  <release-asset-url>`, `chmod +x`, and run `./cip113-cli.AppImage --help`
- Linux alternatives:
  mention that `.deb` and `.rpm` packages are published on the same release page
  for Debian/Ubuntu and RPM-based systems.

Do not change workflow files, flake outputs, or packaging code unless fresh
verification exposes a blocking defect. Such a defect would require a Q-file
because the issue lists those changes as non-goals.

## Verification

Local documentation gate:

```bash
./gate.sh
```

Release proof:

```bash
gh workflow run release.yml \
  --repo lambdasistemi/cip113-tx-builder \
  --ref 76-docs-release-proof \
  -f mode=dev-linux \
  -f publish=no

gh workflow run darwin-release.yml \
  --repo lambdasistemi/cip113-tx-builder \
  --ref 76-docs-release-proof \
  -f mode=dev-homebrew \
  -f publish=no \
  -f update_tap=no
```

After the Linux run completes, download the `linux-dev-release-bundles`
artifact, make the AppImage executable on this Linux host, run it directly with
`--help`, and record the exit-0 evidence.

After the Darwin run completes, link the run and state the actual boundary: a
real `macos-14` GitHub Actions runner tested the generated Homebrew formula via
a temporary local tap and `brew test`; no physical Apple hardware was available
to this operator.

## Slice Breakdown

### Slice 1: Install documentation

Driver/navigator pair updates only `README.md` and `docs/index.md`, then runs
the local docs gate.

### Slice 2: Fresh release proof

Orchestrator-owned slice. Trigger the two dev-mode workflows, wait for success,
download and run the Linux AppImage, and record the proof in
`specs/76-distribution-docs-release-proof/proof.md` plus the PR body.
