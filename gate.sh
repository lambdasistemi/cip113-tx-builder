#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix develop --command fourmolu --mode check src/ exe/ e2e-test/
nix develop --command hlint src/ exe/ e2e-test/

cip113_cli=$(nix build .#cip113-cli --no-link --print-out-paths --print-build-logs)

register_help=$(mktemp)
"$cip113_cli/bin/cip113-cli" register --help >"$register_help"
trap 'rm -f "$register_help"' EXIT

if grep -E -- '--utxo-file|--registry-utxo' "$register_help"; then
  echo "register help still exposes removed offline flags" >&2
  exit 1
fi

grep -q -- '--deployment FILE' "$register_help"
grep -q -- 'env: CIP113_DEPLOYMENT FILE' "$register_help"
grep -q -- 'deployment:' "$register_help"
grep -q -- '--socket-path PATH' "$register_help"
grep -q -- 'env: CIP113_SOCKET_PATH PATH' "$register_help"
grep -q -- 'socket-path:' "$register_help"
grep -q -- '--network-magic INT' "$register_help"
grep -q -- 'env: CIP113_NETWORK_MAGIC INT' "$register_help"
grep -q -- 'network-magic:' "$register_help"
grep -q -- '--token-name NAME' "$register_help"
grep -q -- 'env: CIP113_TOKEN_NAME NAME' "$register_help"
grep -q -- 'token-name:' "$register_help"
grep -q -- '--policy-id HEX' "$register_help"
grep -q -- 'env: CIP113_POLICY_ID HEX' "$register_help"
grep -q -- 'policy-id:' "$register_help"
grep -q -- '--change-address ADDR' "$register_help"
grep -q -- 'env: CIP113_CHANGE_ADDRESS ADDR' "$register_help"
grep -q -- 'change-address:' "$register_help"

e2e_tests=$(nix build .#e2e-tests --no-link --print-out-paths --print-build-logs)
cardano_node=$(nix build .#cardano-node --no-link --print-out-paths --print-build-logs)
util_linux=$(nix build nixpkgs#util-linux.bin --no-link --print-out-paths --print-build-logs)

"$util_linux/bin/script" --version >/dev/null
tmpdir=$(mktemp -d)
trap 'rm -rf "$register_help" "$tmpdir"' EXIT

cd e2e-test
TMPDIR="$tmpdir" \
  CIP113_CLI="$cip113_cli/bin/cip113-cli" \
  PATH="$util_linux/bin:$cardano_node/bin:$PATH" \
  "$e2e_tests/bin/e2e-tests"
