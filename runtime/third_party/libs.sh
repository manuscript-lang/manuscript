#!/bin/sh
# Compiler and linker flags for the C libraries, so no other script names a library path.
# Usage: libs.sh cflags | libs <name>... | archives <name>... | dir | install
#   names: uv llhttp nghttp2 ssl crypto pcre2 z
# MS_C_LIBS=system (default): libuv, nghttp2, OpenSSL, PCRE2 and zlib come from the system packages through
# pkg-config; `libs.sh install` installs them. MS_C_LIBS=pinned: the versions in c-libs.lock, built by build.sh
# (release archives use this). llhttp and QBE are vendored and built by build.sh in both modes; `dir` prints
# that folder (bin/qbe, lib/libllhttp.a). `archives` prints the static archive of each library, which `cargo xtask runtime`
# folds into the runtime archives. MS_C_TRIPLE names the target of a cross build (pinned mode builds for it).
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
mode=${MS_C_LIBS:-system}
command=${1:-}
[ $# -gt 0 ] && shift
package() { # library name -> pkg-config package
    case "$1" in
        uv) echo libuv ;; nghttp2) echo libnghttp2 ;; ssl) echo libssl ;; crypto) echo libcrypto ;;
        pcre2) echo libpcre2-8 ;; z) echo zlib ;; *) echo "libs.sh: unknown library $1" >&2; exit 1 ;;
    esac
}
triple=${MS_C_TRIPLE:-}
build() { MS_C_LIBS=$mode sh "$here/build.sh" ${triple:+"$triple"}; }
archive() { case "$1" in pcre2) echo libpcre2-8.a ;; *) echo "lib$1.a" ;; esac; }
config() { # pkg-config with a remedy when a package is missing
    pkg-config "$@" || { echo "libs.sh: system library missing; run: sh runtime/third_party/libs.sh install (or set MS_C_LIBS=pinned)" >&2; exit 1; }
}
case "$command" in
install)
    if command -v apt-get >/dev/null 2>&1; then
        sudo=; [ "$(id -u)" = 0 ] || sudo=sudo
        $sudo apt-get update
        $sudo apt-get install -y --no-install-recommends pkg-config libuv1-dev libnghttp2-dev libssl-dev libpcre2-dev zlib1g-dev
    elif command -v brew >/dev/null 2>&1; then
        brew install pkgconf libuv libnghttp2 openssl@3 pcre2 zlib
    elif command -v apk >/dev/null 2>&1; then
        apk add pkgconf libuv-dev libuv-static nghttp2-dev nghttp2-static openssl-dev openssl-libs-static pcre2-dev pcre2-static zlib-dev zlib-static
    elif command -v vcpkg >/dev/null 2>&1; then
        vcpkg install pkgconf libuv nghttp2 openssl pcre2 zlib
    else
        echo "libs.sh: no supported package manager (apt, Homebrew, apk, vcpkg); set MS_C_LIBS=pinned" >&2; exit 1
    fi ;;
dir) build ;;
cflags)
    out=$(build)
    if [ "$mode" = system ]; then echo "-I$out/include $(config --cflags libuv libnghttp2 libssl libcrypto libpcre2-8 zlib)"; else echo "-I$out/include"; fi ;;
libs)
    out=$(build)
    flags=
    for name in "$@"; do
        if [ "$name" = llhttp ]; then flags="$flags $out/lib/libllhttp.a"
        elif [ "$mode" = pinned ]; then package "$name" >/dev/null; flags="$flags $out/lib/$(archive "$name")"
        else flags="$flags $(config --libs "$(package "$name")")"; fi
    done
    case "$(uname -s)" in Linux) flags="$flags -lpthread -ldl -lm" ;; esac
    echo "${flags# }" ;;
archives)
    out=$(build)
    for name in "$@"; do
        if [ "$name" = llhttp ]; then echo "$out/lib/libllhttp.a"
        elif [ "$mode" = pinned ]; then package "$name" >/dev/null; echo "$out/lib/$(archive "$name")"
        else
            file="$(config --variable=libdir "$(package "$name")")/$(archive "$name")"
            [ -f "$file" ] || { echo "libs.sh: $file is missing; install the static library package (Alpine: *-static)" >&2; exit 1; }
            echo "$file"
        fi
    done ;;
*) echo "usage: libs.sh cflags | libs <name>... | archives <name>... | dir | install" >&2; exit 1 ;;
esac
