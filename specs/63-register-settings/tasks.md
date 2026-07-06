# Tasks: Register settings parser

## Slice 1 - register parser relocation

- [X] T6301 Move register option parsing into `Register.hs` using shared settings builders.
- [X] T6302 Remove `--utxo-file` and `--registry-utxo` from `Register.Options` and `register --help`.
- [X] T6303 Delete unreachable offline placeholder register code and duplicated validation helpers from `Register.hs`.
- [X] T6304 Wire `Main.hs` to `Register.parser` without touching transfer/freeze/seize bridge parsers.
- [X] T6305 Prove the help output keeps the remaining register flag/env/config settings.
- [X] T6306 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [X] T6307 Re-run the final gate at HEAD and capture help evidence.
- [X] T6308 Update the PR body and drop `gate.sh`.
- [X] T6309 Write the merge-review Q-file for the epic owner.
