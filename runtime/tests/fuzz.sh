#!/bin/sh
# Builds each runtime/fuzz/*_fuzz.c harness with AddressSanitizer and UBSan and runs it over runtime/fuzz/corpus/<name>.
# Run from the repository root (`make c-fuzz`); nightly, not the PR gate.
#   FUZZ_RUNS   inputs per harness (default 20000; the nightly job uses millions)
#   FUZZ_SEED   starting seed (default 1; the nightly job passes the date so each night explores new inputs)
#   FUZZER=libfuzzer  coverage-guided: needs clang with the libFuzzer runtime; runs FUZZ_RUNS inputs per harness
# A failure leaves the input in target/c-fuzz/<name>/fuzz-crash.bin; add a fixed input to runtime/fuzz/corpus/<name>.
set -eu
out=target/c-fuzz
runs=${FUZZ_RUNS:-20000}
seed=${FUZZ_SEED:-1}
cc=${CC:-cc}
llhttp=runtime/third_party/llhttp
mkdir -p "$out"
export ASAN_OPTIONS=abort_on_error=1
# LeakSanitizer exists on Linux only.
[ "$(uname -s)" = Linux ] && ASAN_OPTIONS=$ASAN_OPTIONS:detect_leaks=1
export UBSAN_OPTIONS=print_stacktrace=1
san="-fsanitize=address,undefined -fno-sanitize-recover=undefined"
for h in runtime/fuzz/*_fuzz.c; do
    name=$(basename "$h" _fuzz.c)
    case $name in
        http1) deps="runtime/net/http1.c $llhttp/src/api.c $llhttp/src/http.c $llhttp/src/llhttp.c -I$llhttp/include" ;;
        num) deps="runtime/core/num.c -lm" ;;
        *) echo "fuzz.sh: no build line for $name" >&2; exit 1 ;;
    esac
    mkdir -p "$out/$name"
    if [ "${FUZZER:-}" = libfuzzer ]; then
        # shellcheck disable=SC2086
        "$cc" -std=c11 -O1 -g -fsanitize=fuzzer,address,undefined -Iruntime/include "$h" $deps -o "$out/$name/fuzz"
        (cd "$out/$name" && ./fuzz -runs="$runs" -seed="$seed" "../../../runtime/fuzz/corpus/$name")
    else
        # shellcheck disable=SC2086
        "$cc" -std=c11 -O1 -g $san -Wall -Iruntime/include "$h" runtime/fuzz/driver.c $deps -o "$out/$name/fuzz"
        (cd "$out/$name" && ./fuzz -n "$runs" -s "$seed" ../../../runtime/fuzz/corpus/"$name"/*)
    fi
done
