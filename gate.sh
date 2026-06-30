#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build .#cip113-cli --no-link
nix develop --quiet -c fourmolu -m check exe
nix develop --quiet -c hlint exe

policy_id="0123456789abcdef0123456789abcdef0123456789abcdef01234567"
token_name="CIP113"
target_address="addr_test1thirdpartytarget"
to_address="addr_test1thirdpartyseizeto"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

nix build .#cip113-cli --out-link "$tmpdir/cip113-cli"
ln -s "$tmpdir/cip113-cli/bin/cip113-cli" "$tmpdir/cip113"

PATH="$tmpdir:$PATH" cip113 freeze --help >/dev/null
PATH="$tmpdir:$PATH" cip113 seize --help >/dev/null

run_smoke() {
    local command_name="$1"
    local fixture="$2"
    local expected_exit_file="$3"
    shift 3

    test -f "$fixture"
    test -f "$expected_exit_file"

    local expected_exit
    expected_exit=$(tr -d '[:space:]' < "$expected_exit_file")

    local human_output human_exit
    set +e
    human_output=$(
        PATH="$tmpdir:$PATH" cip113 "$command_name" "$@" \
            --utxo-file "$fixture" \
            --target-address "$target_address" \
            --token-name "$token_name" \
            --policy-id "$policy_id" \
            && echo OK
    )
    human_exit=$?
    set -e

    if [ "$human_exit" != "$expected_exit" ]; then
        printf '%s smoke exited %s, expected %s\n' "$command_name" "$human_exit" "$expected_exit" >&2
        printf '%s\n' "$human_output" >&2
        exit 1
    fi

    printf '%s\n' "$human_output" | sed -n '1p' | grep -Eq '^[0-9a-f]+$'
    printf '%s\n' "$human_output" | grep -qx OK

    local json_output
    json_output=$(
        PATH="$tmpdir:$PATH" cip113 --json "$command_name" "$@" \
            --utxo-file "$fixture" \
            --target-address "$target_address" \
            --token-name "$token_name" \
            --policy-id "$policy_id"
    )

    printf '%s\n' "$json_output" | grep -Eq '^\{"tx":"[0-9a-f]+"\}$'
}

run_smoke freeze \
    e2e-test/fixtures/freeze-smoke-utxos.json \
    e2e-test/fixtures/freeze-smoke.expected-exit

run_smoke seize \
    e2e-test/fixtures/seize-smoke-utxos.json \
    e2e-test/fixtures/seize-smoke.expected-exit \
    --to-address "$to_address"
