#!/usr/bin/env bash
set -euo pipefail

git diff --check
git diff --cached --check

if [ -f .github/workflows/darwin-release.yml ]; then
  nix shell --quiet nixpkgs#actionlint --command \
    actionlint .github/workflows/darwin-release.yml
fi

nix eval --quiet .#packages.aarch64-darwin.darwin-release-artifacts.name --raw >/dev/null
nix eval --quiet .#packages.aarch64-darwin.darwin-dev-homebrew-artifacts.name --raw >/dev/null
