#!/bin/sh
# Builds and runs every runtime/tests/core_*.c unit test and the HTTP/1 test with AddressSanitizer and UBSan.
# Each test links all of runtime/core and runtime/sys; the allocator's live-block counts are on (MS_ALLOC_STATS).
# Run from the repository root (`make c-test`); nightly, not the PR gate.
set -eu
out=target/c-test
mkdir -p "$out"
for t in runtime/tests/core_*.c; do
    name=$(basename "$t" .c)
    cc -std=gnu11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined \
        -Wall -Wextra -Werror -DMS_ALLOC_STATS -Iruntime/include -Iruntime/core "$t" runtime/core/*.c runtime/sys/*.c runtime/tests/support/*.c \
        -lm -lpthread -o "$out/$name"
    "$out/$name"
done
# The HTTP/1 tests link the vendored llhttp sources (the same ones the pinned build compiles).
llhttp=runtime/third_party/llhttp
cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -w -I"$llhttp/include" -Iruntime/include \
    runtime/tests/http1_test.c runtime/net/http1.c "$llhttp"/src/*.c -o "$out/http1_test"
"$out/http1_test"
