#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c fourmolu --mode check src exe e2e-test
nix develop --quiet -c hlint src exe e2e-test
nix build .#e2e-tests
(cd e2e-test && ../result/bin/e2e-tests)
