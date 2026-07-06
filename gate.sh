#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix develop --command fourmolu --mode check src/ exe/ e2e-test/
nix develop --command hlint src/ exe/ e2e-test/
nix build .#cip113-cli --no-link --print-build-logs

e2e_tests="$(nix build .#e2e-tests --no-link --print-out-paths --print-build-logs)"
cip113_cli="$(nix build .#cip113-cli --no-link --print-out-paths --print-build-logs)"
cardano_node="$(nix build .#cardano-node --no-link --print-out-paths --print-build-logs)"
util_linux="$(nix build nixpkgs#util-linux.bin --no-link --print-out-paths --print-build-logs)"

"$util_linux/bin/script" --version >/dev/null
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cd e2e-test
TMPDIR="$tmpdir" \
    CIP113_CLI="$cip113_cli/bin/cip113-cli" \
    PATH="$util_linux/bin:$cardano_node/bin:$PATH" \
    "$e2e_tests/bin/e2e-tests"
