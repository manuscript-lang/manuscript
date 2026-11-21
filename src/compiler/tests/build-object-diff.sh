#!/bin/sh
# Builds each FILE through the C object and link steps (`ms emit` MIR text -> ms_build_object -> ms_build_link) and compares the
# program's output and exit status with the Rust `ms run`. Linux only (the C link step joins the object with the runtime archive).
#   sh src/compiler/tests/build-object-diff.sh RUST_MS BUILD_OBJECT BUILD_LINK TOOLS LLD LINKER_FILES RUNTIME_ARCHIVE WORKDIR FILE...
# TOOLS is the directory with opt and llc, LLD the lld executable, LINKER_FILES the directory with the crt files,
# libc.a, libunwind.a and glibc.symbols (the pinned release `ms` caches under ~/.cache/ms).
set -eu
rust=$(realpath "$1")
object=$(realpath "$2")
link=$(realpath "$3")
tools=$(realpath "$4")
lld=$(realpath "$5")
files=$(realpath "$6")
runtime=$(realpath "$7")
work=$8
shift 8
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
	"$link" "$work/t.o" "$work/t.out" "$lld" "$tools/llc" "$files" --input "$runtime" 2>"$work/link.err" || {
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
