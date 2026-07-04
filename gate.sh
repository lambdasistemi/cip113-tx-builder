#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop .#docs --quiet -c mkdocs build --strict --site-dir site
