# Issue 74 Tasks

## Slice 1 - Linux release workflow

- [X] T7401 Preserve the existing release-please job for pushes to `setup`
      and manual release-please dispatch.
- [X] T7402 Add tag, PR path-filter, and manual Linux modes to
      `.github/workflows/release.yml`.
- [X] T7403 Build `.#linux-release-artifacts` for release mode and
      `.#linux-dev-release-artifacts` for PR/dev mode.
- [X] T7404 Extract AppImage, DEB, and RPM outputs and run extracted
      `cip113-cli --help` offline for each artifact.
- [X] T7405 Upload workflow artifacts for review and attach release
      artifacts only when publishing is enabled.
- [X] T7406 Pass `./gate.sh` and commit the workflow change with the
      required `Tasks:` trailer.
- [X] T7407 Apply a narrow D0 follow-up fix so the Linux DEB/RPM bundlers do
      not fail under Ruby 3.3 `fpm` compatibility.
- [X] T7408 Verify `./gate.sh` builds and smokes both release and dev Linux
      artifact outputs.
