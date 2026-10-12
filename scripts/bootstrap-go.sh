#!/bin/sh
# Fetch a verified toolchain into an installation, never a system directory.
set -eu

repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=$(cat "$repository/.go-version")
if [ "$#" -eq 0 ]; then
    case $(uname -s) in
        Linux) target_os=linux ;;
        Darwin) target_os=darwin ;;
        *) echo 'Use a Manuscript release archive on this operating system.' >&2; exit 1 ;;
    esac
    case $(uname -m) in
        x86_64|amd64) target_arch=amd64 ;;
        aarch64|arm64) target_arch=arm64 ;;
        *) echo 'No bundled toolchain is available for this architecture.' >&2; exit 1 ;;
    esac
    destination="$repository/toolchain"
elif [ "$#" -eq 3 ]; then
    target_os=$1
    target_arch=$2
    destination=$3
else
    echo 'Usage: bootstrap-go.sh [GOOS GOARCH destination]' >&2
    exit 2
fi

extension=tar.gz
go_binary=go
if [ "$target_os" = windows ]; then
    extension=zip
    go_binary=go.exe
fi
archive="go$version.$target_os-$target_arch.$extension"
expected=$(awk -v name="$archive" '$2 == name {print $1}' "$repository/scripts/toolchains.sha256")
if [ -z "$expected" ]; then
    echo "No pinned toolchain for $target_os/$target_arch." >&2
    exit 1
fi

mkdir -p "$destination"
# Keep the SDK's own test fixtures outside the enclosing repository's ./... .
printf 'module manuscript.local/toolchain\n' > "$destination/go.mod"

if [ -f "$destination/go/VERSION" ] &&
    [ "$(sed -n '1p' "$destination/go/VERSION")" = "go$version" ] &&
    [ -f "$destination/go/bin/$go_binary" ] &&
    [ -d "$destination/go/pkg/tool" ] && [ -d "$destination/go/src" ]; then
    exit 0
fi

staging=$(mktemp -d "$destination/.download-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
echo "Preparing Manuscript's bundled Go $version ($target_os/$target_arch)..." >&2
curl --fail --location --retry 3 --output "$staging/$archive" "https://dl.google.com/go/$archive"
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$staging/$archive" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$staging/$archive" | awk '{print $1}')
else
    echo 'A SHA-256 utility (sha256sum or shasum) is required.' >&2
    exit 1
fi
if [ "$actual" != "$expected" ]; then
    echo "Toolchain checksum mismatch for $archive; installation stopped." >&2
    exit 1
fi
if [ "$extension" = zip ]; then
    unzip -q "$staging/$archive" -d "$staging"
else
    tar -xzf "$staging/$archive" -C "$staging"
fi
rm -rf "$destination/go"
mv "$staging/go" "$destination/go"
