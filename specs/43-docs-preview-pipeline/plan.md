# Plan: Docs Preview and Pages Pipeline

## Tech Stack

- GitHub Actions on the repository's `nixos` runner.
- Nix docs shell from this repo: `.#docs`.
- MkDocs strict build output under `site`.
- `actions/upload-pages-artifact` and `actions/deploy-pages` for canonical Pages deployment.
- `paolino/dev-assets/static-preview@main` for PR preview publish and cleanup.

## Slice 1: Workflow and README

One bisect-safe CI/docs slice adds `.github/workflows/deploy-docs.yml` and updates only README's `## Docs` section.

The workflow is copied from `cardano-wallet-tools` and adapted:

- `push` and `pull_request` base branch: `setup`.
- Docs build command: `nix develop .#docs --quiet -c mkdocs build --strict --site-dir site`.
- Canonical deploy condition: `github.ref == 'refs/heads/setup'`.
- Keep PR preview publish and closed-PR cleanup behavior.

The README docs section should keep local serving instructions but stop telling users to publish manually with `just deploy-docs`.

## Repository Setting

The ticket owner flips Pages to GitHub Actions with:

```sh
gh api -X PUT repos/lambdasistemi/cip113-tx-builder/pages -f build_type=workflow
```

Current state before the change was verified as:

```json
{"build_type":"legacy","source":{"branch":"gh-pages","path":"/"}}
```

## Verification

- Run `./gate.sh` locally after the slice.
- Push a draft PR against `setup` and verify GitHub Actions.
- Fetch the PR preview URL with `curl -sI` and require HTTP 200.
- Close a preview PR and verify the same URL returns HTTP 404.
- Note that final canonical Pages deployment must be verified after merge to `setup`.
