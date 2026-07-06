#!/usr/bin/env bash
set -euo pipefail

git diff --check

nix build .#cip113-cli --no-link --print-build-logs

nix eval .#packages.x86_64-linux.linux-release-artifacts.name --raw
nix eval .#packages.x86_64-linux.linux-dev-release-artifacts.name --raw
nix eval .#packages.aarch64-darwin.darwin-release-artifacts.name --raw
nix eval .#packages.aarch64-darwin.darwin-dev-homebrew-artifacts.name --raw
