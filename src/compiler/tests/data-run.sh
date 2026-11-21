#!/bin/sh
# Prints the static data of each src/compiler/tests/data/*.mir with ms_mir_data and compares it with
# the .out file beside it. Run from the repository root: `make c-compiler-test`.
set -eu
sh src/compiler/tests/cbuild.sh ms_mir_data
bin=target/cmake/test/compiler
status=0
for mir in src/compiler/tests/data/*.mir; do
    name=${mir%.mir}
    if ! "$bin/ms_mir_data" "$mir" | diff -u "$name.out" -; then
        echo "FAIL $name"
        status=1
    else
        echo "ok $name"
    fi
done
exit $status
