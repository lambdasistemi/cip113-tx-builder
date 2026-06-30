#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix build .#cip113-cli --no-link
nix develop --quiet -c fourmolu -m check exe
nix develop --quiet -c hlint exe

cli="$(nix build .#cip113-cli --no-link --print-out-paths)/bin/cip113-cli"
fixture="e2e-test/fixtures/register-smoke-utxos.json"
expected_exit_file="e2e-test/fixtures/register-smoke.expected-exit"
registry_utxo="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#0"
policy_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

test -f "$fixture"
test "$(cat "$expected_exit_file")" = "0"

out="$("$cli" register \
  --utxo-file "$fixture" \
  --registry-utxo "$registry_utxo" \
  --token-name CIP113SMOKE \
  --policy-id "$policy_id")"

test -n "$out"
printf '%s\n' "$out" | grep -Eq '^[0-9a-fA-F]+$'

json_out="$("$cli" --json register \
  --utxo-file "$fixture" \
  --registry-utxo "$registry_utxo" \
  --token-name CIP113SMOKE \
  --policy-id "$policy_id")"

printf '%s\n' "$json_out" | grep -Eq '^\{"tx":"[0-9a-fA-F]+"\}$'
