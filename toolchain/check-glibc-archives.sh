#!/bin/sh
# Fails when the static C libraries built for a glibc target call anything glibc 2.28 does not export (the floor programs
# link against): `sh toolchain/check-glibc-archives.sh <folder with lib/*.a> <x86_64|aarch64>`. A symbol is fine when it is
# in toolchain/glibc/<arch>.symbols, defined by the libraries themselves, defined by src/runtime/sys/glibc/compat.c, or in the
# `stat` family that crates/ms-native/src/entry.rs defines, or `__clear_cache` and `__popcountdi2`, which src/runtime/sys/posix/clear_cache.c and popcount.c define (PCRE2's JIT on arm64). Newer glibc headers redirect `sscanf` and `strtol` to
# `__isoc23_*` names when _GNU_SOURCE is on, and the libraries are built on a current distribution, so this runs after every build.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
folder=${1:?usage: check-glibc-archives.sh <folder> <arch>}
arch=${2:?usage: check-glibc-archives.sh <folder> <arch>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc=${CC:-cc}
"$cc" -std=c11 -c -w -o "$work/compat.o" "$repository/src/runtime/sys/glibc/compat.c"
nm -g --defined-only "$work/compat.o" | awk 'NF == 3 {print $3}' > "$work/compat"
printf '%s\n' stat fstat lstat stat64 fstat64 lstat64 fstatat fstatat64 mknod mknodat __clear_cache __popcountdi2 > "$work/stat"
awk '$1 !~ /^#/ {print $3}' "$repository/toolchain/glibc/$arch.symbols" > "$work/abi"
# nm prints `archive:member:` header lines and the symbols after them; a defined symbol has a type letter other than U.
nm -g --defined-only "$folder"/lib/*.a 2>/dev/null | awk 'NF == 3 {print $3}' > "$work/defined"
nm -g --undefined-only "$folder"/lib/*.a 2>/dev/null | awk 'NF == 2 && $1 == "U" {print $2}' > "$work/undefined"
sort -u "$work/abi" "$work/compat" "$work/stat" "$work/defined" > "$work/allowed"
bad=$(sort -u "$work/undefined" | comm -23 - "$work/allowed" | grep -v '^_\?_\?GLOBAL_OFFSET_TABLE_$' || true)
if [ -n "$bad" ]; then
    echo "check-glibc-archives: $folder calls symbols newer than glibc 2.28 (add them to src/runtime/sys/glibc/compat.c or build without them):" >&2
    printf '  %s\n' $bad >&2
    exit 1
fi
