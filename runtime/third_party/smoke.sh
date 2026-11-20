#!/bin/sh
# Builds the C libraries (build.sh) and runs the smoke programs in runtime/tests against them. Usage: smoke.sh [triple]
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
out=$(sh "$repository/runtime/third_party/build.sh" "${1:-host}")
cc=${CC:-cc}
cxx=${CXX:-c++}
exe=$repository/target/c-libs/clibs_smoke
"$cc" -O1 -Wall -I"$out/include" "$repository/runtime/tests/clibs_smoke.c" "$out/lib/libuv.a" "$out/lib/libllhttp.a" "$out/lib/libnghttp2.a" "$out/lib/libssl.a" "$out/lib/libcrypto.a" -lpthread -ldl -lm -o "$exe"
"$exe"
exe=$repository/target/c-libs/clibs_smoke_re2
"$cxx" -std=c++17 -O1 -Wall -I"$out/include" "$repository/runtime/tests/clibs_smoke_re2.cc" "$out/lib/libre2.a" -Wl,--start-group $(ls "$out"/lib/libabsl_*.a) -Wl,--end-group -static-libstdc++ -static-libgcc -lpthread -o "$exe"
"$exe"
