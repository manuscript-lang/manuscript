#!/bin/sh
# Compares `ms review` of the Rust tool (`ms-tooling-dev review`, `report`) and src/ms/review.ms and
# src/ms/report.ms on edited
# copies of each FILE: every fn exported, every export dropped, the last lines cut, a line added at
# the top and the file unchanged, each with changed-line and added-file options. A variant that
# does not check is skipped; the output must be equal for the rest, and at least one variant per
# file must have run.
#   sh src/ms/review-diff.sh DEV_BINARY REVIEW_BINARY REPORT_BINARY WORKDIR FILE...
set -eu
dev=$(realpath "$1")
review=$(realpath "$2")
report=$(realpath "$3")
work=$4
shift 4
rm -rf "$work"
mkdir -p "$work"
work=$(realpath "$work")
failed=0
# Runs the Rust oracle quietly. Its one known crash (an entity removed from a file the diff adds) is
# reported by its message and skipped; any other crash fails the script instead of passing as output.
oracle() {
	sh -c '"$0" "$@" 2>&1' "$dev" "$@" 2>/dev/null
}
crashed=0
# Fails on a crash of the oracle other than its known one; $1 says what ran.
note_crash() {
	[ "$crashed" -ge 128 ] || { crashed=0; return 0; }
	case "$want" in *"a key comes from base or head"*) ;; *) echo "oracle crashed ($crashed): $1"; failed=1 ;; esac
	crashed=0
}
for file in "$@"; do
	name=$(basename "$file")
	ran=0
	mkdir -p "$work/base" "$work/head"
	cp "$file" "$work/base/$name"
	if ! (cd "$work/base" && "$dev" facts "$name" >"$work/base.json" 2>/dev/null); then
		echo "review-diff: $file does not check"
		failed=1
		continue
	fi
	lines=$(wc -l <"$file")
	for variant in export unexport cut prepend same; do
		case $variant in
		export) sed 's/^fn /export fn /' "$file" >"$work/head/$name" ;;
		unexport) sed 's/^export fn /fn /' "$file" >"$work/head/$name" ;;
		cut) head -n $((lines * 3 / 4)) "$file" >"$work/head/$name" ;;
		prepend) (echo "// edited"; cat "$file") >"$work/head/$name" ;;
		same) cp "$file" "$work/head/$name" ;;
		esac
		(cd "$work/head" && "$dev" facts "$name" >"$work/head.json" 2>/dev/null) || continue
		ran=$((ran + 1))
		for options in "" "--no-base" "--added $name" "--touch $name:3 --touch $name:$((lines / 4)) --touch $name:$((lines / 2)) --touch $name:$((lines * 2 / 3)) --touch $name:$lines"; do
			# shellcheck disable=SC2086
			want=$(cd "$work/base" && oracle review "$name" "../head/$name" $options) || crashed=$?
			note_crash "$file $variant"
			# shellcheck disable=SC2086
			got=$("$review" "$work/base.json" "$work/head.json" $options 2>&1) || true
			# The Rust tool panics on an entity removed from a file the diff adds; the port drops it.
			if [ "$want" != "$got" ]; then
				case "$want" in *"a key comes from base or head"*) continue ;; esac
				echo "review differs: $file $variant options='$options'"
				printf '%s\n' "$want" >"$work/want.txt"
				printf '%s\n' "$got" >"$work/got.txt"
				diff "$work/want.txt" "$work/got.txt" | head -20 || true
				failed=1
				continue
			fi
			for extra in "--format ascii" "--format markdown" "--format json --all" "--all" "--effect std.*" "--effect std.fs.read --format json"; do
				# shellcheck disable=SC2086
				want=$(cd "$work/base" && oracle report "$name" "../head/$name" --stats 2 1 7 3 $options $extra) || crashed=$?
				note_crash "$file $variant"
				# shellcheck disable=SC2086
				got=$("$report" "$work/base.json" "$work/head.json" --stats=2,1,7,3 $options $extra 2>&1) || true
				[ "$want" = "$got" ] && continue
				case "$want" in *"a key comes from base or head"*) continue ;; esac
				echo "report differs: $file $variant options='$options $extra'"
				printf '%s\n' "$want" >"$work/want.txt"
				printf '%s\n' "$got" >"$work/got.txt"
				diff "$work/want.txt" "$work/got.txt" | head -20 || true
				failed=1
			done
		done
	done
	for extra in "--format ascii" "--format markdown" "--format json" "--all"; do
		# shellcheck disable=SC2086
		want=$(cd "$work/base" && oracle report --project "$name" $extra) || crashed=$?
		note_crash "$file project"
		# shellcheck disable=SC2086
		got=$("$report" --project "$work/base.json" $extra 2>&1) || true
		[ "$want" = "$got" ] && continue
		echo "project report differs: $file $extra"
		printf '%s\n' "$want" >"$work/want.txt"
		printf '%s\n' "$got" >"$work/got.txt"
		diff "$work/want.txt" "$work/got.txt" | head -20 || true
		failed=1
	done
	if [ "$ran" = 0 ]; then
		echo "review-diff: no variant of $file checked"
		failed=1
	fi
done
exit "$failed"
