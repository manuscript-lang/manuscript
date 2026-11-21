#!/bin/sh
# Installs the tools and libraries the C build needs: CMake, Ninja, ccache, pkg-config, and libuv, nghttp2, OpenSSL,
# PCRE2, zlib and libcurl (the system packages CMakeLists.txt finds with pkg-config).
# Usage: libs.sh install
# Which libraries a build uses is decided by cmake/MsLibs.cmake: system packages (default), the pinned versions
# in c-libs.lock built by build.sh (musl runtime archives), or the MSYS2 CLANG64 or CLANGARM64 packages (Windows,
# mingw-w64-clang-<arch>-*; `install` runs pacman at MS_MSYS2, default C:/msys64).
set -eu
command=${1:-}
case "$command" in
install)
    if command -v apt-get >/dev/null 2>&1; then
        sudo=; [ "$(id -u)" = 0 ] || sudo=sudo
        $sudo apt-get update
        $sudo apt-get install -y --no-install-recommends pkg-config cmake ninja-build ccache musl-tools libuv1-dev libnghttp2-dev libssl-dev libpcre2-dev zlib1g-dev libcurl4-openssl-dev
    elif command -v brew >/dev/null 2>&1; then
        brew install cmake ninja ccache pkgconf libuv libnghttp2 openssl@3 pcre2 zlib curl
    elif command -v apk >/dev/null 2>&1; then
        apk add cmake samurai ccache pkgconf libuv-dev nghttp2-dev nghttp2-static openssl-dev openssl-libs-static pcre2-dev zlib-dev zlib-static curl-dev curl-static
    elif command -v dnf >/dev/null 2>&1; then
        # The release container (manylinux_2_28, AlmaLinux 8): EPEL has ccache and ninja, PowerTools
        # the development files.
        sudo=; [ "$(id -u)" = 0 ] || sudo=sudo
        $sudo dnf install -y epel-release dnf-plugins-core
        $sudo dnf config-manager --set-enabled powertools
        $sudo dnf install -y pkgconf-pkg-config cmake ninja-build ccache libuv-devel libnghttp2-devel openssl-devel pcre2-devel zlib-devel libcurl-devel
    elif [ -x "${MS_MSYS2:-C:/msys64}/usr/bin/pacman.exe" ]; then
        case "${PROCESSOR_ARCHITECTURE:-}" in ARM64) env=clangarm64 ;; *) env=clang64 ;; esac
        pre=mingw-w64-clang-$(if [ "$env" = clangarm64 ]; then echo aarch64; else echo x86_64; fi)
        "${MS_MSYS2:-C:/msys64}/usr/bin/pacman.exe" -S --noconfirm --needed "$pre-libuv" "$pre-nghttp2" "$pre-openssl" "$pre-pcre2" "$pre-zlib" "$pre-curl"
    elif command -v vcpkg >/dev/null 2>&1; then
        vcpkg install pkgconf libuv nghttp2 openssl pcre2 zlib curl
    else
        echo "libs.sh: no supported package manager (apt, dnf, Homebrew, apk, vcpkg)" >&2; exit 1
    fi ;;
*) echo "usage: libs.sh install" >&2; exit 1 ;;
esac
