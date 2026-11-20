#!/bin/sh
# Runs the smoke programs in runtime/tests against the C libraries libs.sh selects (system packages by default,
# MS_C_LIBS=pinned for the versions in c-libs.lock).
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
libs=$repository/runtime/third_party/libs.sh
cc=${CC:-cc}
cflags=$(sh "$libs" cflags)
mkdir -p "$repository/target/c-libs"
run() { # test name, extra sources, then library names after --
    name=$1; shift
    sources=$repository/runtime/tests/$name.c
    while [ "$1" != -- ]; do sources="$sources $repository/$1"; shift; done
    shift
    # shellcheck disable=SC2086
    "$cc" -O1 -Wall $cflags $sources $(sh "$libs" libs "$@") -o "$repository/target/c-libs/$name"
    "$repository/target/c-libs/$name"
}
run clibs_smoke -- uv llhttp nghttp2 ssl crypto
run clibs_smoke_zlib -- z
run clibs_smoke_pcre2 -- pcre2
run http1_test runtime/net/http1.c -- llhttp
run tls_test runtime/net/tls.c -- ssl crypto
run ws_test runtime/net/ws.c -- crypto
run conn_test runtime/net/conn.c runtime/net/http1.c -- llhttp
run h2_test runtime/net/h2.c -- nghttp2
