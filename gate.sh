#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build .#cip113-cli --no-link
nix develop --quiet -c fourmolu -m check exe
nix develop --quiet -c hlint exe

fixture="e2e-test/fixtures/transfer-smoke-utxos.json"
expected_exit_file="e2e-test/fixtures/transfer-smoke.expected-exit"

test -f "$fixture"
test -f "$expected_exit_file"

expected_exit=$(tr -d '[:space:]' < "$expected_exit_file")
policy_id="0123456789abcdef0123456789abcdef0123456789abcdef01234567"
token_name="CIP113"
from_address="addr_test1transferfrom"
to_address="addr_test1transferto"
amount="25"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

nix build .#cip113-cli --out-link "$tmpdir/cip113-cli"
ln -s "$tmpdir/cip113-cli/bin/cip113-cli" "$tmpdir/cip113"

set +e
human_output=$(
    PATH="$tmpdir:$PATH" cip113 transfer \
        --utxo-file "$fixture" \
        --from-address "$from_address" \
        --to-address "$to_address" \
        --token-name "$token_name" \
        --policy-id "$policy_id" \
        --amount "$amount" \
        && echo OK
)
human_exit=$?
set -e

if [ "$human_exit" != "$expected_exit" ]; then
    printf 'transfer smoke exited %s, expected %s\n' "$human_exit" "$expected_exit" >&2
    printf '%s\n' "$human_output" >&2
    exit 1
fi

printf '%s\n' "$human_output" | sed -n '1p' | grep -Eq '^[0-9a-f]+$'
printf '%s\n' "$human_output" | grep -qx OK

json_output=$(
    PATH="$tmpdir:$PATH" cip113 --json transfer \
        --utxo-file "$fixture" \
        --from-address "$from_address" \
        --to-address "$to_address" \
        --token-name "$token_name" \
        --policy-id "$policy_id" \
        --amount "$amount"
)

printf '%s\n' "$json_output" | grep -Eq '^\{"tx":"[0-9a-f]+"\}$'
