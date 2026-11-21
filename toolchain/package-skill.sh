#!/bin/sh
# Packs the agent skill into manuscript-skill.tar.gz and its checksum. Needs no compiler.
#
#   sh toolchain/package-skill.sh <output-directory>
#
# The archive holds one folder, `manuscript/`, copied from src/ms/data/agent-skill and
# stamped with the version in .msversion. Every release attaches it under the same file name, so
# releases/latest/download/ is a stable URL.
set -eu

[ $# -eq 1 ] || { echo "usage: package-skill.sh <output-directory>" >&2; exit 2; }
out="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root/.msversion")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "$root/src/ms/data/agent-skill" "$work/manuscript"
find "$work/manuscript" -name '*.md' | while read -r file; do
	sed "s/{{MS_VERSION}}/$version/g" "$file" >"$file.new"
	mv "$file.new" "$file"
done
if grep -rq '{{MS_VERSION}}' "$work/manuscript"; then echo "package-skill: unfilled version placeholder" >&2; exit 1; fi

mkdir -p "$out"
tar -C "$work" -czf "$out/manuscript-skill.tar.gz" manuscript
(cd "$out" && { sha256sum manuscript-skill.tar.gz 2>/dev/null || shasum -a 256 manuscript-skill.tar.gz; } >manuscript-skill.tar.gz.sha256)
