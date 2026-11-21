#!/bin/sh
# The formatter's golden cases: compiler/tests/format/NAME.src is formatted and compared with NAME.expected
# (a case without one only has to be stable). Formatting the result again must change nothing, and a case
# not named corpus_* (the recorded cases keep their CRLF text bytes) formats the same with CRLF line ends.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/format
rm -rf "$out"
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_syntax_dump
dump=target/cmake/test/compiler/ms_syntax_dump
status=0
for src in compiler/tests/format/*.src; do
    name=$(basename "$src" .src)
    expected=compiler/tests/format/$name.expected
    [ -f "$expected" ] || expected=
    "$dump" format "$src" | tail -n +2 > "$out/$name.lf"
    sed 's/$/\r/' "$src" > "$out/$name.crlf.src"
    "$dump" format "$out/$name.crlf.src" | tail -n +2 > "$out/$name.crlf"
    cp "$out/$name.lf" "$out/$name.again.src"
    "$dump" format "$out/$name.again.src" | tail -n +2 > "$out/$name.again"
    kinds="lf crlf again"
    case $name in corpus_*) kinds="lf again" ;; esac
    for got in $kinds; do
        want=$expected
        { [ "$got" = again ] || [ -z "$want" ]; } && want=$out/$name.lf
        if ! cmp -s "$out/$name.$got" "$want"; then
            echo "FAIL format $name ($got)"
            diff "$want" "$out/$name.$got" | head -10 || true
            status=1
        fi
    done
done
[ "$status" = 0 ] && echo "ok   format golden ($(ls compiler/tests/format/*.src | wc -l) cases)"
exit $status
