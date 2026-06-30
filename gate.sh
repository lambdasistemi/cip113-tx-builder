#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build --quiet .#cip113-cli
nix develop --quiet -c fourmolu --mode check exe
nix develop --quiet -c hlint exe

if [ "${CIP113_GATE_PHASE:-}" = "provider" ]; then
  exit 0
fi

BIN="./result/bin/cip113-cli"
POLICY_ID="0123456789abcdef0123456789abcdef0123456789abcdef01234567"

"$BIN" register \
  --utxo-file e2e-test/fixtures/register-smoke-utxos.json \
  --registry-utxo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#0 \
  --token-name CIP113 \
  --policy-id "$POLICY_ID" \
  >/dev/null

missing_socket="$(mktemp -u /tmp/cip113-node-missing.XXXXXX.sock)"
set +e
"$BIN" \
  --socket-path "$missing_socket" \
  --network-magic 2 \
  register \
  --registry-utxo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#0 \
  --token-name CIP113 \
  --policy-id "$POLICY_ID" \
  >/tmp/cip113-node-missing.out \
  2>/tmp/cip113-node-missing.err
status=$?
set -e

if [ "$status" -ne 1 ]; then
  echo "expected missing node socket to exit 1, got $status" >&2
  cat /tmp/cip113-node-missing.out >&2 || true
  cat /tmp/cip113-node-missing.err >&2 || true
  exit 1
fi

if ! grep -Eiq 'socket|node' /tmp/cip113-node-missing.err; then
  echo "expected missing node socket error to mention socket/node" >&2
  cat /tmp/cip113-node-missing.err >&2 || true
  exit 1
fi
