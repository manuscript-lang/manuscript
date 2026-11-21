#!/bin/sh
# Runs every diagram view (text, Mermaid and JSON; whole program and named entities; depths 0
# and 2) of each FILE through the Rust views (`ms-tooling-dev view`) and the Manuscript
# src/ms/views.ms, and requires equal output. An error the Rust views report must appear in
# the Manuscript tool's error text.
#   sh src/ms/views-diff.sh DEV_BINARY VIEWS_BINARY WORKDIR FILE...
set -eu
dev=$(realpath "$1")
views=$(realpath "$2")
work=$3
shift 3
mkdir -p "$work"
failed=0
for file in "$@"; do
	facts="$work/$(basename "$file" .ms).json"
	"$dev" facts "$file" >"$facts"
	entities=$(grep -o '"name": "[^"]*"' "$facts" | cut -d'"' -f4 | sort -u | head -4)
	for view in overview calls effects errors modules flow scope tasks types ownership; do
		for entity in "" $entities; do
			for depth in 0 2; do
				for format in ascii mermaid json; do
					want=$("$dev" view "$file" "$view" "$entity" "$depth" "$format" 2>&1 || true)
					got=$("$views" "$facts" "$view" "$entity" "$depth" "$format" 2>&1 || true)
					[ "$want" = "$got" ] && continue
					case "$want" in
					"error: "*) case "$got" in *"${want#error: }"*) continue ;; esac ;;
					esac
					echo "views differ: $file $view entity='$entity' depth=$depth $format"
					failed=1
				done
			done
		done
	done
done
exit "$failed"
