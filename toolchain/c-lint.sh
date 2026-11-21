#!/bin/sh
# Checks every C source of the runtime and the compiler against documentation/contributing/c-style.md:
# the warnings in toolchain/c-warnings.txt as errors, then clang-tidy with .clang-tidy.
# Usage (from the repository root, `make c-lint`): c-lint.sh [base]
#   With a git ref as base, clang-tidy runs only on C files that differ from it (all of them when a header
#   differs); the warnings always run on every file. Without it, both run on everything.
# toolchain/c-duplicates.py also fails a static function body copied into a second file.
# toolchain/c-lint-pending.txt lists files written before the guide that do not pass yet. A listed file may
# fail; a listed file that passes must be removed from the list, so the list only shrinks.
set -eu
base=${1:-}
pending=toolchain/c-lint-pending.txt
tidy=$(command -v clang-tidy || command -v clang-tidy-18 || command -v clang-tidy-17 || true)
[ -n "$tidy" ] || { echo "c-lint: clang-tidy not found" >&2; exit 1; }
out=target/c-lint
rm -rf "$out"; mkdir -p "$out"
# The flags come from the CMake project (cmake/MsLint.cmake, `make c-lint`): warnings, include paths and library headers.
[ -f "${MS_LINT_FLAGS:-}" ] || { echo "c-lint: run it through CMake (make c-lint or cmake --build <dir> --target c-lint)" >&2; exit 1; }
flags=$(cat "$MS_LINT_FLAGS")
# A source under runtime/sys/<os>/ or runtime/io/<os>/ compiles only on that system, so the others are left to that system's build.
case "$(uname -s)" in Darwin) other='/(sys|io)/(linux|glibc|windows)/' ;; *) other='/(sys|io)/(darwin|windows)/' ;; esac
# std_embed.c includes a file the build generates, which a lone compile does not see.
files=$(find runtime/sys runtime/core runtime/io runtime/net runtime/std runtime/tests runtime/fuzz compiler/src compiler/tests compiler/tools -name '*.c' 2>/dev/null | grep -Ev "$other" | grep -v "^compiler/src/std_embed.c$" | sort)
# compiler/src is one translation unit, libms.c, that includes each source once: a file included twice redeclares its
# types, and one left out is not built. driver.c, tool.c, tool_check.c, tool_build.c, tool_search.c, tool_facts.c and std_embed.c are the entry points, outside it.
included=$(sed -n 's/^#include "\(.*\.c\)"$/\1/p' compiler/src/libms.c)
twice=$(echo "$included" | sort | uniq -d)
[ -z "$twice" ] || { echo "c-lint: libms.c includes twice: $twice" >&2; exit 1; }
for f in $(cd compiler/src && find . -name '*.c' | sed 's|^\./||' | sort); do
    case "$f" in driver.c|libms.c|std_embed.c|tool.c|tool_check.c|tool_build.c|tool_search.c|tool_facts.c) continue ;; esac
    echo "$included" | grep -qx "$f" || { echo "c-lint: compiler/src/$f is not included by libms.c" >&2; exit 1; }
done
# No static function body is copied into a second file (the list of known copies only shrinks).
python3 toolchain/c-duplicates.py || { echo "c-lint: duplicated functions (toolchain/c-duplicates.py)" >&2; exit 1; }
changed=$files
if [ -n "$base" ]; then
    git rev-parse --verify --quiet "$base^{commit}" > /dev/null || { echo "c-lint: $base is not a commit" >&2; exit 1; }
    # A file written after the guide never joins the pending list. Only this change's own additions count, so the
    # list is compared with the commit the change started from, not with a main that has shrunk it since.
    start=$(git merge-base "$base" HEAD 2> /dev/null || true)
    # A pull request checked out shallow, as the merge of the change into its base: the first parent is that base.
    [ -n "$start" ] || ! git rev-parse --verify --quiet 'HEAD^2^{commit}' > /dev/null || start=$(git rev-parse 'HEAD^1')
    [ -n "$start" ] || start=$base
    if git cat-file -e "$start:$pending" 2> /dev/null && git diff "$start" -- "$pending" | grep -q '^+[^+]'; then
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
# Library calls that take no size and have a bounded replacement (documentation/contributing/c-style.md): sprintf and
# strcat and strcpy overrun, strtok keeps hidden state, gets cannot be used safely, and Apple's libc deprecates sprintf, so a
# macOS build fails on it. Use snprintf, memcpy with a checked size, or ms_rt/safe.h (tests: tests/support/append.h).
banned='(^|[^[:alnum:]_.>])(sprintf|vsprintf|strcpy|stpcpy|strcat|strtok|gets|tmpnam|mktemp)[[:space:]]*\('
# Every system's sources count, including the ones this system does not compile.
# shellcheck disable=SC2086
if hits=$(grep -nHE "$banned" $(find runtime/sys runtime/core runtime/io runtime/net runtime/std runtime/tests runtime/fuzz compiler/src compiler/tests compiler/tools -name '*.c' 2> /dev/null) $(find runtime/include runtime/core runtime/net runtime/std runtime/sys runtime/io runtime/tests compiler/include compiler/src -name '*.h' 2> /dev/null) | grep -vE ':[0-9]+:[[:space:]]*(/?\*|//)'); then
    echo "$hits" >&2
    echo "c-lint: sprintf, strcpy, strcat, strtok and the like are banned; use snprintf or a bounded copy" >&2
    status=1
fi
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
