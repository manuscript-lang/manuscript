#!/bin/sh
# Checks every C source of the runtime and the compiler against documentation/contributing/c-style.md:
# the warnings in toolchain/c-warnings.txt as errors, then clang-tidy with .clang-tidy.
# Usage (from the repository root, `make c-lint`): c-lint.sh [base]
#   With a git ref as base, clang-tidy runs only on C files that differ from it (all of them when a header
#   differs); the warnings always run on every file. Without it, both run on everything.
# toolchain/c-lint-pending.txt lists files written before the guide that do not pass yet. A listed file may
# fail; a listed file that passes must be removed from the list, so the list only shrinks.
set -eu
base=${1:-}
pending=toolchain/c-lint-pending.txt
tidy=$(command -v clang-tidy || command -v clang-tidy-18 || command -v clang-tidy-17 || true)
[ -n "$tidy" ] || { echo "c-lint: clang-tidy not found" >&2; exit 1; }
out=target/c-lint
rm -rf "$out"; mkdir -p "$out"
warnings=$(tr '\n' ' ' < toolchain/c-warnings.txt)
# -Wcomma is clang-only, so it is not in the shared list.
flags="-std=c11 $warnings -Wcomma -Iruntime/include -Icompiler/include -Iruntime/tests $(sh runtime/third_party/libs.sh cflags)"
files=$(find runtime/sys runtime/core runtime/io runtime/net runtime/std runtime/tests runtime/fuzz compiler/src compiler/tests compiler/tools -name '*.c' 2>/dev/null | sort)
changed=$files
if [ -n "$base" ]; then
    git rev-parse --verify --quiet "$base^{commit}" > /dev/null || { echo "c-lint: $base is not a commit" >&2; exit 1; }
    # A file written after the guide never joins the pending list.
    if git cat-file -e "$base:$pending" 2> /dev/null && git diff "$base" -- "$pending" | grep -q '^+[^+]'; then
        echo "c-lint: $pending gained a line; the list only shrinks" >&2; exit 1
    fi
fi
if [ -n "$base" ] && ! git diff --name-only "$base" -- runtime compiler .clang-tidy toolchain | grep -q -v '\.c$'; then
    changed=$(git diff --name-only --diff-filter=d "$base" -- runtime compiler | grep '\.c$' || true)
fi
check() { # file: writes "$out/<n>.log" when the file fails
    file=$1
    log=$out/$(echo "$file" | tr / _).log
    # shellcheck disable=SC2086
    clang -fsyntax-only $flags -I"$(dirname "$file")" "$file" > "$log" 2>&1 || return 0
    # clang-tidy reads production sources only: tests and fuzz harnesses get the warnings.
    case "$file" in runtime/tests/*|runtime/fuzz/*|compiler/tests/*|compiler/tools/*) rm -f "$log"; return 0 ;; esac
    case " $(echo $changed) " in *" $file "*) ;; *) rm -f "$log"; return 0 ;; esac
    # shellcheck disable=SC2086
    "$tidy" --quiet "$file" -- $flags -I"$(dirname "$file")" > "$log" 2>&1 || return 0
    rm -f "$log"
}
jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
running=0
for file in $files; do
    check "$file" &
    running=$((running + 1))
    if [ "$running" -ge "$jobs" ]; then wait; running=0; fi
done
wait
status=0
for file in $files; do
    log=$out/$(echo "$file" | tr / _).log
    listed=no
    grep -Fqx "$file" "$pending" && listed=yes
    if [ -f "$log" ] && [ "$listed" = no ]; then
        # With a base, only files this change touches fail it: a file another change merged just before the
        # gate saw it is reported here and fails the nightly run, not every pull request after it.
        case " $(echo $changed) " in
            *" $file "*) cat "$log"; echo "c-lint: $file fails (documentation/contributing/c-style.md)" >&2; status=1 ;;
            *) echo "c-lint: $file fails but this change does not touch it" >&2 ;;
        esac
    elif [ ! -f "$log" ] && [ "$listed" = yes ]; then
        case " $(echo $changed) " in *" $file "*) echo "c-lint: $file passes now; remove it from $pending" >&2; status=1 ;; esac
    fi
done
while read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || { echo "c-lint: $pending names $file, which does not exist" >&2; status=1; }
done < "$pending"
[ "$status" = 0 ] && echo "c-lint ok: $(echo "$files" | wc -l | tr -d ' ') files, $(wc -l < "$pending" | tr -d ' ') pending"
exit "$status"
