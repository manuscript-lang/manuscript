#!/bin/sh
# Compares the fact JSON of the C checker (`ms_check_dump STDLIB --facts`) with the Rust
# checker's (`ms-tooling-dev facts`) on each FILE, with src/ms/facts_diff.ms (it names the
# fields compared). A file the Rust side rejects is skipped and counted; the count is printed.
#   sh src/compiler/tests/facts-diff.sh CHECK_DUMP DEV_BINARY FACTS_DIFF_BINARY WORKDIR FILE...
set -eu
dump=$(realpath "$1")
dev=$(realpath "$2")
diff_tool=$(realpath "$3")
work=$4
shift 4
stdlib=$(realpath "$(dirname "$0")/../../stdlib")
mkdir -p "$work"
compared=0
skipped=0
failed=0
for file in "$@"; do
	cp "$file" "$work/main.ms"
	# The Rust dump names the file by its basename; both tools see main.ms.
	if ! "$dev" facts "$work/main.ms" >"$work/rust.json" 2>/dev/null || ! head -c1 "$work/rust.json" | grep -q '{'; then
		skipped=$((skipped + 1))
		continue
	fi
	if ! "$dump" "$stdlib" --facts "$work/main.ms" >"$work/c.json" 2>"$work/c.err" || ! head -c1 "$work/c.json" | grep -q '{'; then
		echo "facts: C dump failed on $file"
		failed=1
		continue
	fi
	compared=$((compared + 1))
	if ! "$diff_tool" "$work/rust.json" "$work/c.json" >"$work/diff.txt" 2>&1; then
		echo "facts differ: $file"
		head -5 "$work/diff.txt"
		failed=1
	fi
done
echo "facts-diff: $compared files compared, $skipped skipped"
exit "$failed"
