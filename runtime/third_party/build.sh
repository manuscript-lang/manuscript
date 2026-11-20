#!/bin/sh
# Builds the C libraries the networking runtime links (libuv, nghttp2, llhttp, OpenSSL) as static archives.
# Sources are pinned in runtime/third_party/c-libs.lock (sha256 checked) and fetched into target/c-libs/src; llhttp is vendored.
# Output: target/c-libs/<triple>-<key>/{lib,include}. Usage: build.sh [triple]; `build.sh key [triple]` prints the cache key. CC chooses the compiler.
# Needs a C compiler, make, cmake and perl (OpenSSL's Configure). Using `ms` needs none of them.
# MS_C_LIBS=system builds only the vendored parts (llhttp, QBE); libs.sh then finds the rest with pkg-config.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
triple=${1:-host}
[ "$triple" = key ] && triple=${2:-host}
root=$repository/target/c-libs
src=$root/src
cc=${CC:-cc}
mode=${MS_C_LIBS:-system}
case "$mode" in system|pinned) ;; *) echo "MS_C_LIBS must be system or pinned, not $mode" >&2; exit 1 ;; esac
# One build for every dependency. The output folder is named by a hash of everything that decides its contents
# (pins, this script, the triple, the compilers), so a CI cache keyed on `key` restores it whole and a change to any
# input starts a clean build of all of them.
hash_input() { cat "$repository/runtime/third_party/c-libs.lock" "$repository/runtime/third_party/build.sh"; find "$repository/runtime/third_party/llhttp" "$repository/runtime/third_party/qbe" -type f | sort | xargs cat; printf '%s\n%s\n%s\n' "$triple" "$("$cc" --version | head -1)" "$mode"; }
key=$(hash_input | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16)
if [ "${1:-}" = key ]; then echo "$key"; exit 0; fi
out=$root/$triple-$mode-$key
if [ -f "$out/.complete" ]; then echo "$out"; exit 0; fi
# Parallel runs (the glibc, musl and profiling runtime builds of `cargo xtask runtime`) share one output folder, so one
# builds while the others wait for `.complete`. mkdir is atomic; a lock left by a killed run is reported, not stolen.
mkdir -p "$root"
lock=$out.lock
waited=0
until mkdir "$lock" 2>/dev/null; do
    [ -f "$out/.complete" ] && { echo "$out"; exit 0; }
    [ "$waited" -lt 1800 ] || { echo "build.sh: $lock is held for 30 minutes; remove it if no build is running" >&2; exit 1; }
    sleep 1
    waited=$((waited + 1))
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
trap 'exit 1' INT TERM
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
if [ "$mode" = pinned ]; then
    while read -r name version url hash; do
        case "$name" in ''|'#'*) continue ;; esac
        fetch "$name" "$version" "$url" "$hash"
    done < "$repository/runtime/third_party/c-libs.lock"
fi
version_of() { awk -v n="$1" '$1==n {print $2}' "$repository/runtime/third_party/c-libs.lock"; }
cmake_flags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$cc -DCMAKE_POSITION_INDEPENDENT_CODE=ON"

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
if [ "$mode" = system ]; then touch "$out/.complete"; echo "$out"; exit 0; fi
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
if [ ! -f "$out/lib/libssl.a" ]; then
    # no-secure-memory: its mmap-locked heap needs kernel headers (<linux/mman.h>) that musl-gcc does not see, and we keep no keys in a locked heap.
    build=$root/build/$triple/openssl
    rm -rf "$build"; mkdir -p "$build"
    (cd "$build" && CC="$cc" perl "$src/openssl-$(version_of openssl)/Configure" no-shared no-tests no-docs no-apps no-module no-legacy no-dso no-engine no-afalgeng no-comp no-ssl3 no-weak-ssl-ciphers no-secure-memory --libdir=lib --prefix="$build/install" >/dev/null \
        && make -j "$jobs" build_libs >/dev/null && cp libssl.a libcrypto.a "$out/lib/" && mkdir -p "$out/include/openssl" \
        && cp "$src/openssl-$(version_of openssl)"/include/openssl/*.h include/openssl/*.h "$out/include/openssl/")
fi
if [ ! -f "$out/lib/libz.a" ]; then
    # zlib: the in-memory deflate and inflate code only, compiled directly (no gz file layer, no build system).
    build=$root/build/$triple/zlib
    zsrc=$src/zlib-$(version_of zlib)
    mkdir -p "$build"
    for f in adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil; do "$cc" -O2 -fPIC -I"$zsrc" -c "$zsrc/$f.c" -o "$build/$f.o"; done
    ar rcs "$out/lib/libz.a" "$build"/*.o
    cp "$zsrc/zlib.h" "$zsrc/zconf.h" "$out/include/"
fi
if [ ! -f "$out/lib/libpcre2-8.a" ]; then
    # PCRE2, 8-bit library only, with its JIT. Plain C: no C++ runtime in programs.
    build=$root/build/$triple/pcre2
    cmake -S "$src/pcre2-$(version_of pcre2)" -B "$build" $cmake_flags -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF -DPCRE2_SUPPORT_JIT=ON -DPCRE2_SUPPORT_UNICODE=ON -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_LIBZ=OFF -DPCRE2_SUPPORT_LIBBZ2=OFF -DPCRE2_SUPPORT_LIBREADLINE=OFF >/dev/null
    cmake --build "$build" -j "$jobs" >/dev/null
    cp "$build/libpcre2-8.a" "$out/lib/"
    cp "$build/interface/pcre2.h" "$out/include/"
fi
touch "$out/.complete"
echo "$out"
