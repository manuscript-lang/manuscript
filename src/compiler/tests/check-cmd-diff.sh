#!/bin/sh
# Compares `ms check FILE [--json [--with-text [--each]]]` through the C driver (check=c) with the Rust `ms` over the conformance fixtures:
# output and exit status must be identical. The census says how many files the C command served itself and how many
# it handed to Rust (a handover is correct by construction: the Rust command then runs). Usage, from the repository
# root: sh src/compiler/tests/check-cmd-diff.sh [LIMIT]
#   MS_RUST_CLI  the Rust ms (default target/release/ms)   MS_C_MS  the C ms (default target/cmake/test/compiler/ms)
#   MS_FILES  a file with the paths to compare instead of the corpus
#   MS_STDLIB_DIR  where the C command reads the standard library until it is embedded   JOBS  parallel runs (8)
set -eu
if [ "${1:-}" = --one ]; then
    f=$2
    id=$(printf '%s' "$f" | cksum | cut -d' ' -f1)
    for mode in text json with-text each; do
        flag=
        [ "$mode" = json ] && flag=--json
        [ "$mode" = with-text ] && flag="--json --with-text"
        [ "$mode" = each ] && flag="--json --with-text --each"
        base="$MS_OUT/$id.$mode"
        { "$MS_RUST_CLI" check "$f" $flag 2>&1; echo "exit $?"; } > "$base.rust" || true
        { MS_STAGES=check=c MS_DRIVER_TRACE=1 "$MS_C_MS" check "$f" $flag 2>&1; echo "exit $?"; } > "$base.ctrace" || true
        grep -v '^ms driver: ' "$base.ctrace" > "$base.c" || true
        if grep -q 'handover' "$base.ctrace"; then served=handover; else served=c; fi
        if cmp -s "$base.rust" "$base.c"; then same=same; else same=DIFF; fi
        why=$(sed -n 's/^ms driver: check handover: //p' "$base.ctrace")
        echo "$mode $served $same $f${why:+ ($why)}" >> "$MS_OUT/results"
    done
    exit 0
fi
export MS_RUST_CLI=${MS_RUST_CLI:-target/release/ms}
export MS_C_MS=${MS_C_MS:-target/cmake/test/compiler/ms}
export MS_RUST_CLI MS_C_MS
MS_OUT=target/c-compiler/check-cmd
export MS_OUT
rm -rf "$MS_OUT"
mkdir -p "$MS_OUT"
: > "$MS_OUT/results"
if [ -n "${MS_FILES:-}" ]; then
    cp "$MS_FILES" "$MS_OUT/files"
else
    find tests/conformance/fixtures -name '*.ms' | sort | head -n "${1:-100000}" > "$MS_OUT/files"
fi
xargs -P "${JOBS:-8}" -n 1 sh "$0" --one < "$MS_OUT/files"
sort "$MS_OUT/results" -o "$MS_OUT/results"
echo "files: $(wc -l < "$MS_OUT/files")"
awk '{ n[$1" "$2" "$3]++ } END { for (k in n) print n[k], k }' "$MS_OUT/results" | sort -k2
echo "handover reasons (text):"
sed -n 's/^text handover [a-zA-Z]* [^ ]* (\(.*\))$/\1/p' "$MS_OUT/results" | sort | uniq -c | sort -rn
if grep -q ' DIFF ' "$MS_OUT/results"; then
    grep ' DIFF ' "$MS_OUT/results" | head -n 20
    exit 1
fi
