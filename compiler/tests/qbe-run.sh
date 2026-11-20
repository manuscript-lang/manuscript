#!/bin/sh
# Compiles each compiler/tests/qbe/*.mir through the C MIR reader, the C QBE emitter, the vendored QBE and
# the system C compiler, runs it, and compares its exit status with the .exit file beside it.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/qbe
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_mir_qbe qbe
bin=target/cmake/test/compiler
q=runtime/third_party/qbe
case "$(uname -s)-$(uname -m)" in
Darwin-arm64) target=arm64_apple ;;
Darwin-*) target=amd64_apple ;;
*-aarch64 | *-arm64) target=arm64 ;;
*) target=amd64_sysv ;;
esac
cat > "$out/rt.c" <<'C'
#include <stdlib.h>
extern long msmain(void);
void msrt_fault_int_overflow(void) { exit(134); }
long msrt_test_add(long a, long b) { return a + b; }
int main(void) { return (int)msmain(); }
C
status=0
for mir in compiler/tests/qbe/*.mir; do
    name=${mir%.mir}
    "$bin/ms_mir_qbe" "$mir" > "$out/$(basename "$name").ssa"
    "$bin/qbe" -t "$target" "$out/$(basename "$name").ssa" > "$out/$(basename "$name").s"
    cc "$out/$(basename "$name").s" "$out/rt.c" -o "$out/$(basename "$name")"
    got=0
    "$out/$(basename "$name")" || got=$?
    want=$(cat "$name.exit")
    if [ "$got" = "$want" ]; then echo "ok   qbe $(basename "$name")"; else echo "FAIL qbe $(basename "$name"): exit $got, want $want"; status=1; fi
done
exit $status
