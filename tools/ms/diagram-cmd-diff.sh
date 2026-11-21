#!/bin/sh
# Compares `ms diagram FILE --view V [--diff PATCH]` of the Rust command line with
# tools/ms/diagram_cmd.ms on a git checkout per FILE, over every view in ascii, mermaid and JSON,
# unmarked and marked by a diff (every fn exported, a function appended), and with a depth bound.
#   sh tools/ms/diagram-cmd-diff.sh RUST_MS DIAGRAM_CMD FACTS_PROGRAM WORKDIR FILE...
set -eu
rust=$(realpath "$1")
cmd=$(realpath "$2")
MS_FACTS=$(realpath "$3")
export MS_FACTS
work=$4
shift 4
rm -rf "$work"
mkdir -p "$work"
work=$(realpath "$work")
failed=0
for file in "$@"; do
	rm -rf "$work/repo"
	mkdir -p "$work/repo"
	cp "$file" "$work/repo/a.ms"
	git -C "$work/repo" init -q .
	git -C "$work/repo" add -A
	git -C "$work/repo" -c user.email=a@b -c user.name=x commit -qm base
	ran=0
	for variant in export append; do
		git -C "$work/repo" checkout -q -- .
		case $variant in
		export) sed -i 's/^fn /export fn /' "$work/repo/a.ms" ;;
		append) printf 'export fn appended_by_review() Int:\n    return 3\n' >>"$work/repo/a.ms" ;;
		esac
		(cd "$work/repo" && "$MS_FACTS" facts a.ms >"$work/facts.json" 2>/dev/null) || continue
		head -c1 "$work/facts.json" | grep -q "{" || continue
		git -C "$work/repo" diff --no-renames >"$work/p.patch"
		[ -s "$work/p.patch" ] || continue
		ran=$((ran + 1))
		for view in overview calls effects errors modules flow scope tasks types ownership; do
			for options in "" "--format mermaid" "--json" "--depth 1" "--diff ../p.patch" "--diff ../p.patch --format mermaid" "--diff ../p.patch --json"; do
				# shellcheck disable=SC2086
				want=$(cd "$work/repo" && "$rust" diagram a.ms --view $view $options 2>&1) || true
				# shellcheck disable=SC2086
				got=$(cd "$work/repo" && "$cmd" a.ms --view $view $(printf '%s' "$options" | sed 's/--json/--format json/') 2>&1) || true
				if [ "$want" != "$got" ]; then
					echo "diagram differs: $file $variant view=$view options='$options'"
					printf '%s\n' "$want" >"$work/want.txt"
					printf '%s\n' "$got" >"$work/got.txt"
					diff "$work/want.txt" "$work/got.txt" | head -10 || true
					failed=1
				fi
			done
		done
	done
	if [ "$ran" = 0 ]; then
		echo "diagram-cmd-diff: no variant of $file checked"
		failed=1
	fi
done
exit "$failed"
