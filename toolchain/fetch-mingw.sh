#!/bin/sh
# Fetches the pinned llvm-mingw release (`toolchain/mingw-version`, checksum in `toolchain/mingw-sha256`) into
# target/llvm-bundle/mingw (override with MINGW_WORK) and prints that directory. `ms` links Windows programs
# with its bundled lld against the mingw-w64 runtime and import libraries in this tree (`<arch>-w64-mingw32/lib`),
# so no MSVC SDK is needed, and builds the runtime and `ring` with its clang (`bin/<arch>-w64-mingw32-clang`).
# The release carries x86_64 and aarch64 libraries whatever the host is.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$repository/toolchain/mingw-version")
sha256=$(tr -d '[:space:]' < "$repository/toolchain/mingw-sha256")
work=${MINGW_WORK:-$repository/target/llvm-bundle/mingw}
host=${MINGW_HOST:-x86_64}
if [ -x "$work/bin/x86_64-w64-mingw32-clang" ] || [ -x "$work/bin/x86_64-w64-mingw32-clang.exe" ] || [ -f "$work/.fetched-$version" ]; then
    echo "$work"
    exit 0
fi
asset=llvm-mingw-$version-ucrt-$host
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ext=zip ;; *) ext=tar.xz ;; esac
mkdir -p "$work"
archive=$work/../llvm-mingw-$version.$ext
curl --fail --location --retry 3 -sS -o "$archive" \
    "https://github.com/mstorsjo/llvm-mingw/releases/download/$version/$asset.$ext"
actual=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$archive"; else shasum -a 256 "$archive"; fi | cut -d' ' -f1 | tr -d "\\")
if [ "$sha256" != "$actual" ]; then
    echo "llvm-mingw checksum mismatch for $asset.$ext: expected $sha256, got $actual" >&2
    [ "$sha256" = unpinned ] || exit 1
    echo "toolchain/mingw-sha256 is unpinned; continuing with the downloaded archive" >&2
fi
if [ "$ext" = zip ]; then
    unzip -q -o "$archive" -d "$work.tmp"
    cp -R "$work.tmp/$asset/." "$work/"
    rm -rf "$work.tmp"
else
    tar -xf "$archive" -C "$work" --strip-components=1
fi
rm -f "$archive"
touch "$work/.fetched-$version"
echo "$work"
