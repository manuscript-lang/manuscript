#!/bin/sh
# Builds each src/runtime/fuzz/*_fuzz.c harness with AddressSanitizer and UBSan (CMake, target/cmake/fuzz) and runs it
# over src/runtime/fuzz/corpus/<name>. Run from the repository root (`make c-fuzz`); nightly, not the PR gate.
#   FUZZ_RUNS   inputs per harness (default 20000; the nightly job uses millions)
#   FUZZ_SEED   starting seed (default 1; the nightly job passes the date so each night explores new inputs)
#   FUZZER=libfuzzer  coverage-guided: needs clang with the libFuzzer runtime; runs FUZZ_RUNS inputs per harness
# A failure leaves the input in target/c-fuzz/<name>/fuzz-crash.bin; add a fixed input to src/runtime/fuzz/corpus/<name>.
set -eu
out=target/c-fuzz
build=target/cmake/fuzz
runs=${FUZZ_RUNS:-20000}
seed=${FUZZ_SEED:-1}
cmake -S . -B "$build" -G Ninja -DMS_SANITIZE=ON -DMS_FUZZER="${FUZZER:-driver}" ${FUZZER:+-DCMAKE_C_COMPILER=clang} > /dev/null
cmake --build "$build" --target $(cd src/runtime/fuzz && ls ./*_fuzz.c | sed 's|^\./||; s|\.c$||')
export ASAN_OPTIONS=abort_on_error=1
# LeakSanitizer exists on Linux only.
[ "$(uname -s)" = Linux ] && ASAN_OPTIONS=$ASAN_OPTIONS:detect_leaks=1
export UBSAN_OPTIONS=print_stacktrace=1
for h in src/runtime/fuzz/*_fuzz.c; do
    name=$(basename "$h" _fuzz.c)
    bin=$PWD/$build/tests/${name}_fuzz
    mkdir -p "$out/$name"
    if [ "${FUZZER:-}" = libfuzzer ]; then
        (cd "$out/$name" && "$bin" -runs="$runs" -seed="$seed" "../../../src/runtime/fuzz/corpus/$name")
    else
        (cd "$out/$name" && "$bin" -n "$runs" -s "$seed" ../../../src/runtime/fuzz/corpus/"$name"/*)
    fi
done
