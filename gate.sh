#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build --quiet .#cip113-cli --no-link
bin=$(nix build --quiet --print-out-paths .#cip113-cli)/bin/cip113-cli
deployment_fixture=e2e-test/fixtures/deployment-smoke.json
malformed_deployment=$(mktemp)
missing_deployment=$(mktemp)
stderr_file=$(mktemp)
trap 'rm -f "$malformed_deployment" "$missing_deployment" "$stderr_file"' EXIT
rm -f "$missing_deployment"
printf '{bad json\n' >"$malformed_deployment"

for command in register transfer freeze seize; do
  "$bin" "$command" --deployment "$deployment_fixture" --help | grep -- '--deployment' >/dev/null
done

policy_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
registry_ref=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#0

if "$bin" --deployment "$missing_deployment" register \
  --deployment "$deployment_fixture" \
  --registry-utxo "$registry_ref" \
  --token-name Smoke \
  --policy-id "$policy_id" 2>"$stderr_file"; then
  echo "expected register without --utxo-file to fail after loading deployment" >&2
  exit 1
fi
grep -- 'register: offline mode requires --utxo-file' "$stderr_file" >/dev/null

if "$bin" register \
  --deployment "$malformed_deployment" \
  --registry-utxo "$registry_ref" \
  --token-name Smoke \
  --policy-id "$policy_id" 2>"$stderr_file"; then
  echo "expected malformed deployment descriptor to fail" >&2
  exit 1
fi
grep -- 'cip113-cli: failed to decode deployment file' "$stderr_file" >/dev/null

if "$bin" register \
  --deployment "$missing_deployment" \
  --registry-utxo "$registry_ref" \
  --token-name Smoke \
  --policy-id "$policy_id" 2>"$stderr_file"; then
  echo "expected missing deployment descriptor to fail" >&2
  exit 1
fi
grep -- 'cip113-cli: failed to read deployment file' "$stderr_file" >/dev/null

nix develop --quiet -c fourmolu --mode check exe src e2e-test
nix develop --quiet -c hlint exe src e2e-test
