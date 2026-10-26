#!/bin/sh
# Run the packaged Rust ms for this host (built by package-rust.sh) on the hello example, from a
# path that contains spaces.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) echo "Unsupported host: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
name="manuscript-rust-$os-$arch"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT HUP INT TERM
mkdir -p "$staging/extracted distribution"
tar -xzf "$repository/dist/$name.tar.gz" -C "$staging/extracted distribution"
bundle="$staging/extracted distribution/$name"
"$bundle/ms" --version
cd "$bundle/examples/hello"
output=$("$bundle/ms" run ms.toml -- first second)
test "$output" = "Arguments: 2"
"$bundle/ms" build ms.toml -o hello
output=$(./hello first second)
test "$output" = "Arguments: 2"
"$bundle/ms" test test.ms
