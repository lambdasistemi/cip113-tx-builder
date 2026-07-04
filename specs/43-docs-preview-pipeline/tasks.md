# Tasks: Docs Preview and Pages Pipeline

## Slice 1: Workflow and README

- [X] T043-S1 Add `.github/workflows/deploy-docs.yml` adapted for `setup`, `.#docs`, Pages deploy, PR previews, and preview cleanup.
- [X] T043-S1 Update README `## Docs` to keep local preview guidance, remove manual publish instructions, and mention live docs plus PR previews.
- [X] T043-S1 Run the local docs gate with `./gate.sh`.
- [X] T043-S1 Commit the slice as `ci: add docs preview and pages workflow` with `Tasks: T043-S1`.

## Ticket Owner Verification

- [X] T043-V1 Flip repository Pages source to GitHub Actions and verify `build_type=workflow`.
- [X] T043-V1 Push draft PR against `setup`.
- [X] T043-V1 Verify a real PR preview URL returns HTTP 200 and is linked by a PR comment.
- [X] T043-V1 Verify closing a preview PR removes the preview URL with HTTP 404.
- [X] T043-V1 Record post-merge Pages deployment verification as deferred to the epic owner.
