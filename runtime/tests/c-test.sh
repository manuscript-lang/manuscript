#!/bin/sh
# Builds and runs every runtime/tests/core_*.c unit test (linked with all of runtime/core), the HTTP/1 test, and every
# runtime/tests/std_*.c unit test (linked with all of runtime/std and the system PCRE2) with AddressSanitizer and UBSan.
# The core tests also link runtime/sys and runtime/tests/support; the allocator's live-block counts are on (MS_ALLOC_STATS).
# Run from the repository root (`make c-test`); nightly, not the PR gate.
set -eu
out=target/c-test
mkdir -p "$out"
flags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Iruntime/include"
for t in runtime/tests/core_*.c; do
    name=$(basename "$t" .c)
    cc $flags -std=gnu11 -DMS_ALLOC_STATS -Iruntime/core "$t" runtime/core/*.c runtime/sys/*.c runtime/tests/support/*.c -lm -lpthread -o "$out/$name"
    "$out/$name"
done
for t in runtime/tests/std_*.c; do
    name=$(basename "$t" .c)
    # shellcheck disable=SC2046
    cc $flags $(pkg-config --cflags libpcre2-8 libcrypto) "$t" runtime/std/*.c $(sh runtime/third_party/libs.sh libs pcre2 crypto) -lm -o "$out/$name"
    "$out/$name"
done
# The HTTP/1 tests link the vendored llhttp sources (the same ones the pinned build compiles).
llhttp=runtime/third_party/llhttp
cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -w -I"$llhttp/include" -Iruntime/include \
    runtime/tests/http1_test.c runtime/net/http1.c "$llhttp"/src/*.c -o "$out/http1_test"
"$out/http1_test"
