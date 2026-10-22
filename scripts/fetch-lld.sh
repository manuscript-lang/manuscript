#!/bin/sh
# Downloads the pinned static lld (and on Linux opt and llc) for a platform into target/llvm-bundle/install/bin, verifying
# its SHA-256 against scripts/lld.lock. Usage: sh scripts/fetch-lld.sh [os arch] [install-dir]
# Defaults to this machine; MS_LLD can point the build at a different lld instead.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
lock="$root/scripts/lld.lock"
os=${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}
arch=${2:-$(uname -m)}
case "$os" in darwin | linux | windows) ;; *) echo "fetch-lld: unsupported os $os" >&2; exit 1 ;; esac
case "$arch" in x86_64 | amd64) arch=amd64 ;; aarch64 | arm64) arch=arm64 ;; *) echo "fetch-lld: unsupported arch $arch" >&2; exit 1 ;; esac
dest=${3:-$root/target/llvm-bundle/install}

tag=$(awk '$1 == "tag" { print $2 }' "$lock")
version=$(awk '$1 == "version" { print $2 }' "$lock")
exe=lld
[ "$os" = windows ] && exe=lld.exe
# The LLVM release build (opt and llc) runs on Linux only.
assets="lld"
[ "$os" = linux ] && assets="lld llvm-tools"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for kind in $assets; do
  asset="$kind-$version-$os-$arch.tar.gz"
  want=$(awk -v a="$asset" '$2 == a { print $1 }' "$lock")
  [ -n "$want" ] || { echo "fetch-lld: $asset is not in scripts/lld.lock" >&2; exit 1; }
  if [ "$(cat "$dest/.asset-$kind" 2>/dev/null)" = "$want" ]; then
    continue
  fi
  curl -fsSL --retry 4 -o "$tmp/$asset" "https://github.com/manuscript-lang/llvm-bundle/releases/download/$tag/$asset"
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$tmp/$asset" | awk '{ print $1 }')
  else
    got=$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')
  fi
  [ "$got" = "$want" ] || { echo "fetch-lld: $asset checksum $got does not match $want" >&2; exit 1; }
  mkdir -p "$dest"
  tar -xzf "$tmp/$asset" -C "$dest"
  printf '%s\n' "$want" > "$dest/.asset-$kind"
done
[ -x "$dest/bin/$exe" ] || { echo "fetch-lld: $dest/bin/$exe is missing" >&2; exit 1; }
