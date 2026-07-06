#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix develop --command fourmolu --mode check src/ exe/ e2e-test/
nix develop --command hlint src/ exe/ e2e-test/

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cip113_cli=$(nix build .#cip113-cli --no-link --print-out-paths --print-build-logs)
freeze_help="$tmpdir/freeze.help"
seize_help="$tmpdir/seize.help"

"$cip113_cli/bin/cip113-cli" freeze --help >"$freeze_help"
"$cip113_cli/bin/cip113-cli" seize --help >"$seize_help"

if grep -E -- '--utxo-file' "$freeze_help" "$seize_help"; then
  echo "freeze/seize help still exposes removed offline flag" >&2
  exit 1
fi

grep -q -- '--deployment FILE' "$freeze_help"
grep -q -- 'env: CIP113_DEPLOYMENT FILE' "$freeze_help"
grep -q -- 'deployment:' "$freeze_help"
grep -q -- '--socket-path PATH' "$freeze_help"
grep -q -- 'env: CIP113_SOCKET_PATH PATH' "$freeze_help"
grep -q -- 'socket-path:' "$freeze_help"
grep -q -- '--network-magic INT' "$freeze_help"
grep -q -- 'env: CIP113_NETWORK_MAGIC INT' "$freeze_help"
grep -q -- 'network-magic:' "$freeze_help"
grep -q -- '--target-address ADDR' "$freeze_help"
grep -q -- 'env: CIP113_TARGET_ADDRESS ADDR' "$freeze_help"
grep -q -- 'target-address:' "$freeze_help"
grep -q -- '--token-name NAME' "$freeze_help"
grep -q -- 'env: CIP113_TOKEN_NAME NAME' "$freeze_help"
grep -q -- 'token-name:' "$freeze_help"
grep -q -- '--policy-id HEX' "$freeze_help"
grep -q -- 'env: CIP113_POLICY_ID HEX' "$freeze_help"
grep -q -- 'policy-id:' "$freeze_help"
grep -q -- '--change-address ADDR' "$freeze_help"
grep -q -- 'env: CIP113_CHANGE_ADDRESS ADDR' "$freeze_help"
grep -q -- 'change-address:' "$freeze_help"

grep -q -- '--deployment FILE' "$seize_help"
grep -q -- 'env: CIP113_DEPLOYMENT FILE' "$seize_help"
grep -q -- 'deployment:' "$seize_help"
grep -q -- '--socket-path PATH' "$seize_help"
grep -q -- 'env: CIP113_SOCKET_PATH PATH' "$seize_help"
grep -q -- 'socket-path:' "$seize_help"
grep -q -- '--network-magic INT' "$seize_help"
grep -q -- 'env: CIP113_NETWORK_MAGIC INT' "$seize_help"
grep -q -- 'network-magic:' "$seize_help"
grep -q -- '--target-address ADDR' "$seize_help"
grep -q -- 'env: CIP113_TARGET_ADDRESS ADDR' "$seize_help"
grep -q -- 'target-address:' "$seize_help"
grep -q -- '--to-address ADDR' "$seize_help"
grep -q -- 'env: CIP113_TO_ADDRESS ADDR' "$seize_help"
grep -q -- 'to-address:' "$seize_help"
grep -q -- '--token-name NAME' "$seize_help"
grep -q -- 'env: CIP113_TOKEN_NAME NAME' "$seize_help"
grep -q -- 'token-name:' "$seize_help"
grep -q -- '--policy-id HEX' "$seize_help"
grep -q -- 'env: CIP113_POLICY_ID HEX' "$seize_help"
grep -q -- 'policy-id:' "$seize_help"
grep -q -- '--change-address ADDR' "$seize_help"
grep -q -- 'env: CIP113_CHANGE_ADDRESS ADDR' "$seize_help"
grep -q -- 'change-address:' "$seize_help"

e2e_tests=$(nix build .#e2e-tests --no-link --print-out-paths --print-build-logs)
cardano_node=$(nix build .#cardano-node --no-link --print-out-paths --print-build-logs)
util_linux=$(nix build nixpkgs#util-linux.bin --no-link --print-out-paths --print-build-logs)

"$util_linux/bin/script" --version >/dev/null

cd e2e-test
TMPDIR="$tmpdir" \
  CIP113_CLI="$cip113_cli/bin/cip113-cli" \
  PATH="$util_linux/bin:$cardano_node/bin:$PATH" \
  "$e2e_tests/bin/e2e-tests"
