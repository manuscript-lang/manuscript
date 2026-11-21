#!/bin/sh
# The driver: unit tests for the stage table and parse entry point, then the thin `ms` executable run
# in front of a stand-in for the Rust `ms` to prove the handover keeps arguments, output streams and
# exit statuses. The stand-in needs no Rust build; the real Rust `ms` behind the C one is exercised
# by running the conformance corpus with `ms-conform run --ms target/cmake/test/compiler/ms` (MS_RUST_CLI set).
# Run from the repository root: `make c-driver-test`.
set -eu
out=target/c-compiler
mkdir -p "$out"
sh src/compiler/tests/cbuild.sh driver_test ms
bin=target/cmake/test/compiler
"$bin/driver_test"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The stand-in prints one argument per line on stdout, a marker on stderr, and exits with $STUB_STATUS
# (or kills itself with the signal named by $STUB_SIGNAL).
cat > "$tmp/stub-rust" <<'STUB'
#!/bin/sh
for arg in "$@"; do printf '%s\n' "$arg"; done
echo "stub-stderr" >&2
[ -z "${STUB_SIGNAL:-}" ] || kill "-$STUB_SIGNAL" $$
exit "${STUB_STATUS:-0}"
STUB
chmod +x "$tmp/stub-rust"
export MS_RUST_CLI="$tmp/stub-rust"

expect() { # description, expected status, then the ms arguments
    description=$1; want=$2; shift 2
    set +e
    "$bin/ms" "$@" > "$tmp/stdout" 2> "$tmp/stderr"
    got=$?
    set -e
    [ "$got" = "$want" ] || { echo "FAIL $description: status $got, wanted $want"; exit 1; }
    echo "ok   $description"
}

STUB_STATUS=0 expect "status 0" 0 --version
STUB_STATUS=3 expect "status 3 comes through" 3 run a.ms
printf '%s\n' run 'two words' '' > "$tmp/want"
STUB_STATUS=0 expect "arguments arrive unchanged" 0 run 'two words' ''
cmp -s "$tmp/stdout" "$tmp/want" || { echo "FAIL arguments differ"; cat "$tmp/stdout"; exit 1; }
grep -qx stub-stderr "$tmp/stderr" || { echo "FAIL stderr not passed through"; exit 1; }
STUB_SIGNAL=TERM expect "a signal becomes 128 plus its number" 143 run a.ms
STUB_STATUS=2 expect "an unknown command is the Rust ms's to reject" 2 bogus

MS_DRIVER_TRACE=1 "$bin/ms" check a.ms 2>&1 >/dev/null | grep -q 'check -> rust'
echo "ok   trace"
MS_STAGES=bogus=c "$bin/ms" check a.ms > /dev/null 2>&1 && { echo "FAIL a bad MS_STAGES must be refused"; exit 1; }
echo "ok   bad MS_STAGES refused"
