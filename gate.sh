#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c fourmolu --mode check src exe e2e-test
nix develop --quiet -c hlint src exe e2e-test
e2e_tests="$(nix build .#e2e-tests --no-link --print-out-paths --print-build-logs)"
cardano_node="$(nix build .#cardano-node --no-link --print-out-paths --print-build-logs)"
tmpdir="$(mktemp -d)"
cd e2e-test
TMPDIR="$tmpdir" PATH="$cardano_node/bin:$PATH" "$e2e_tests/bin/e2e-tests"
