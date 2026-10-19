#!/bin/sh
# Build the Rust ms for this machine: one binary with the native runtime (ms-native) embedded.
# The release runner for each target builds it natively; the archive is dist/manuscript-rust-<os>-<arch>.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

if [ "$#" -eq 2 ]; then
    target_os=$1
    target_arch=$2
elif [ "$#" -eq 0 ]; then
    case "$(uname -s)" in
        Linux) target_os=linux ;;
        Darwin) target_os=darwin ;;
        MINGW*|MSYS*|CYGWIN*) target_os=windows ;;
        *) echo "Unsupported host: $(uname -s)" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) target_arch=amd64 ;;
        aarch64|arm64|ARM64) target_arch=arm64 ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac
else
    echo 'Usage: package-rust.sh [OS ARCH]' >&2
    exit 2
fi
case "$target_os/$target_arch" in
    linux/amd64|linux/arm64|darwin/amd64|darwin/arm64|windows/amd64|windows/arm64) ;;
    *) echo "Unsupported distribution target: $target_os/$target_arch" >&2; exit 1 ;;
esac

executable=ms
if [ "$target_os" = windows ]; then executable=ms.exe; fi

# `ms-cli`'s build script builds ms-native in release mode and embeds it.
cargo build --release --locked -p ms-cli

name="manuscript-rust-$target_os-$target_arch"
mkdir -p dist
staging=$(mktemp -d "$repository/dist/.package-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
bundle="$staging/$name"
mkdir -p "$bundle/examples/hello/src"
cp "target/release/$executable" "$bundle/$executable"
cp examples/hello/ms.toml "$bundle/examples/hello/"
cp examples/hello/src/main.ms "$bundle/examples/hello/src/"

if [ "$target_os" = windows ]; then
    archive="dist/$name.zip"
    rm -f "$archive"
    (cd "$staging" && 7z a -tzip -bso0 "$repository/$archive" "$name")
else
    archive="dist/$name.tar.gz"
    tar -C "$staging" -czf "$archive" "$name"
fi
if command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
else
    (cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
fi
echo "$archive"
