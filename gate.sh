#!/usr/bin/env bash
set -euo pipefail

git diff --check

mapfile -t haskell_files < <(git ls-files '*.hs')
nix develop --quiet -c fourmolu -m check "${haskell_files[@]}"
nix develop --quiet -c hlint exe src e2e-test

nix build .#cip113-cli
freeze_help=$(./result/bin/cip113-cli freeze --help)
seize_help=$(./result/bin/cip113-cli seize --help)

printf '%s\n' "$freeze_help" | grep -q -- '--target-address'
printf '%s\n' "$freeze_help" | grep -q -- '--token-name'
printf '%s\n' "$freeze_help" | grep -q -- '--policy-id'
printf '%s\n' "$freeze_help" | grep -q -- '--change-address'
! printf '%s\n' "$freeze_help" | grep -q -- '--utxo-file'

printf '%s\n' "$seize_help" | grep -q -- '--target-address'
printf '%s\n' "$seize_help" | grep -q -- '--to-address'
printf '%s\n' "$seize_help" | grep -q -- '--token-name'
printf '%s\n' "$seize_help" | grep -q -- '--policy-id'
printf '%s\n' "$seize_help" | grep -q -- '--change-address'
! printf '%s\n' "$seize_help" | grep -q -- '--utxo-file'

nix build .#e2e-tests
./result/bin/e2e-tests
