# Tasks: Freeze/seize settings parsers

## Slice 1 - freeze/seize parser relocation

- [X] T6501 Move freeze option parsing into `Freeze.hs` using shared settings builders.
- [X] T6502 Move seize option parsing into `Seize.hs` using shared settings builders.
- [X] T6503 Remove `--utxo-file` from freeze/seize `Options` records and help output.
- [X] T6504 Delete unreachable offline placeholder code and duplicated parser/validation helpers from `Freeze.hs` and `Seize.hs`.
- [X] T6505 Wire `Main.hs` to `Freeze.parser` and `Seize.parser` with unused-import cleanup.
- [X] T6506 Prove the remaining freeze/seize flags still appear in CLI help and the existing `FreezeSeizeCLISpec` argv strings do not change.
- [X] T6507 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [X] T6508 Re-run the final gate at HEAD and capture help evidence.
- [X] T6509 Update the PR body and drop `gate.sh`.
- [X] T6510 Write the merge-review Q-file for the epic owner.
