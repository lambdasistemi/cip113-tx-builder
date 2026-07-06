# Issue 75 Tasks

## Slice 1 - Darwin release workflow

- [X] T7501 Add `.github/workflows/darwin-release.yml` with `v*` tag,
      `pull_request` to `setup`, and manual dispatch triggers.
- [X] T7502 Build `.#darwin-release-artifacts` for release mode and
      `.#darwin-dev-homebrew-artifacts` for PR/dev mode.
- [X] T7503 Mint a scoped `lambdasistemi-ci` App token for
      `lambdasistemi/homebrew-tap` and use it for tap pushes.
- [X] T7504 Configure PR mode so it installs the generated dev formula through
      a temporary local tap, rewrites only `url` to the fresh tarball, and runs
      `brew test` without mutating the real tap.
- [X] T7505 Use the D0 formula names/classes:
      `cip113-cli.rb` / `Cip113Cli` and `cip113-cli-dev.rb` /
      `Cip113CliDev`.
- [X] T7506 Run `./gate.sh` and commit the workflow change with the required
      `Tasks:` trailer.
