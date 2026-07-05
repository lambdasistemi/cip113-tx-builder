#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build --quiet .#cip113-cli --no-link
nix develop --quiet -c fourmolu --mode check exe src e2e-test
nix develop --quiet -c hlint exe src e2e-test
