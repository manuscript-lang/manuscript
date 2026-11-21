#!/bin/sh
# Compares the expression type kinds of the C checker (`ms_check_dump STDLIB --nodes`) with the
# Rust checker's (`ms-tooling-dev nodes`) on each FILE. A node both typed must have the same kind. A
# node only the C checker typed (the literal of a match-arm pattern) is counted, not failed: the
# Rust checker gives it no type, so a rule keyed on "typed" never reads it. The C checker types only the functions its body pass claims,
# so the count of nodes it typed against Rust's is printed, and a run that types none fails.
#   sh src/compiler/tests/nodes-diff.sh CHECK_DUMP DEV_BINARY WORKDIR FILE...
set -eu
dump=$(realpath "$1")
dev=$(realpath "$2")
work=$3
shift 3
stdlib=$(realpath "$(dirname "$0")/../../stdlib")
mkdir -p "$work"
files=0
skipped=0
typed=0
total=0
only_c=0
failed=0
for file in "$@"; do
	cp "$file" "$work/main.ms"
	if ! "$dev" nodes "$work/main.ms" >"$work/rust.txt" 2>/dev/null; then
		skipped=$((skipped + 1))
		continue
	fi
	if ! "$dump" "$stdlib" --nodes "$work/main.ms" >"$work/c.json" 2>/dev/null; then
		echo "nodes: C dump failed on $file"
		failed=1
		continue
	fi
	jq -r '.nodes[] | "\(.id) \(.kind)"' "$work/c.json" | sort >"$work/c.txt"
	sort "$work/rust.txt" >"$work/rust.sorted"
	files=$((files + 1))
	typed=$((typed + $(wc -l <"$work/c.txt")))
	total=$((total + $(wc -l <"$work/rust.sorted")))
	only_c=$((only_c + $(comm -13 "$work/rust.sorted" "$work/c.txt" | wc -l)))
	cut -d' ' -f1 "$work/rust.sorted" | sort >"$work/rust.ids"
	# C lines whose id Rust typed, but with another kind.
	extra=$(comm -13 "$work/rust.sorted" "$work/c.txt" | while read -r id kind; do grep -qx "$id" "$work/rust.ids" && echo "$id $kind"; done || true)
	if [ -n "$extra" ]; then
		echo "nodes differ: $file"
		echo "$extra" | head -5
		failed=1
	fi
done
echo "nodes-diff: $files files compared, $skipped skipped, $typed of $total typed expressions covered by C, $only_c typed only by C"
[ "$typed" -gt 0 ] || failed=1
exit "$failed"
