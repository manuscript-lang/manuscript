#!/bin/sh
# Build one self-contained ms binary with a reduced native build payload.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"
sh scripts/bootstrap-go.sh
host_go="$repository/toolchain/go/bin/go"
export GOROOT="$repository/toolchain/go"
export GOTOOLCHAIN=local
export GOENV=off
export CGO_ENABLED=0

if [ "$#" -eq 0 ]; then
    target_os=$("$host_go" env GOHOSTOS)
    target_arch=$("$host_go" env GOHOSTARCH)
elif [ "$#" -eq 2 ]; then
    target_os=$1
    target_arch=$2
else
    echo 'Usage: package.sh [GOOS GOARCH]' >&2
    exit 2
fi
case "$target_os/$target_arch" in
    linux/amd64|linux/arm64|darwin/amd64|darwin/arm64|windows/amd64|windows/arm64) ;;
    *) echo "Unsupported distribution target: $target_os/$target_arch" >&2; exit 1 ;;
esac

mkdir -p dist
# Extracted distributions must also stay outside repository-wide Go checks.
printf 'module manuscript.local/distributions\n' > dist/go.mod
staging=$(mktemp -d "$repository/dist/.package-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
name="manuscript-$target_os-$target_arch"
bundle="$staging/$name"
mkdir -p "$bundle"
executable=ms
if [ "$target_os" = windows ]; then executable=ms.exe; fi
if [ "$target_os/$target_arch" = "$("$host_go" env GOHOSTOS)/$("$host_go" env GOHOSTARCH)" ]; then
    target_sdk="$GOROOT"
else
    sh scripts/bootstrap-go.sh "$target_os" "$target_arch" "$staging/sdk"
    target_sdk="$staging/sdk/go"
fi
"$host_go" run ./scripts/mktoolchain "$target_sdk" "$staging/build-payload.tar.gz" "$target_os" "$target_arch"
# Delve gates its Windows ARM64 native backend behind this upstream build tag.
# It has no effect on other targets, and does not enable CGO.
GOOS="$target_os" GOARCH="$target_arch" "$host_go" build -tags bundled_toolchain,exp.winarm64 -overlay "$staging/build-payload.tar.gz.overlay.json" -trimpath -mod=vendor -o "$bundle/$executable" ./cmd/ms
mkdir -p "$bundle/examples/hello/src" "$bundle/licenses"
cp examples/hello/ms.toml "$bundle/examples/hello/"
cp examples/hello/src/main.ms "$bundle/examples/hello/src/"
# Ship each vendored dependency's license under its source identity.
find vendor -type f \( -name 'LICENSE*' -o -name 'COPYING*' -o -name 'PATENTS*' \) | while IFS= read -r notice; do
    destination="$bundle/licenses/$notice"
    mkdir -p "$(dirname "$destination")"
    cp "$notice" "$destination"
done
cp "$target_sdk/LICENSE" "$bundle/licenses/go.txt"
cp "$target_sdk/PATENTS" "$bundle/licenses/go-PATENTS.txt"
cp scripts/distribution-README.txt "$bundle/README.txt"
cp examples/hello/test.ms "$bundle/examples/hello/"

if [ "$target_os" = windows ]; then
    archive="$name.zip"
    (cd "$staging" && zip -qr "$archive" "$name")
else
    archive="$name.tar.gz"
    tar -czf "$staging/$archive" -C "$staging" "$name"
fi
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$staging" && sha256sum "$archive" > "$archive.sha256")
else
    (cd "$staging" && shasum -a 256 "$archive" > "$archive.sha256")
fi
rm -rf "$repository/dist/$name"
mv "$bundle" "$repository/dist/$name"
mv "$staging/$archive" "$staging/$archive.sha256" "$repository/dist/"
echo "Created dist/$archive"
