#!/bin/sh
# Builds the C libraries the networking runtime links (libuv, nghttp2, llhttp, OpenSSL) as static archives.
# Sources are pinned in runtime/third_party/c-libs.lock (sha256 checked) and fetched into target/c-libs/src; llhttp is vendored.
# Output: target/c-libs/<triple>-<key>/{lib,include}. Usage: build.sh [triple]; `build.sh key [triple]` prints the cache key. CC and CXX choose the compilers.
# Needs a C compiler, make, cmake and perl (OpenSSL's Configure). Using `ms` needs none of them.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
triple=${1:-host}
[ "$triple" = key ] && triple=${2:-host}
root=$repository/target/c-libs
src=$root/src
cc=${CC:-cc}
cxx=${CXX:-c++}
# One build for every dependency. The output folder is named by a hash of everything that decides its contents
# (pins, this script, the triple, the compilers), so a CI cache keyed on `key` restores it whole and a change to any
# input starts a clean build of all of them.
hash_input() { cat "$repository/runtime/third_party/c-libs.lock" "$repository/runtime/third_party/build.sh"; find "$repository/runtime/third_party/llhttp" "$repository/runtime/third_party/qbe" -type f | sort | xargs cat; printf '%s\n%s\n%s\n' "$triple" "$("$cc" --version | head -1)" "$("$cxx" --version | head -1)"; }
key=$(hash_input | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16)
if [ "${1:-}" = key ]; then echo "$key"; exit 0; fi
out=$root/$triple-$key
if [ -f "$out/.complete" ]; then echo "$out"; exit 0; fi
rm -rf "$out"
jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
mkdir -p "$src" "$out/lib" "$out/include"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
fetch() { # name version url sha256
    dir=$src/$1-$2
    [ -d "$dir" ] && return 0
    archive=$src/$(basename "$3")
    [ -f "$archive" ] || curl --fail --location --retry 3 -sS -o "$archive" "$3"
    [ "$(sha "$archive")" = "$4" ] || { echo "$1: checksum mismatch for $3" >&2; exit 1; }
    mkdir -p "$dir.tmp"
    tar -xf "$archive" -C "$dir.tmp" --strip-components=1
    mv "$dir.tmp" "$dir"
}
while read -r name version url hash; do
    case "$name" in ''|'#'*) continue ;; esac
    fetch "$name" "$version" "$url" "$hash"
done < "$repository/runtime/third_party/c-libs.lock"
version_of() { awk -v n="$1" '$1==n {print $2}' "$repository/runtime/third_party/c-libs.lock"; }
cmake_flags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$cc -DCMAKE_POSITION_INDEPENDENT_CODE=ON"

if [ ! -f "$out/lib/libuv.a" ]; then
    build=$root/build/$triple/libuv
    cmake -S "$src/libuv-$(version_of libuv)" -B "$build" $cmake_flags -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF >/dev/null
    cmake --build "$build" -j "$jobs" >/dev/null
    cp "$build"/libuv.a "$out/lib/"
    cp -R "$src/libuv-$(version_of libuv)/include/." "$out/include/"
fi
if [ ! -f "$out/lib/libnghttp2.a" ]; then
    build=$root/build/$triple/nghttp2
    cmake -S "$src/nghttp2-$(version_of nghttp2)" -B "$build" $cmake_flags -DENABLE_LIB_ONLY=ON -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF >/dev/null
    cmake --build "$build" -j "$jobs" >/dev/null
    cp "$build"/lib/libnghttp2.a "$out/lib/"
    mkdir -p "$out/include/nghttp2"
    cp "$src/nghttp2-$(version_of nghttp2)"/lib/includes/nghttp2/nghttp2.h "$build"/lib/includes/nghttp2/nghttp2ver.h "$out/include/nghttp2/"
fi
if [ ! -f "$out/lib/libllhttp.a" ]; then
    build=$root/build/$triple/llhttp
    mkdir -p "$build"
    for f in api http llhttp; do "$cc" -O2 -fPIC -I"$repository/runtime/third_party/llhttp/include" -c "$repository/runtime/third_party/llhttp/src/$f.c" -o "$build/$f.o"; done
    ar rcs "$out/lib/libllhttp.a" "$build"/*.o
    cp "$repository/runtime/third_party/llhttp/include/llhttp.h" "$out/include/"
fi
if [ ! -f "$out/bin/qbe" ]; then
    # QBE 1.3, the debug code generator: a standalone compiler from its SSA text to assembly; targets are chosen with -t at run time.
    mkdir -p "$out/bin"
    q=$repository/runtime/third_party/qbe
    "$cc" -std=c99 -O2 -I"$q" "$q"/*.c "$q"/amd64/*.c "$q"/arm64/*.c "$q"/rv64/*.c -o "$out/bin/qbe"
fi
if [ ! -f "$out/lib/libssl.a" ]; then
    build=$root/build/$triple/openssl
    rm -rf "$build"; mkdir -p "$build"
    (cd "$build" && CC="$cc" perl "$src/openssl-$(version_of openssl)/Configure" no-shared no-tests no-docs no-apps no-module no-legacy no-dso no-engine no-afalgeng no-comp no-ssl3 no-weak-ssl-ciphers --libdir=lib --prefix="$build/install" >/dev/null \
        && make -j "$jobs" build_libs >/dev/null && cp libssl.a libcrypto.a "$out/lib/" && mkdir -p "$out/include/openssl" \
        && cp "$src/openssl-$(version_of openssl)"/include/openssl/*.h include/openssl/*.h "$out/include/openssl/")
fi
if [ ! -f "$out/lib/libre2.a" ]; then
    # RE2 is C++17 and needs Abseil; both build static and install into one prefix. The runtime links libstdc++ (libc++ on macOS and mingw) statically.
    build=$root/build/$triple/abseil
    cmake -S "$src/abseil-$(version_of abseil)" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER="$cxx" -DCMAKE_CXX_STANDARD=17 -DABSL_PROPAGATE_CXX_STD=ON -DABSL_BUILD_TESTING=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX="$root/build/$triple/absl-install" >/dev/null
    cmake --build "$build" -j "$jobs" >/dev/null
    cmake --install "$build" >/dev/null
    build=$root/build/$triple/re2
    cmake -S "$src/re2-$(version_of re2)" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER="$cxx" -DCMAKE_CXX_STANDARD=17 -DRE2_BUILD_TESTING=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_PREFIX_PATH="$root/build/$triple/absl-install" >/dev/null
    cmake --build "$build" -j "$jobs" >/dev/null
    cp "$build/libre2.a" "$out/lib/"
    mkdir -p "$out/include/re2"
    cp "$src/re2-$(version_of re2)"/re2/*.h "$out/include/re2/"
    cp "$root/build/$triple/absl-install"/lib/libabsl_*.a "$out/lib/"
    cp -R "$root/build/$triple/absl-install/include/absl" "$out/include/"
fi
touch "$out/.complete"
echo "$out"
