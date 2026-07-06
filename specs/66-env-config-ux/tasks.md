# Tasks: CLI env/config UX documentation and E2E proof

## Slice 1 - docs and config-backed e2e proof

- [ ] T6601 Update `docs/cli.md` to document flag, environment variable, and config key mappings for register.
- [ ] T6602 Update `docs/cli.md` to document flag, environment variable, and config key mappings for transfer.
- [ ] T6603 Update `docs/cli.md` to document flag, environment variable, and config key mappings for freeze.
- [ ] T6604 Update `docs/cli.md` to document flag, environment variable, and config key mappings for seize.
- [ ] T6605 Rewrite the tutorial setup to use a YAML config file instead of repeated deployment/socket/network/change shell variables.
- [ ] T6606 Keep the tutorial command sequence aligned with the e2e renderer.
- [ ] T6607 Add live e2e proof for config-file plus env-var invocation with no repeated real-build flags per command.
- [ ] T6608 Run `./gate.sh` successfully.

## Slice 2 - finalization

- [ ] T6609 Re-run the final gate at HEAD and capture root/register help output.
- [ ] T6610 Update the PR body and drop `gate.sh`.
- [ ] T6611 Write the merge-review Q-file for the epic owner.
