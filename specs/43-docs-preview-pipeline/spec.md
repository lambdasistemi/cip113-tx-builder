# Spec: Docs Preview and Pages Pipeline

## P1 User Story

As a maintainer, I want documentation changes to publish through GitHub Actions and expose per-PR previews so reviewers can inspect rendered docs before merge.

## Functional Requirements

- Add a documentation deployment workflow modeled on `cardano-wallet-tools`.
- Build docs with `nix develop .#docs --quiet -c mkdocs build --strict --site-dir site`.
- Publish canonical docs from pushes to `setup` using GitHub Pages Actions deployment.
- Publish previews for open pull requests at `https://preview.dev.plutimus.com/lambdasistemi/cip113-tx-builder/pr-<N>/`.
- Remove preview artifacts when the pull request is closed.
- Update README's `## Docs` section to remove manual publish instructions, keep local preview guidance, and point to live docs plus PR previews.
- Flip the repository Pages source from legacy branch deployment to GitHub Actions.

## Success Criteria

- `.github/workflows/deploy-docs.yml` exists and targets `setup`.
- Repository Pages `build_type` is `workflow`.
- A real PR preview URL returns HTTP 200 and has a PR comment link.
- Closing a preview PR removes the preview URL and it returns HTTP 404.
- Final merge to `setup` triggers the real Pages deployment. This is deferred to the epic owner after merge because it cannot be fully proven before the PR lands.

## Non-Goals

- No documentation content changes.
- No `mkdocs.yml` navigation changes.
- No `docs/*.md` or `e2e-test/*` edits.
- No removal of the local `Justfile` `serve-docs` target.
