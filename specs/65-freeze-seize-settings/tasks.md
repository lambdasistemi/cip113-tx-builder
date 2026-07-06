# Tasks: Freeze/seize settings parsers

## Slice 1 - freeze/seize parser relocation

- [ ] T6501 Move freeze option parsing into `Freeze.hs` using shared settings builders.
- [ ] T6502 Move seize option parsing into `Seize.hs` using shared settings builders.
- [ ] T6503 Remove `--utxo-file` from freeze/seize `Options` records and help output.
- [ ] T6504 Delete unreachable offline placeholder code and duplicated parser/validation helpers from `Freeze.hs` and `Seize.hs`.
- [ ] T6505 Wire `Main.hs` to `Freeze.parser` and `Seize.parser` with unused-import cleanup.
- [ ] T6506 Prove the remaining freeze/seize flags still appear in CLI help and the existing `FreezeSeizeCLISpec` argv strings do not change.
- [ ] T6507 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [ ] T6508 Re-run the final gate at HEAD and capture help evidence.
- [ ] T6509 Update the PR body and drop `gate.sh`.
- [ ] T6510 Write the merge-review Q-file for the epic owner.
