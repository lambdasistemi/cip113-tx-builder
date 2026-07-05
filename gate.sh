#!/usr/bin/env bash
set -euo pipefail

git diff --check

mapfile -t hs_files < <(git ls-files '*.hs')
nix develop --quiet -c fourmolu -m check "${hs_files[@]}"
nix develop --quiet -c hlint src exe e2e-test

nix build .#cip113-cli
nix build .#e2e-tests
(cd e2e-test && ../result/bin/e2e-tests)
