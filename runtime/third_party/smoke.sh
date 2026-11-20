#!/bin/sh
# Builds the C libraries (build.sh) and runs the smoke programs in runtime/tests against them. Usage: smoke.sh [triple]
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
out=$(sh "$repository/runtime/third_party/build.sh" "${1:-host}")
cc=${CC:-cc}
exe=$repository/target/c-libs/clibs_smoke
"$cc" -O1 -Wall -I"$out/include" "$repository/runtime/tests/clibs_smoke.c" "$out/lib/libuv.a" "$out/lib/libllhttp.a" "$out/lib/libnghttp2.a" "$out/lib/libssl.a" "$out/lib/libcrypto.a" -lpthread -ldl -lm -o "$exe"
"$exe"
exe=$repository/target/c-libs/clibs_smoke_zlib
"$cc" -O1 -Wall -I"$out/include" "$repository/runtime/tests/clibs_smoke_zlib.c" "$out/lib/libz.a" -o "$exe"
"$exe"
exe=$repository/target/c-libs/clibs_smoke_pcre2
"$cc" -O1 -Wall -I"$out/include" "$repository/runtime/tests/clibs_smoke_pcre2.c" "$out/lib/libpcre2-8.a" -o "$exe"
"$exe"
exe=$repository/target/c-libs/http1_test
"$cc" -O1 -Wall -Wextra -I"$out/include" "$repository/runtime/tests/http1_test.c" "$repository/runtime/net/http1.c" "$out/lib/libllhttp.a" -o "$exe"
"$exe"
exe=$repository/target/c-libs/tls_test
"$cc" -O1 -Wall -Wextra -I"$out/include" "$repository/runtime/tests/tls_test.c" "$repository/runtime/net/tls.c" "$out/lib/libssl.a" "$out/lib/libcrypto.a" -lpthread -ldl -o "$exe"
"$exe"
