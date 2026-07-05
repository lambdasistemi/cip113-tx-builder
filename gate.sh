#!/usr/bin/env bash
set -euo pipefail

git diff --check

mapfile -t hs_files < <(git ls-files '*.hs')
nix develop --quiet -c fourmolu -m check "${hs_files[@]}"
nix develop --quiet -c hlint src exe e2e-test

cip113_cli_out=$(nix build --print-out-paths .#cip113-cli)
cardano_node_out=$(nix build --print-out-paths .#cardano-node)
nix build .#e2e-tests
(cd e2e-test && CIP113_CLI="$cip113_cli_out/bin/cip113-cli" PATH="$cardano_node_out/bin:$PATH" ../result/bin/e2e-tests)
