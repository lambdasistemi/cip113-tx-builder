#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix develop --command fourmolu --mode check src/ exe/ e2e-test/
nix develop --command hlint src/ exe/ e2e-test/

cip113_cli=$(nix build .#cip113-cli --no-link --print-out-paths --print-build-logs)

transfer_help=$(mktemp)
"$cip113_cli/bin/cip113-cli" transfer --help >"$transfer_help"
trap 'rm -f "$transfer_help"' EXIT

if grep -E -- '--utxo-file' "$transfer_help"; then
  echo "transfer help still exposes removed offline flag" >&2
  exit 1
fi

grep -q -- '--deployment FILE' "$transfer_help"
grep -q -- 'env: CIP113_DEPLOYMENT FILE' "$transfer_help"
grep -q -- 'deployment:' "$transfer_help"
grep -q -- '--socket-path PATH' "$transfer_help"
grep -q -- 'env: CIP113_SOCKET_PATH PATH' "$transfer_help"
grep -q -- 'socket-path:' "$transfer_help"
grep -q -- '--network-magic INT' "$transfer_help"
grep -q -- 'env: CIP113_NETWORK_MAGIC INT' "$transfer_help"
grep -q -- 'network-magic:' "$transfer_help"
grep -q -- '--from-address ADDR' "$transfer_help"
grep -q -- 'env: CIP113_FROM_ADDRESS ADDR' "$transfer_help"
grep -q -- 'from-address:' "$transfer_help"
grep -q -- '--to-address ADDR' "$transfer_help"
grep -q -- 'env: CIP113_TO_ADDRESS ADDR' "$transfer_help"
grep -q -- 'to-address:' "$transfer_help"
grep -q -- '--token-name NAME' "$transfer_help"
grep -q -- 'env: CIP113_TOKEN_NAME NAME' "$transfer_help"
grep -q -- 'token-name:' "$transfer_help"
grep -q -- '--policy-id HEX' "$transfer_help"
grep -q -- 'env: CIP113_POLICY_ID HEX' "$transfer_help"
grep -q -- 'policy-id:' "$transfer_help"
grep -q -- '--amount INT' "$transfer_help"
grep -q -- 'env: CIP113_AMOUNT INT' "$transfer_help"
grep -q -- 'amount:' "$transfer_help"
grep -q -- '--change-address ADDR' "$transfer_help"
grep -q -- 'env: CIP113_CHANGE_ADDRESS ADDR' "$transfer_help"
grep -q -- 'change-address:' "$transfer_help"

e2e_tests=$(nix build .#e2e-tests --no-link --print-out-paths --print-build-logs)
cardano_node=$(nix build .#cardano-node --no-link --print-out-paths --print-build-logs)
util_linux=$(nix build nixpkgs#util-linux.bin --no-link --print-out-paths --print-build-logs)

"$util_linux/bin/script" --version >/dev/null
tmpdir=$(mktemp -d)
trap 'rm -rf "$transfer_help" "$tmpdir"' EXIT

cd e2e-test
TMPDIR="$tmpdir" \
  CIP113_CLI="$cip113_cli/bin/cip113-cli" \
  PATH="$util_linux/bin:$cardano_node/bin:$PATH" \
  "$e2e_tests/bin/e2e-tests"
