#!/bin/sh
# Fetches the prebuilt C libraries (libuv, nghttp2, OpenSSL, zlib, PCRE2, libcurl) for one target triple, the way
# `ms` fetches its pinned LLVM tools: .github/workflows/c-libs.yml builds each target once from the sources pinned in
# runtime/third_party/c-libs.lock and publishes `c-libs-<triple>-<key>.tar.gz` to the release `c-libs-<key>`;
# toolchain/c-libs.sums pins each archive's SHA-256. The folder lands in target/c-libs/<triple>-pinned-<key>/{lib,include},
# the same place runtime/third_party/build.sh builds into, and its path is printed.
# Usage: fetch-c-libs.sh <triple>   fetch (or build, see below) and print the folder
#        fetch-c-libs.sh pin <key>  rewrite toolchain/c-libs.sums from the published release for that key
# With no pinned archive for the current key (the pins changed and nothing is published yet), or MS_C_LIBS_BUILD=1,
# it builds from source with build.sh instead (needs make, cmake, perl and the compiler named by CC).
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sums=$repository/toolchain/c-libs.sums
build=$repository/runtime/third_party/build.sh
base=${MS_C_LIBS_URL:-https://github.com/manuscript-lang/manuscript/releases/download}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
if [ "${1:-}" = pin ]; then
    key=${2:?usage: fetch-c-libs.sh pin <key>}
    tmp=$(mktemp)
    curl --fail --location --retry 3 -sS -o "$tmp" "$base/c-libs-$key/SHA256SUMS"
    { grep -v -- "-$key.tar.gz" "$sums" 2>/dev/null || true; cat "$tmp"; } | sort -k2 > "$sums.new"
    mv "$sums.new" "$sums"; rm -f "$tmp"
    exit 0
fi
triple=${1:?usage: fetch-c-libs.sh <triple>}
key=$(sh "$build" key "$triple")
out=$repository/target/c-libs/$triple-pinned-$key
if [ -f "$out/.complete" ]; then echo "$out"; exit 0; fi
name=c-libs-$triple-$key.tar.gz
want=$(awk -v n="$name" '$2==n {print $1}' "$sums" 2>/dev/null || true)
if [ -z "$want" ] || [ "${MS_C_LIBS_BUILD:-}" = 1 ]; then exec sh "$build" "$triple"; fi
mkdir -p "$out.tmp"
archive=$out.tmp/$name
curl --fail --location --retry 3 -sS -o "$archive" "$base/c-libs-$key/$name"
got=$(sha "$archive")
[ "$got" = "$want" ] || { echo "fetch-c-libs: checksum mismatch for $name: expected $want, got $got" >&2; rm -rf "$out.tmp"; exit 1; }
tar -xzf "$archive" -C "$out.tmp"
rm -f "$archive"
touch "$out.tmp/.complete"
rm -rf "$out"
mv "$out.tmp" "$out"
echo "$out"
