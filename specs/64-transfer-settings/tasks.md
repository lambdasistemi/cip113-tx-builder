# Tasks: Transfer settings parser

## Slice 1 - transfer parser relocation

- [X] T6401 Move transfer option parsing into `Transfer.hs` using shared settings builders.
- [X] T6402 Remove `--utxo-file` from `Transfer.Options` and `transfer --help`.
- [X] T6403 Delete unreachable offline placeholder transfer code and duplicated parser/validation helpers from `Transfer.hs`.
- [X] T6404 Wire `Main.hs` to `Transfer.parser` without touching freeze/seize bridge parsers.
- [X] T6405 Prove the help output keeps the remaining transfer flag/env/config settings.
- [X] T6406 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [X] T6407 Re-run the final gate at HEAD and capture help evidence.
- [X] T6408 Update the PR body and drop `gate.sh`.
- [X] T6409 Write the merge-review Q-file for the epic owner.
