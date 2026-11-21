#!/bin/sh
# Builds each FILE through the C object step (`ms emit` MIR text -> ms_build_object -> cc) and compares the
# program's output and exit status with the Rust `ms run`. Linux only (cc links the object with the runtime archive).
#   sh compiler/tests/build-object-diff.sh RUST_MS BUILD_OBJECT TOOLS RUNTIME_ARCHIVE WORKDIR FILE...
set -eu
rust=$(realpath "$1")
object=$(realpath "$2")
tools=$(realpath "$3")
runtime=$(realpath "$4")
work=$5
shift 5
mkdir -p "$work"
compared=0
skipped=0
failed=0
for file in "$@"; do
	cp "$file" "$work/t.ms"
	if ! (cd "$work" && "$rust" emit t.ms >t.mir 2>/dev/null); then
		skipped=$((skipped + 1))
		continue
	fi
	if ! "$object" "$work/t.mir" "$work/t.o" "$tools" 2>"$work/object.err"; then
		echo "object fails: $file: $(head -c 200 "$work/object.err")"
		failed=1
		continue
	fi
	cc -nostartfiles "$work/t.o" "$runtime" -lm -lpthread -ldl -Wl,--defsym=__dso_handle=0 -o "$work/t.out" 2>"$work/link.err" || {
		echo "link fails: $file: $(head -c 200 "$work/link.err")"
		failed=1
		continue
	}
	want_status=0
	got_status=0
	(cd "$work" && "$rust" run t.ms >want.txt 2>&1) || want_status=$?
	(cd "$work" && ./t.out >got.txt 2>&1) || got_status=$?
	compared=$((compared + 1))
	if [ "$want_status" != "$got_status" ] || ! cmp -s "$work/want.txt" "$work/got.txt"; then
		echo "differs: $file (status $want_status vs $got_status)"
		failed=1
	fi
done
echo "build-object-diff: $compared programs compared, $skipped skipped"
exit $failed
