# Tasks: Transfer settings parser

## Slice 1 - transfer parser relocation

- [ ] T6401 Move transfer option parsing into `Transfer.hs` using shared settings builders.
- [ ] T6402 Remove `--utxo-file` from `Transfer.Options` and `transfer --help`.
- [ ] T6403 Delete unreachable offline placeholder transfer code and duplicated parser/validation helpers from `Transfer.hs`.
- [ ] T6404 Wire `Main.hs` to `Transfer.parser` without touching freeze/seize bridge parsers.
- [ ] T6405 Prove the help output keeps the remaining transfer flag/env/config settings.
- [ ] T6406 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [ ] T6407 Re-run the final gate at HEAD and capture help evidence.
- [ ] T6408 Update the PR body and drop `gate.sh`.
- [ ] T6409 Write the merge-review Q-file for the epic owner.
