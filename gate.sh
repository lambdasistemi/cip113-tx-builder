#!/usr/bin/env bash
set -euo pipefail

git diff --check

site_dir="$(mktemp -d)"
trap 'rm -rf "$site_dir"' EXIT

nix develop .#docs --quiet -c mkdocs build --site-dir "$site_dir/site"
