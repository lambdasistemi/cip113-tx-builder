#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git diff --check

if [ -d exe ]; then
  nix develop --quiet -c fourmolu --mode check exe/
  nix develop --quiet -c hlint exe/

  cli_out="$(nix build .#cip113-cli --no-link --print-out-paths --print-build-logs)"
  if [ -x "$cli_out/bin/cip113" ]; then
    "$cli_out/bin/cip113" --help >/dev/null
  elif [ -x "$cli_out/bin/cip113-cli" ]; then
    "$cli_out/bin/cip113-cli" --help >/dev/null
  else
    printf 'cip113-cli package did not provide cip113 or cip113-cli in bin/\n' >&2
    exit 1
  fi
else
  printf 'exe/ not present yet; skipping CLI-specific gate checks\n'
fi
