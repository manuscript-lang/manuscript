#!/bin/sh
# Runs `ms diagram` (text and Mermaid) of each FILE through the Rust `ms` and through
# src/ms/inspect.ms over the `ms inspect` document, and requires equal output.
#   sh src/ms/inspect-diff.sh RUST_MS INSPECT_BINARY WORKDIR FILE...
set -eu
rust_ms=$(realpath "$1")
inspect=$(realpath "$2")
work=$3
shift 3
mkdir -p "$work"
failed=0
for file in "$@"; do
	document="$work/$(basename "$file" .ms).inspect.json"
	"$rust_ms" inspect "$file" >"$document"
	for format in ascii mermaid; do
		want=$("$rust_ms" diagram --format "$format" "$file" 2>&1 || true)
		got=$("$inspect" "$document" "$format" 2>&1 || true)
		if [ "$want" != "$got" ]; then
			echo "diagram differs: $file $format"
			failed=1
		fi
	done
done
exit "$failed"
