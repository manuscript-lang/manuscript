#!/bin/sh
# Runs each query of search_queries.txt through the Rust `ms search_symbol` and the Manuscript
# tools/ms/search.ms (text, --json and --limit 10) and requires equal output and status.
#   sh tools/ms/search-diff.sh RUST_MS SEARCH_BINARY
set -eu
rust_ms=$(realpath "$1")
search=$(realpath "$2")
queries=$(realpath "$(dirname "$0")/search_queries.txt")
empty=$(mktemp -d)
trap 'rm -rf "$empty"' EXIT
cd "$empty"
failed=0
while IFS= read -r query; do
	for mode in "" "--json" "--limit 10"; do
		# shellcheck disable=SC2086
		want=$("$rust_ms" search_symbol $mode "$query" 2>&1; echo "status=$?")
		# shellcheck disable=SC2086
		got=$("$search" $mode "$query" 2>&1; echo "status=$?")
		if [ "$want" != "$got" ]; then
			echo "search_symbol differs: [$mode] $query"
			failed=1
		fi
	done
done <"$queries"
exit "$failed"
