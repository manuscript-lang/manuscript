#!/bin/sh
# Fetches the pinned shared LLVM library for this host (`toolchain/llvm-lib.lock`: release tag, version and the
# SHA-256 of each platform's archive) from manuscript-lang/llvm-bundle into .artifacts/llvm-lib (override with
# LLVM_LIB_WORK) and prints the absolute path of the library, which is what `MS_LLVM` takes. Does nothing but
# print when the library is already there.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
lock=$repository/toolchain/llvm-lib.lock
tag=$(sed -n 's/^tag //p' "$lock")
version=$(sed -n 's/^version //p' "$lock")
work=${LLVM_LIB_WORK:-$repository/.artifacts/llvm-lib}
case "$(uname -s)" in
Linux) os=linux; library=lib/libLLVM.so ;;
Darwin) os=darwin; library=lib/libLLVM.dylib ;;
MINGW*|MSYS*|CYGWIN*) os=windows; library=bin/LLVM-C.dll ;;
*) echo "no pinned LLVM library for $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
x86_64|amd64) arch=amd64 ;;
arm64|aarch64|ARM64) arch=arm64 ;;
*) echo "no pinned LLVM library for $(uname -m)" >&2; exit 1 ;;
esac
asset=llvm-lib-$version-$os-$arch.tar.gz
want=$(sed -n "s/^\\([0-9a-f]\\{64\\}\\)  $asset\$/\\1/p" "$lock")
if [ -z "$want" ]; then
    echo "toolchain/llvm-lib.lock has no digest for $asset" >&2
    exit 1
fi
here=$work/$tag-$os-$arch
if [ -f "$here/$library" ]; then
    echo "$here/$library"
    exit 0
fi
mkdir -p "$here.tmp"
archive=$here.tmp/$asset
curl --fail --location --retry 3 -sS -o "$archive" \
    "https://github.com/manuscript-lang/llvm-bundle/releases/download/$tag/$asset"
got=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$archive"; else shasum -a 256 "$archive"; fi | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
    echo "$asset checksum mismatch: expected $want, got $got" >&2
    exit 1
fi
tar -xzf "$archive" -C "$here.tmp"
rm -f "$archive"
rm -rf "$here"
mv "$here.tmp" "$here"
echo "$here/$library"
