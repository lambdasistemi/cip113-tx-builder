# Issue 76 Release Proof

## Scope Boundary

This ticket documents installation and records dev-mode release proof. It does
not cut a stable tag, run publish-mode release workflows, push the real
Homebrew tap, or mutate stable GitHub release assets.

Parent answer `A-001-release-assets.md` authorized the real stable release cut
at the epic level after PR #80 merges. The epic owner will cut a new `v*` tag
on `setup` and verify stable GitHub release assets plus the Homebrew tap push.

## Linux Dev Dispatch

Workflow dispatch command:

```bash
gh workflow run release.yml \
  --repo lambdasistemi/cip113-tx-builder \
  --ref 76-docs-release-proof \
  -f mode=dev-linux \
  -f publish=no
```

Evidence:

- Run: https://github.com/lambdasistemi/cip113-tx-builder/actions/runs/28815196493
- Workflow: `Release`
- Event: `workflow_dispatch`
- Branch: `76-docs-release-proof`
- Head SHA: `8acceeb72f7aac6fdc524ccd277a17e407d4172c`
- Conclusion: `success`
- Job: `Build Linux release bundles`, job ID `85452717638`, conclusion
  `success`
- Mode: `dev-linux`
- Publish: `no`
- Artifact: `linux-dev-release-bundles`, artifact ID `8118498822`
- Artifact URL:
  https://github.com/lambdasistemi/cip113-tx-builder/actions/runs/28815196493/artifacts/8118498822

The workflow artifact contained:

```text
SHA256SUMS
cip113-cli-0.1.1.0-8acceeb-x86_64-linux.AppImage
cip113-cli-0.1.1.0-8acceeb-x86_64-linux.deb
cip113-cli-0.1.1.0-8acceeb-x86_64-linux.rpm
cip113-cli.AppImage
```

## Linux Local AppImage Smoke

The Linux artifact was downloaded from run `28815196493` onto this Linux host
under:

```text
/tmp/epic-72/cip113-tx-builder-76/linux-artifacts-28815196493/
```

Local smoke command:

```bash
appimage=/tmp/epic-72/cip113-tx-builder-76/linux-artifacts-28815196493/cip113-cli-0.1.1.0-8acceeb-x86_64-linux.AppImage
chmod +x "$appimage"
"$appimage" --help
```

Result: exit `0`.

Observed output started with:

```text
Usage: cip113-cli [--config-file FILE_PATH] [--json] COMMAND

Build unsigned CIP-113 transaction bodies
```

## Darwin Fresh Dev Dispatch

Workflow dispatch command:

```bash
gh workflow run darwin-release.yml \
  --repo lambdasistemi/cip113-tx-builder \
  --ref 76-docs-release-proof \
  -f mode=dev-homebrew \
  -f publish=no \
  -f update_tap=no
```

Evidence:

- Run: https://github.com/lambdasistemi/cip113-tx-builder/actions/runs/28815197761
- Workflow: `Darwin Release`
- Event: `workflow_dispatch`
- Branch: `76-docs-release-proof`
- Head SHA: `8acceeb72f7aac6fdc524ccd277a17e407d4172c`
- Conclusion: `success`
- Job: `Build Darwin Homebrew artifacts`, job ID `85452722035`, conclusion
  `success`
- Runner image: `macos-14-arm64`
- Operating system: macOS `14.8.7`
- Mode: `dev-homebrew`
- Publish: `no`
- Update tap: `no`
- Artifact: `darwin-dev-homebrew-artifacts`, artifact ID `8118583324`
- Artifact URL:
  https://github.com/lambdasistemi/cip113-tx-builder/actions/runs/28815197761/artifacts/8118583324

The fresh dispatch ran the Darwin tarball smoke with
`INPUT_TARBALL_SMOKE_SCRIPT: cip113-cli --help`; the run log shows the CLI help
output at `18:51:39Z`.

Important boundary: the pinned `paolino/dev-assets/darwin-homebrew-release`
action runs the generated-formula local-tap `brew install` / `brew test` step
only for `pull_request` events. For `workflow_dispatch` with `mode=dev-homebrew`
and `update_tap=no`, it smoke-tests the tarball and uploads dev artifacts; it
does not run the local-tap `brew test`.

## Darwin Homebrew Local-Tap Proxy

Because this operator does not have hands-on physical Apple hardware, the
closest available Homebrew proof is CI on a real GitHub Actions macOS runner.
This is a CI-runner proxy, not physical hardware verification performed by the
operator.

D2 PR-mode evidence:

- Run: https://github.com/lambdasistemi/cip113-tx-builder/actions/runs/28813640535
- Workflow: `Darwin Release`
- Event: `pull_request`
- Branch: `75-darwin-release-workflow`
- Head SHA: `ab6558bc772453a6daffd335814c84c05c8440ae`
- Conclusion: `success`
- Job: `Build Darwin Homebrew artifacts`, job ID `85447501494`, conclusion
  `success`

That PR-mode run executed `test-local-tap.sh` on the macOS runner. The log shows:

```text
MODE: dev-homebrew
PUBLISH: no
UPDATE_TAP: no
INPUT_TAP_NAME: lambdasistemi/tap
INPUT_TAP_REPOSITORY: lambdasistemi/homebrew-tap
INPUT_BREW_SMOKE_SCRIPT: cip113-cli --help
==> Tapping lambdasistemi/tap
Installing cip113-cli-dev from lambdasistemi/tap
==> Testing lambdasistemi/tap/cip113-cli-dev
/opt/homebrew/Cellar/cip113-cli-dev/0.1.1.0-f0f606c/bin/cip113-cli --help
Usage: cip113-cli [--config-file FILE_PATH] [--json] COMMAND
```

## Stable Release Page

A stable `v0.1.1` release exists:

```text
https://github.com/lambdasistemi/cip113-tx-builder/releases/tag/v0.1.1
```

At proof time, `gh release view v0.1.1 --json assets` returned an empty asset
list. That tag predates the merged D0-D2 release pipeline work, so D3 does not
publish assets to it.

Per parent answer `A-001-release-assets.md`, the stable release-page acceptance
item will be closed by the epic owner after PR #80 merges by cutting a new `v*`
tag on `setup` and verifying the resulting AppImage, DEB, RPM, and Homebrew tap
publication.
