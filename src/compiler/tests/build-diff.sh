#!/bin/sh
# Builds every `phase=run` conformance program with the Rust back end and with the C back end
# (`MS_BACKEND=c`), runs both executables and compares stdout and exit status. Prints one line per
# program and a census of why the C build fails (the emitter's reason lines), which is the list of
# gaps to route to the emitter, lowering and pass owners.
# Run from the repository root with a built `ms` (`make build`): `sh src/compiler/tests/build-diff.sh [LIMIT]`.
# MS_BUILD_DIFF_FLAGS=--static links musl when the system libraries need a newer glibc than the runtime floor.
# MS_BUILD_DIFF_PROFILE=Debug (default) or Release, as `ms build --build-type`.
set -u
limit=${1:-0}
profile=${MS_BUILD_DIFF_PROFILE:-Debug}
flags=${MS_BUILD_DIFF_FLAGS:-}
ms=${MS:-target/release/ms}
exe=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe=.exe ;; esac
out=target/c-compiler/build-diff
rm -rf "$out"
mkdir -p "$out"
grep -rl "^// conform: .*phase=run" tests/conformance/fixtures --include=*.ms | sort > "$out/files.txt"
[ "$limit" -gt 0 ] && head -n "$limit" "$out/files.txt" > "$out/files.cut" && mv "$out/files.cut" "$out/files.txt"
pass=0 same=0 diff=0 cfail=0 rfail=0
while read -r src; do
    id=$(echo "$src" | tr '/' '_')
    "$ms" build $flags --build-type $profile "$src" -o "$out/$id.rust$exe" > "$out/$id.rust.log" 2>&1 || { rfail=$((rfail + 1)); continue; }
    if ! MS_BACKEND=c "$ms" build $flags --build-type $profile "$src" -o "$out/$id.c$exe" > "$out/$id.c.log" 2>&1; then
        cfail=$((cfail + 1))
        echo "cfail $src"
        continue
    fi
    "$out/$id.rust$exe" > "$out/$id.rust.out" 2>&1 < /dev/null; r=$?
    "$out/$id.c$exe" > "$out/$id.c.out" 2>&1 < /dev/null; c=$?
    if [ "$r" = "$c" ] && cmp -s "$out/$id.rust.out" "$out/$id.c.out"; then
        same=$((same + 1)); echo "same  $src"
    else
        diff=$((diff + 1)); echo "DIFF  $src (rust $r, c $c)"
    fi
done < "$out/files.txt"
echo "built by both and same: $same; differ: $diff; C build failed: $cfail; Rust build failed: $rfail"
echo "--- why the C build fails (count, reason) ---"
# One reason per emitter line ("fn: reason"), one per failed pass, one per parse error, so a program
# with several gaps counts under each.
for log in "$out"/*.c.log; do
    sed -E 's#/tmp/ms-cbackend-[0-9]+/##; s/^native code generation failed[^:]*: (ms_mir_build|clang|cc) failed: //' "$log" |
        awk '/^the C back end cannot write:/ {w=1; next} w && NF {sub(/^[^:]*: /, ""); print "emitter: " $0; next} /^Built / {exit} /does not verify after/ {print "verify: " $0; v=1; next} v && NF {sub(/^[^:]*: /, ""); sub(/%[0-9]+/, "%N"); print "  " $0; v=0; next} !w && NF && !v {print "other: " $0; exit}'
done | sort | uniq -c | sort -rn | head -n 40
