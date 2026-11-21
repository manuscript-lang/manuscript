#!/bin/sh
# Checks each C MIR pass (and each optimisation pass, frozen as opt-<pass>) against the frozen output of the Rust pass on the repository's .mir
# files (compiler/tests/mir/frozen/<pass>.out.gz, made by `MS_MIR_FREEZE=1 sh compiler/tests/mir-pass-diff.sh`).
# Needs no Rust build. Run from the repository root. After a deliberate change of a pass or of a
# fixture, refresh with `MS_MIR_REFRESH=1`, which rewrites the golden from the C pass and leaves the
# diff to review.
set -eu
export MS_STDLIB_DIR=${MS_STDLIB_DIR:-$PWD/stdlib}
out=target/c-compiler/mir-pass-frozen
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_mir_pass ms_mir_dump
bin=target/cmake/test/compiler/ms_mir_pass
dump=target/cmake/test/compiler/ms_mir_dump
# The elaborate fixtures made task programs, which the elaborate-cancel list names (see mir-pass-diff.sh).
mkdir -p target/c-compiler/mir-pass/task
for f in $(git ls-files 'compiler/tests/mir/elaborate/*.mir'); do
    { head -1 "$f"; echo 'extern @msrt_promise_start(int) -> int spawns_task'; tail -n +2 "$f"; } > "target/c-compiler/mir-pass/task/$(basename "$f")"
done
status=0
for list in compiler/tests/mir/frozen/*.list; do
    pass=$(basename "$list" .list)
    case $pass in
    # The optimisation passes: one pass (or the pipeline) on each verified module.
    opt-*) tr '\n' '\0' < "$list" | xargs -0 "$dump" opt "${pass#opt-}" > "$out/$pass.c" ;;
    *) tr '\n' '\0' < "$list" | xargs -0 "$bin" pass "$pass" > "$out/$pass.c" ;;
    esac
    # Goldens name the repository as <repo>, so they do not depend on the checkout's path.
    sed -i.bak "s|$PWD/|<repo>/|g" "$out/$pass.c" && rm -f "$out/$pass.c.bak"
    if [ -n "${MS_MIR_REFRESH:-}" ]; then
        gzip -9nc "$out/$pass.c" > "compiler/tests/mir/frozen/$pass.out.gz"
        echo "refreshed $pass"
        continue
    fi
    gzip -dc "compiler/tests/mir/frozen/$pass.out.gz" > "$out/$pass.golden"
    if cmp -s "$out/$pass.golden" "$out/$pass.c"; then
        echo "ok   mir pass $pass frozen ($(wc -l < "$list") files)"
    else
        echo "FAIL mir pass $pass frozen: first difference"
        diff "$out/$pass.golden" "$out/$pass.c" | head -20 || true
        status=1
    fi
done
exit $status
