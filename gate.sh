#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cd "$repo_root"
git diff --check

nix develop --quiet -c fourmolu --mode check src exe e2e-test
nix develop --quiet -c hlint src exe e2e-test

nix build .#e2e-tests
nix build .#cardano-node --out-link e2e-test/result-cardano-node

(
    cd e2e-test
    PATH="$repo_root/e2e-test/result-cardano-node/bin:$PATH" \
        "$repo_root/result/bin/e2e-tests"
)
