#!/bin/sh
# Builds the pinned static LLVM + lld bundle for the host (`sh scripts/build-llvm-bundle.sh <os> <arch> [lld]`) and
# writes dist/llvm/lld-<version>-<os>-<arch>.tar.gz (bin/lld only, what `ms` embeds to link) and
# dist/llvm/llvm-<version>-<os>-<arch>.tar.gz (static libraries and headers for in-process codegen), each with a
# .sha256 beside it. The version is the single pin in scripts/llvm-version.
# Zig-style: one statically linked tree per platform, no shared libLLVM, built once in CI and consumed by checksum.
# With `lld` as the third argument only lld is built, into target/llvm-bundle/install/bin (what `ms` embeds; CI
# caches that tree and `ms-clif/build.rs` finds it there).
set -eu
os=$1
arch=$2
what=${3:-all}
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$repository/scripts/llvm-version")
work=${LLVM_WORK:-$repository/target/llvm-bundle}
out=$repository/dist/llvm
mkdir -p "$work" "$out"
cd "$work"

# llvm's CMake expects the cmake and third-party trees next to the llvm source directory.
if [ ! -d llvm ]; then
    base=https://github.com/llvm/llvm-project/releases/download/llvmorg-$version
    for part in llvm lld cmake third-party; do
        curl --fail --location --retry 3 -sS -o "$part.tar.xz" "$base/$part-$version.src.tar.xz"
        mkdir -p "$part"
        tar -xf "$part.tar.xz" -C "$part" --strip-components=1
        rm "$part.tar.xz"
    done
fi

targets="X86;AArch64"
[ "$what" = lld ] && targets=X86 # lld links without code generation; LTO is not used
set -- -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS=lld -DLLVM_EXTERNAL_LLD_SOURCE_DIR="$work/lld" \
    "-DLLVM_TARGETS_TO_BUILD=$targets" \
    -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_ENABLE_PLUGINS=OFF -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_DOCS=OFF -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_UTILS=OFF -DLLVM_ENABLE_BINDINGS=OFF
case "$os" in
    darwin)
        osx_arch=x86_64
        [ "$arch" = arm64 ] && osx_arch=arm64
        set -- "$@" -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 "-DCMAKE_OSX_ARCHITECTURES=$osx_arch" ;;
    windows) set -- "$@" -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded ;;
    *) set -- "$@" "-DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ -static-libgcc" ;;
esac
cmake "$@"
if [ "$what" = lld ]; then
    cmake --build build --target lld
    exe=
    [ "$os" = windows ] && exe=.exe
    mkdir -p "$work/install/bin"
    cp "build/bin/lld$exe" "$work/install/bin/"
    exit 0
fi
cmake --build build
cmake --install build --prefix "$work/install"

exe=
[ "$os" = windows ] && exe=.exe
# The install tree carries no tools (LLVM_BUILD_TOOLS=OFF); lld is the one executable ms embeds.
mkdir -p "$work/install/bin"
cp "build/bin/lld$exe" "$work/install/bin/"

lld_asset=lld-$version-$os-$arch.tar.gz
dev_asset=llvm-$version-$os-$arch.tar.gz
tar -czf "$out/$lld_asset" -C "$work/install" "bin/lld$exe"
tar -czf "$out/$dev_asset" -C "$work/install" include lib
(cd "$out" && for f in "$lld_asset" "$dev_asset"; do
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" > "$f.sha256"; else shasum -a 256 "$f" > "$f.sha256"; fi
done)
ls -l "$out"
