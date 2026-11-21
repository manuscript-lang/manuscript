#!/bin/sh
# Builds the pinned C libraries the runtime links (libuv, nghttp2, OpenSSL, zlib, PCRE2, libcurl) as static archives
# (cmake/MsLibs.cmake takes the folder as MS_LIBS_PREFIX). llhttp is vendored and built by CMake.
# Sources are vendored (trimmed of tests and docs) in runtime/third_party/<name>; c-libs.lock records each upstream version, URL and
# SHA-256 of the tarball they came from. Nothing is downloaded.
# Output: target/c-libs/<triple>-pinned-<key>/{lib,include}. Usage: build.sh [triple]; `build.sh key [triple]` prints the cache key.
# CC chooses the compiler (musl-gcc for musl, llvm-mingw's clang for Windows). Needs a C compiler, make, cmake and perl (OpenSSL's Configure). Using `ms` needs none of them.
set -e
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
triple=${1:-host}
[ "$triple" = key ] && triple=${2:-host}
root=$repository/target/c-libs
cc=$(printf "%s" "${CC:-cc}" | tr "\\\\" "/") # forward slashes: sh drops the backslashes of a Windows path
mode=pinned
# One build for every dependency. The output folder is named by a hash of everything that decides its contents
# (pins, this script, the triple), so a published archive and a CI cache keyed on `key` restore it whole and a change
# to any input starts a clean build of all of them. The compiler is not part of the key: the published archives are the
# one build everyone uses, so the key must not change with the machine that asks for it.
hash_input() { cat "$repository/runtime/third_party/c-libs.lock" "$repository/runtime/third_party/build.sh"; printf '%s\n%s\n' "$triple" "$mode"; }
key=$(hash_input | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16)
if [ "${1:-}" = key ]; then echo "$key"; exit 0; fi
out=$root/$triple-$mode-$key
# The folder is printed in the form native tools take: on Windows MSYS paths (/d/a/...) become D:/a/... for CMake.
emit() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$out"; else echo "$out"; fi; }
if [ -f "$out/.complete" ]; then emit; exit 0; fi
# Parallel runs (the glibc, musl and profiling runtime builds of `cargo xtask runtime`) share one output folder, so one
# builds while the others wait for `.complete`. mkdir is atomic; a lock left by a killed run is reported, not stolen.
mkdir -p "$root"
lock=$out.lock
waited=0
until mkdir "$lock" 2>/dev/null; do
    [ -f "$out/.complete" ] && { emit; exit 0; }
    [ "$waited" -lt 1800 ] || { echo "build.sh: $lock is held for 30 minutes; remove it if no build is running" >&2; exit 1; }
    sleep 1
    waited=$((waited + 1))
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
trap 'exit 1' INT TERM
if [ -f "$out/.complete" ]; then emit; exit 0; fi
rm -rf "$out"
jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
mkdir -p "$out/lib" "$out/include"
vendor=$repository/runtime/third_party
cmake_flags="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$cc -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
command -v ninja >/dev/null 2>&1 && cmake_flags="$cmake_flags -G Ninja"
arch=${triple%%-*}
[ "$triple" = host ] && arch=$(uname -m)
# What the target needs beyond the compiler: OpenSSL's Configure target, CMake's system, the Windows library names.
case "$triple" in
*windows*) # llvm-mingw's clang, cross or native; mingw-w64 builds archives named lib*.a.
    cmake_flags="$cmake_flags -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER_TARGET=$arch-w64-mingw32"
    # OpenSSL's cross-compile prefix would name a gcc that is not installed; CC (llvm-mingw's clang) and its archiver are used by path.
    ssl_target=mingw64; ssl_extra="$([ "$arch" = x86_64 ] || echo no-asm)"
    case "$cc" in */*) tools=$(dirname "$cc"); export AR="$tools/llvm-ar" RANLIB="$tools/llvm-ranlib" ;; esac ;;
*apple-darwin*)
    export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}
    case "$arch" in arm64|aarch64) cmake_arch=arm64; ssl_target=darwin64-arm64-cc ;; *) cmake_arch=x86_64; ssl_target=darwin64-x86_64-cc ;; esac
    cmake_flags="$cmake_flags -DCMAKE_OSX_ARCHITECTURES=$cmake_arch -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
    ssl_extra="" ;;
*-linux-musl)
    # musl-gcc sees only musl's headers; libuv wants the kernel's (<linux/errqueue.h>), which the distribution keeps beside glibc's.
    export CFLAGS="${CFLAGS:-} -idirafter /usr/include/$arch-linux-gnu -idirafter /usr/include"
    case "$arch" in aarch64|arm64) export CFLAGS="$CFLAGS -mno-outline-atomics"; ssl_target=linux-aarch64 ;; x86_64) ssl_target=linux-x86_64 ;; *) ssl_target=linux-generic64 ;; esac
    ssl_extra="" ;;
*)
    # Programs link no libgcc or compiler-rt, so atomics must be inline (outline atomics call __aarch64_ldadd8_* and friends).
    case "$arch" in aarch64|arm64) export CFLAGS="${CFLAGS:-} -mno-outline-atomics" ;; esac
    case "$arch" in aarch64|arm64) ssl_target=linux-aarch64 ;; x86_64) ssl_target=linux-x86_64 ;; *) ssl_target=linux-generic64 ;; esac
    ssl_extra="" ;;
esac

# Runs a build step with its output held back: a failing step prints the tail of its output and stops the build.
quiet() { "$@" >"$out/step.log" 2>&1 || { tail -n 60 "$out/step.log" >&2; echo "build.sh: failed: $*" >&2; exit 1; }; }

if [ ! -f "$out/lib/libuv.a" ]; then
    build=$root/build/$triple/libuv
    quiet cmake -S "$vendor/libuv" -B "$build" $cmake_flags -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF
    quiet cmake --build "$build" -j "$jobs"
    cp "$build"/libuv.a "$out/lib/"
    cp -R "$vendor/libuv/include/." "$out/include/"
fi
if [ ! -f "$out/lib/libnghttp2.a" ]; then
    build=$root/build/$triple/nghttp2
    quiet cmake -S "$vendor/nghttp2" -B "$build" $cmake_flags -DENABLE_LIB_ONLY=ON -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF
    quiet cmake --build "$build" -j "$jobs"
    cp "$build"/lib/libnghttp2.a "$out/lib/"
    mkdir -p "$out/include/nghttp2"
    cp "$vendor/nghttp2"/lib/includes/nghttp2/nghttp2.h "$build"/lib/includes/nghttp2/nghttp2ver.h "$out/include/nghttp2/"
fi
# OpenSSL's Configure needs a perl that produces Unix-like paths (not Strawberry or ActiveState Perl, which report MSWin32).
# The shell's perl is tried first, then MSYS2's (Windows tries MSYS2's first).
msys=${MS_MSYS2:-C:/msys64}
perl=
candidates="perl $msys/usr/bin/perl"
# On Windows, MSYS2's perl and make go together: its perl records /d/a/... paths that only MSYS2's make resolves.
case "$triple" in *windows*) candidates="$msys/usr/bin/perl perl" ;; esac
for candidate in $candidates; do
    if "$candidate" -e 'exit($^O eq "MSWin32")' >/dev/null 2>&1; then perl=$candidate; break; fi
done
if [ ! -f "$out/lib/libssl.a" ]; then
    [ -n "$perl" ] || { echo "build.sh: no Unix-style perl (OpenSSL's Configure needs one; on Windows install MSYS2's perl)" >&2; exit 1; }
    # CC, AR and RANLIB go to Configure as arguments: it records them in the Makefile, where a variable in the environment was lost under MSYS2 and the build fell back to the first gcc on PATH (x64 objects in an arm64 archive).
    # no-secure-memory: its mmap-locked heap needs kernel headers (<linux/mman.h>) that musl-gcc does not see, and we keep no keys in a locked heap.
    perl_dir=; ssl_make=make
    # MSYS2's perl records MSYS-style paths (/d/a/...) in configdata.pm, which only MSYS2's own make can resolve.
    case "$perl" in */*) perl_dir=$(dirname "$perl"):; [ -x "$(dirname "$perl")/make" ] && ssl_make=$(dirname "$perl")/make ;; esac
    build=$root/build/$triple/openssl
    rm -rf "$build"; mkdir -p "$build"
    (cd "$build" && PATH="$perl_dir$PATH" quiet "$perl" "$vendor/openssl/Configure" "$ssl_target" "CC=$cc" ${AR:+"AR=$AR"} ${RANLIB:+"RANLIB=$RANLIB"} $ssl_extra no-shared no-tests no-docs no-apps no-module no-legacy no-dso no-engine no-afalgeng no-comp no-ssl3 no-weak-ssl-ciphers no-secure-memory --libdir=lib --prefix="$build/install" \
        && quiet "$ssl_make" -j "$jobs" build_libs && cp libssl.a libcrypto.a "$out/lib/" && mkdir -p "$out/include/openssl" \
        && cp "$vendor/openssl"/include/openssl/*.h include/openssl/*.h "$out/include/openssl/")
fi
if [ ! -f "$out/lib/libz.a" ]; then
    # zlib: the in-memory deflate and inflate code only, compiled directly (no gz file layer, no build system).
    build=$root/build/$triple/zlib
    zsrc=$vendor/zlib
    mkdir -p "$build"
    for f in adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil; do "$cc" -O2 -fPIC ${CFLAGS:-} -I"$zsrc" -c "$zsrc/$f.c" -o "$build/$f.o"; done
    ar rcs "$out/lib/libz.a" "$build"/*.o
    cp "$zsrc/zlib.h" "$zsrc/zconf.h" "$out/include/"
fi
if [ ! -f "$out/lib/libpcre2-8.a" ]; then
    # PCRE2, 8-bit library only, with its JIT. Plain C: no C++ runtime in programs.
    build=$root/build/$triple/pcre2
    quiet cmake -S "$vendor/pcre2" -B "$build" $cmake_flags -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF -DPCRE2_SUPPORT_JIT=ON -DPCRE2_SUPPORT_UNICODE=ON -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_LIBZ=OFF -DPCRE2_SUPPORT_LIBBZ2=OFF -DPCRE2_SUPPORT_LIBREADLINE=OFF
    quiet cmake --build "$build" -j "$jobs"
    cp "$build/libpcre2-8.a" "$out/lib/"
    cp "$build/interface/pcre2.h" "$out/include/"
fi
if [ ! -f "$out/lib/libcurl.a" ]; then
    # libcurl: HTTP and HTTPS only (HTTP/2 through nghttp2, Unix sockets, cookies, proxies), on the OpenSSL and zlib built above. No other protocols,
    # no extra libraries (psl, idn, ssh, brotli, zstd), no executable.
    build=$root/build/$triple/curl
    # nghttp2's header marks its functions dllimport unless told the library is static; curl's CMake does not tell it on Windows.
    curl_defs=""
    case "$triple" in *windows*) curl_defs="-DCMAKE_C_FLAGS=-DNGHTTP2_STATICLIB" ;; esac
    quiet cmake -S "$vendor/curl" -B "$build" $cmake_flags $curl_defs -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF \
        -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON -DCURL_USE_OPENSSL=ON -DUSE_NGHTTP2=ON -DCURL_ZLIB=ON -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF \
        -DUSE_LIBIDN2=OFF -DCURL_USE_GSSAPI=OFF -DENABLE_UNIX_SOCKETS=ON -DCURL_ENABLE_SSL=ON \
        -DCMAKE_PREFIX_PATH="$out" -DOPENSSL_ROOT_DIR="$out" -DOPENSSL_USE_STATIC_LIBS=ON -DZLIB_ROOT="$out" \
        -DNGHTTP2_INCLUDE_DIR="$out/include" -DNGHTTP2_LIBRARY="$out/lib/libnghttp2.a"
    quiet cmake --build "$build" -j "$jobs"
    cp "$build"/lib/libcurl.a "$out/lib/"
    mkdir -p "$out/include/curl"
    cp "$vendor/curl"/include/curl/*.h "$out/include/curl/"
fi
for a in libuv libnghttp2 libssl libcrypto libz libpcre2-8 libcurl; do
    [ -f "$out/lib/$a.a" ] || { echo "build.sh: $a.a was not built for $triple" >&2; exit 1; }
done
case "$triple" in
*linux-gnu) # The libraries are built on a current glibc; none may call what the floor (glibc 2.28) lacks.
    sh "$repository/toolchain/check-glibc-archives.sh" "$out" "$arch" || exit 1 ;;
esac
rm -f "$out/step.log"
touch "$out/.complete"
emit
