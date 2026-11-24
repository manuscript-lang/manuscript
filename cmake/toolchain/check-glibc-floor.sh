#!/bin/sh
# (CI: a change here starts the LLVM jobs of a pull request: one corpus job on amd64, the gates on arm64.)
# Fails when an ELF executable needs glibc newer than 2.28, or a shared library other than glibc's own
# and libgcc_s (every glibc distribution ships it; Rust's unwinder links it, and AlmaLinux 8 has GCC 8's):
# `sh cmake/toolchain/check-glibc-floor.sh <file>...`. It reads the binary's version requirements, the ones the
# loader enforces at start, so weak references count. MS_GLIBC_FLOOR overrides the floor, as `major.minor`;
# MS_GCC_FLOOR the newest libgcc_s version allowed (default 8.0, AlmaLinux 8's).
set -eu
floor=${MS_GLIBC_FLOOR:-2.28}
gcc_floor=${MS_GCC_FLOOR:-8.0}
[ $# -gt 0 ] || { echo "usage: $0 <elf file>..." >&2; exit 2; }
status=0
for file in "$@"; do
    info=$(objdump -p "$file")
    needed=$(printf '%s\n' "$info" | awk '$1 == "NEEDED" { print $2 }')
    for lib in $needed; do
        case "$lib" in
            libc.so.6 | libgcc_s.so.1 | libm.so.6 | libpthread.so.0 | libdl.so.2 | librt.so.1 | ld-linux-*.so.* | linux-vdso.so.1) ;;
            *) echo "$file: needs $lib, which is not part of glibc" >&2; status=1 ;;
        esac
    done
    # Lines of the "Version References" section name one version each, e.g. `0x09691a75 0x00 05 GLIBC_2.2.5`.
    bad=$(printf '%s\n' "$info" | awk -v glibc="$floor" -v gcc="$gcc_floor" '
        # Whether version `have` ("2.34") is newer than `limit` ("2.28"), comparing major then minor.
        function newer(have, limit,    h, l) {
            split(have, h, "."); split(limit, l, ".")
            return h[1] + 0 > l[1] + 0 || (h[1] + 0 == l[1] + 0 && h[2] + 0 > l[2] + 0)
        }
        $NF ~ /^(GLIBC|GLIBCXX|CXXABI|GCC)_[0-9.]+$/ && NF == 4 {
            name = $NF
            if (name ~ /^GLIBC_/) { sub(/^GLIBC_/, "", name); if (newer(name, glibc)) print $NF }
            else if (name ~ /^GCC_/) { sub(/^GCC_/, "", name); if (newer(name, gcc)) print $NF }
            else print $NF
        }' | sort -u)
    if [ -n "$bad" ]; then
        echo "$file: needs versions above glibc $floor or libgcc_s $gcc_floor:" >&2
        printf '  %s\n' $bad >&2
        status=1
    fi
done
[ "$status" -eq 0 ] && echo "glibc floor $floor holds for $*"
exit "$status"
