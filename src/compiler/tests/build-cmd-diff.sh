#!/bin/sh
# `ms build` through the Manuscript front and the C pipeline (ms_tool_build) against the Rust command: for each
# `phase=run` conformance program the front builds it, the trace says whether C built it or handed it to Rust, and
# every program C built is run next to the Rust-built one (stdout, stderr and exit status must match).
# Prints a census of why C handed programs over. A manual check, not part of pull request CI.
# Run from the repository root: `sh src/compiler/tests/build-cmd-diff.sh [LIMIT]`.
#   MS_FRONT     the Manuscript front built as `ms` with its `ms-rust` beside it (default target/front/ms)
#   MS_RUST_CLI  the Rust ms (default target/release/ms)
#   MS_LLVM_TOOLS, MS_LLD, MS_LINKER_FILES, MS_RT_LIB  as src/ms/build_run.ms reads them
#   JOBS         parallel builds (default 8)
set -u
limit=${1:-0}
out=target/c-compiler/build-cmd
mkdir -p "$out"
rm -rf "$out/results"
mkdir -p "$out/results"
export MS_FRONT=${MS_FRONT:-target/front/ms} MS_RUST_CLI=${MS_RUST_CLI:-target/release/ms}
export out
grep -rl "^// conform: .*phase=run" tests/conformance/fixtures --include=*.ms | sort > "$out/files.txt"
[ "$limit" -gt 0 ] && head -n "$limit" "$out/files.txt" > "$out/files.cut" && mv "$out/files.cut" "$out/files.txt"

one() {
    src=$1
    id=$(echo "$src" | tr '/' '_')
    base="$out/results/$id"
    MS_DRIVER_TRACE=1 "$MS_FRONT" build --build-type Debug "$src" -o "$base.front" > "$base.front.log" 2>&1 || { echo "frontfail $src" > "$base.status"; return; }
    if grep -q "handed to Rust:" "$base.front.log"; then
        echo "handover $(sed -n 's/^ms build: handed to Rust: //p' "$base.front.log" | head -n 1)" > "$base.status"
        return
    fi
    "$MS_RUST_CLI" build --build-type Debug "$src" -o "$base.rust" > "$base.rust.log" 2>&1 || { echo "rustfail $src" > "$base.status"; return; }
    "$base.front" > "$base.front.out" 2>&1 < /dev/null; f=$?
    "$base.rust" > "$base.rust.out" 2>&1 < /dev/null; r=$?
    if [ "$f" = "$r" ] && cmp -s "$base.front.out" "$base.rust.out"; then echo "same $src" > "$base.status"; else echo "DIFF $src (c $f, rust $r)" > "$base.status"; fi
    rm -f "$base.front" "$base.rust"
}
export -f one 2>/dev/null || true
if [ -n "${BASH_VERSION:-}" ]; then
    xargs -P "${JOBS:-8}" -I{} bash -c 'one "$1"' _ {} < "$out/files.txt"
else
    while read -r src; do one "$src"; done < "$out/files.txt"
fi
cat "$out"/results/*.status | awk '{ kind = $1; if (kind == "handover") { $1 = ""; reasons[$0]++ } count[kind]++ }
    END { for (k in count) printf "%d %s\n", count[k], k; print "--- why C handed over (count, reason) ---"; for (r in reasons) printf "%d%s\n", reasons[r], r }' | sort -rn
grep -h "^DIFF" "$out"/results/*.status
