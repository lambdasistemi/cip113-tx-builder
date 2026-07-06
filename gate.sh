#!/usr/bin/env bash
set -euo pipefail

smoke_linux_artifacts() {
  local artifacts_dir="$1"
  local workdir appimage deb rpm

  artifacts_dir="$(cd "$artifacts_dir" && pwd)"
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  appimage="$(find "$artifacts_dir" -maxdepth 1 -type f -name 'cip113-cli-*-x86_64-linux.AppImage' | sort | head -1)"
  deb="$(find "$artifacts_dir" -maxdepth 1 -type f -name 'cip113-cli-*-x86_64-linux.deb' | sort | head -1)"
  rpm="$(find "$artifacts_dir" -maxdepth 1 -type f -name 'cip113-cli-*-x86_64-linux.rpm' | sort | head -1)"

  test -n "$appimage"
  test -n "$deb"
  test -n "$rpm"

  run_help() {
    local bin="$1"
    test -x "$bin"
    env -u SSL_CERT_FILE -u SYSTEM_CERTIFICATE_PATH "$bin" --help >/dev/null
  }

  find_wrapped_cli() {
    local root="$1"
    find "$root" -path '*-with-ca*/bin/cip113-cli' -type f -executable | sort | head -1
  }

  smoke_appimage() {
    local appimage_dir appimage_copy bin
    appimage_dir="$workdir/appimage"
    mkdir -p "$appimage_dir"
    appimage_copy="$appimage_dir/cip113-cli.AppImage"
    cp -L "$appimage" "$appimage_copy"
    chmod +x "$appimage_copy"
    (cd "$appimage_dir" && "$appimage_copy" --appimage-extract >/dev/null)
    bin="$(find_wrapped_cli "$appimage_dir/squashfs-root")"
    test -n "$bin"
    run_help "$bin"
  }

  smoke_deb() {
    local deb_dir bin
    deb_dir="$workdir/deb"
    mkdir -p "$deb_dir"
    dpkg-deb -x "$deb" "$deb_dir"
    bin="$(find_wrapped_cli "$deb_dir")"
    test -n "$bin"
    run_help "$bin"
  }

  smoke_rpm() {
    local rpm_dir bin
    rpm_dir="$workdir/rpm"
    mkdir -p "$rpm_dir"
    (cd "$rpm_dir" && rpm2cpio "$rpm" | cpio -idm >/dev/null)
    bin="$(find_wrapped_cli "$rpm_dir")"
    test -n "$bin"
    run_help "$bin"
  }

  smoke_appimage
  smoke_deb
  smoke_rpm
}

git diff --check
nix eval --raw .#packages.x86_64-linux.linux-release-artifacts.name >/dev/null
nix eval --raw .#packages.x86_64-linux.linux-dev-release-artifacts.name >/dev/null
nix run --quiet nixpkgs#actionlint -- .github/workflows/release.yml

artifact_dir="$(nix build --quiet .#linux-dev-release-artifacts --no-link --print-out-paths)"
nix shell --quiet nixpkgs#dpkg nixpkgs#rpm nixpkgs#cpio --command bash -c "$(declare -f smoke_linux_artifacts); smoke_linux_artifacts \"\$1\"" bash "$artifact_dir"
