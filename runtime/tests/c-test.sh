#!/bin/sh
# Builds and runs every runtime/tests/core_*.c unit test (linked with all of runtime/core) and every
# runtime/tests/std_*.c unit test (linked with all of runtime/std and the system PCRE2) with AddressSanitizer and UBSan.
# Run from the repository root (`make c-test`); nightly, not the PR gate.
set -eu
out=target/c-test
mkdir -p "$out"
flags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Iruntime/include"
for t in runtime/tests/core_*.c; do
    name=$(basename "$t" .c)
    cc $flags "$t" runtime/core/*.c -lm -o "$out/$name"
    "$out/$name"
done
for t in runtime/tests/std_*.c; do
    name=$(basename "$t" .c)
    # shellcheck disable=SC2046
    cc $flags $(pkg-config --cflags libpcre2-8) "$t" runtime/std/*.c $(pkg-config --libs libpcre2-8) -lm -o "$out/$name"
    "$out/$name"
done
