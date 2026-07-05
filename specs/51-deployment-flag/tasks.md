# Tasks: CLI Deployment Descriptor Flag

## Slice 1 - Shared Deployment Flag And Loader

- [X] T051-S1 Add `--deployment FILE` to the shared register/transfer/freeze/seize option path with global and command-local precedence.
- [X] T051-S1 Decode supplied deployment files as `CIP113Deployment` and exit 1 with clear read/decode errors.
- [X] T051-S1 Preserve current placeholder transaction-building behavior when a descriptor is loaded or omitted.
- [X] T051-S1 Update `docs/cli.md` with the flag for all four commands.
- [X] T051-S1 Provide smoke evidence for parser visibility, real descriptor load success, malformed descriptor failure, and missing descriptor failure.
- [X] T051-S1 Run `./gate.sh`.
- [X] T051-S1 Commit the slice as `feat: add shared deployment descriptor flag` with `Tasks: T051-S1`.
