#!/bin/sh
# Builds and runs every runtime/tests/{core,sys}_*.c unit test with AddressSanitizer and UBSan.
# Each test links all of runtime/core and runtime/sys/posix (the Windows layer is covered by the
# conformance corpus on Windows). Run from the repository root (`make c-test`); nightly, not the PR gate.
set -eu
out=target/c-test
mkdir -p "$out"
for t in runtime/tests/core_*.c runtime/tests/sys_*.c; do
    name=$(basename "$t" .c)
    cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined \
        -Wall -Wextra -Werror -Iruntime/include "$t" runtime/core/*.c runtime/sys/posix/*.c -lm -o "$out/$name"
    "$out/$name"
done
