#!/bin/sh
# Installs the Manuscript agent skill without the compiler, on Linux or macOS.
#
#   curl -fsSL https://manuscript-lang.github.io/manuscript/install-skill.sh | sh
#   curl -fsSL https://manuscript-lang.github.io/manuscript/install-skill.sh | sh -s -- .claude/skills
#
# It downloads manuscript-skill.tar.gz from a release, checks its SHA-256 and unpacks the
# `manuscript` folder into each parent directory named on the command line (default:
# .claude/skills and .agents/skills). An existing `manuscript` folder is never overwritten.
# Settings, all optional:
#   MS_VERSION      a release such as 2026.11.0 (default: the latest release); the skill
#                   matches the language version of that release
#   MS_RELEASE_URL  a directory URL that holds the archive (default: GitHub releases)
set -eu

repo="manuscript-lang/manuscript"
version="${MS_VERSION:-latest}"

fail() {
	echo "install-skill: $1" >&2
	exit 1
}

if [ $# -eq 0 ]; then
	set -- .claude/skills .agents/skills
fi

if [ -n "${MS_RELEASE_URL:-}" ]; then
	base="$MS_RELEASE_URL"
elif [ "$version" = latest ]; then
	base="https://github.com/$repo/releases/latest/download"
else
	base="https://github.com/$repo/releases/download/v${version#v}"
fi

name="manuscript-skill"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

curl -fsSL "$base/$name.tar.gz" -o "$work/$name.tar.gz" || fail "cannot download $base/$name.tar.gz"
curl -fsSL "$base/$name.tar.gz.sha256" -o "$work/$name.tar.gz.sha256" || fail "cannot download the checksum"

expected="$(cut -d ' ' -f 1 "$work/$name.tar.gz.sha256")"
if command -v sha256sum >/dev/null 2>&1; then
	actual="$(sha256sum "$work/$name.tar.gz" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
	actual="$(shasum -a 256 "$work/$name.tar.gz" | cut -d ' ' -f 1)"
else
	fail "sha256sum or shasum is required to check the download"
fi
[ "$expected" = "$actual" ] || fail "checksum mismatch: expected $expected, got $actual"

tar -xzf "$work/$name.tar.gz" -C "$work"
[ -f "$work/manuscript/SKILL.md" ] || fail "the archive has no manuscript/SKILL.md"

# Check every destination first so a refusal leaves nothing half installed.
for parent in "$@"; do
	[ ! -e "$parent/manuscript" ] || fail "$parent/manuscript exists; existing skill files are never overwritten; remove it or choose another directory"
done
for parent in "$@"; do
	mkdir -p "$parent"
	cp -R "$work/manuscript" "$parent/manuscript"
	echo "Wrote the Manuscript agent skill to $parent/manuscript"
done
