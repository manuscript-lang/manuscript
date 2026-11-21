#!/bin/sh
# Installs the Manuscript compiler (`ms`) on Linux or macOS.
#
#   curl -fsSL https://manuscript-lang.github.io/manuscript/install.sh | sh
#
# It downloads the release archive for this machine, checks its SHA-256, and copies `ms`
# and `ms-rust` into a bin directory. Settings, all optional:
#   MS_VERSION      a release such as 2026.11.0 (default: the latest release)
#   MS_INSTALL_DIR  where `ms` goes (default: $HOME/.local/bin)
#   MS_RELEASE_URL  a directory URL that holds the archives (default: GitHub releases)
set -eu

repo="manuscript-lang/manuscript"
version="${MS_VERSION:-latest}"
dir="${MS_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
	echo "install: $1" >&2
	exit 1
}

case "$(uname -s)" in
Linux) os=linux ;;
Darwin) os=darwin ;;
*) fail "unsupported system $(uname -s); on Windows run install.ps1 from PowerShell" ;;
esac

case "$(uname -m)" in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*) fail "unsupported processor $(uname -m)" ;;
esac

if [ -n "${MS_RELEASE_URL:-}" ]; then
	base="$MS_RELEASE_URL"
elif [ "$version" = latest ]; then
	base="https://github.com/$repo/releases/latest/download"
else
	base="https://github.com/$repo/releases/download/v${version#v}"
fi

name="manuscript-rust-$os-$arch"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

echo "Downloading $name"
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
mkdir -p "$dir"
# `ms` finds `ms-rust`, the Rust command line it hands some stages to, in its own directory.
for file in ms-rust ms; do
	cp "$work/$name/$file" "$dir/$file.new"
	chmod 755 "$dir/$file.new"
	mv "$dir/$file.new" "$dir/$file"
done

echo "Installed $("$dir/ms" --version) to $dir/ms"
case ":$PATH:" in
*":$dir:"*) ;;
*) echo "Add $dir to your PATH, for example: export PATH=\"$dir:\$PATH\"" ;;
esac
