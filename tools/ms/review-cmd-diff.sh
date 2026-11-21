#!/bin/sh
# Compares `ms review FILE --diff PATCH` of the Rust command line with tools/ms/review_cmd.ms on a
# git checkout per FILE: every fn exported, a function appended, a line prepended and the last
# lines cut, each reviewed as ascii, markdown and json, with --explain 1 and as a project map, from the
# project directory and from the checkout's top (the project in a subdirectory).
#   sh tools/ms/review-cmd-diff.sh RUST_MS REVIEW_CMD FACTS_PROGRAM WORKDIR FILE...
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
	mkdir -p "$work/repo/proj"
	cp "$file" "$work/repo/proj/a.ms"
	git -C "$work/repo" init -q .
	git -C "$work/repo" add -A
	git -C "$work/repo" -c user.email=a@b -c user.name=x commit -qm base
	lines=$(wc -l <"$file")
	ran=0
	for variant in export append prepend cut; do
		git -C "$work/repo" checkout -q -- .
		case $variant in
		export) sed -i 's/^fn /export fn /' "$work/repo/proj/a.ms" ;;
		append) printf 'export fn appended_by_review() Int:\n    return 3\n' >>"$work/repo/proj/a.ms" ;;
		prepend) sed -i '1i // edited' "$work/repo/proj/a.ms" ;;
		cut) head -n $((lines * 3 / 4)) "$file" >"$work/repo/proj/a.ms" ;;
		esac
		(cd "$work/repo/proj" && "$MS_FACTS" facts a.ms >/dev/null 2>&1) || continue
		git -C "$work/repo" diff --no-renames >"$work/p.patch"
		[ -s "$work/p.patch" ] || continue
		ran=$((ran + 1))
		for where in proj .; do
			target=a.ms
			patch=../../p.patch
			if [ "$where" = . ]; then
				target=proj/a.ms
				patch=../p.patch
			fi
			for options in "" "--format markdown" "--json" "--explain 1" "--explain 1 --json"; do
				# shellcheck disable=SC2086
				want=$(cd "$work/repo/$where" && "$rust" review "$target" --diff "$patch" $options 2>&1) || true
				got=$(cd "$work/repo/$where" && "$cmd" "$target" --diff "$patch" $(printf '%s' "$options" | sed 's/--json/--format json/') 2>&1) || true
				if [ "$want" != "$got" ]; then
					echo "review differs: $file $variant [$where] options='$options'"
					printf '%s\n' "$want" >"$work/want.txt"
					printf '%s\n' "$got" >"$work/got.txt"
					diff "$work/want.txt" "$work/got.txt" | head -20 || true
					failed=1
				fi
			done
		done
		for options in "" "--json"; do
			want=$(cd "$work/repo/proj" && "$rust" review a.ms $options 2>&1) || true
			got=$(cd "$work/repo/proj" && "$cmd" a.ms $(printf '%s' "$options" | sed 's/--json/--format json/') 2>&1) || true
			if [ "$want" != "$got" ]; then
				echo "project review differs: $file options='$options'"
				failed=1
			fi
		done
	done
	if [ "$ran" = 0 ]; then
		echo "review-cmd-diff: no variant of $file checked"
		failed=1
	fi
done
exit "$failed"
