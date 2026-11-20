#!/bin/sh
# Builds and runs every runtime/tests/core_*.c unit test with AddressSanitizer and UBSan.
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
