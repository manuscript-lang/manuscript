#!/bin/sh
# Compares the interactive page of the Rust tool (`ms-tooling-dev html`) and tools/ms/html.ms over
# each FILE alone and against an edited copy (every fn exported), byte for byte.
#   sh tools/ms/html-diff.sh DEV_BINARY HTML_BINARY WORKDIR FILE...
set -eu
dev=$(realpath "$1")
html=$(realpath "$2")
work=$3
shift 3
rm -rf "$work"
mkdir -p "$work/base" "$work/head"
work=$(realpath "$work")
failed=0
for file in "$@"; do
	name=$(basename "$file")
	cp "$file" "$work/base/$name"
	sed 's/^fn /export fn /' "$file" >"$work/head/$name"
	(cd "$work/base" && "$dev" facts "$name" >"$work/base.json")
	if ! (cd "$work/head" && "$dev" facts "$name" >"$work/head.json" 2>/dev/null); then
		cp "$work/base.json" "$work/head.json"
		cp "$file" "$work/head/$name"
	fi
	for mode in alone against; do
		if [ "$mode" = alone ]; then
			want=$(cd "$work/head" && "$dev" html "$name")
			got=$("$html" "$work/head.json" "$work/head")
		else
			want=$(cd "$work/head" && "$dev" html "$name" "../base/$name")
			got=$("$html" "$work/head.json" "$work/head" "$work/base.json")
		fi
		[ "$want" = "$got" ] && continue
		echo "html differs: $file $mode"
		printf '%s\n' "$want" >"$work/want.html"
		printf '%s\n' "$got" >"$work/got.html"
		cmp "$work/want.html" "$work/got.html" || true
		failed=1
	done
done
exit "$failed"
