#!/bin/sh
# Install checkout-local tools; downloads are confined to explicit setup.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=scripts/devtools.env
. "$repository/scripts/devtools.env"
destination="$repository/.tools"
mkdir -p "$destination"
if [ -f "$destination/versions" ] && cmp -s "$repository/scripts/devtools.env" "$destination/versions" &&
    [ -x "$destination/staticcheck" ] && [ -x "$destination/actionlint" ] && [ -x "$destination/shellcheck" ]; then
    exit 0
fi
go_tool=${MANUSCRIPT_GO:-$repository/toolchain/go/bin/go}
GOBIN="$destination" "$go_tool" install "honnef.co/go/tools/cmd/staticcheck@$STATICCHECK_VERSION"
GOBIN="$destination" "$go_tool" install "github.com/rhysd/actionlint/cmd/actionlint@$ACTIONLINT_VERSION"
case $(uname -s) in Linux) target_os=linux ;; Darwin) target_os=darwin ;; *) echo 'Developer lint setup requires Linux or macOS.' >&2; exit 1 ;; esac
case $(uname -m) in x86_64|amd64) target_arch=x86_64 ;; aarch64|arm64) target_arch=aarch64 ;; *) echo 'Unsupported lint tool architecture.' >&2; exit 1 ;; esac
archive="shellcheck-$SHELLCHECK_VERSION.$target_os.$target_arch.tar.xz"
expected=$(awk -v name="$archive" '$2 == name {print $1}' "$repository/scripts/devtools.sha256")
test -n "$expected"
staging=$(mktemp -d "$destination/.download-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
curl --fail --location --retry 3 --output "$staging/$archive" "https://github.com/koalaman/shellcheck/releases/download/$SHELLCHECK_VERSION/$archive"
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$staging/$archive" | awk '{print $1}')
else
    actual=$(shasum -a 256 "$staging/$archive" | awk '{print $1}')
fi
if [ "$actual" != "$expected" ]; then echo 'ShellCheck checksum mismatch.' >&2; exit 1; fi
tar -xJf "$staging/$archive" -C "$staging"
mv "$staging/shellcheck-$SHELLCHECK_VERSION/shellcheck" "$destination/shellcheck"
cp "$repository/scripts/devtools.env" "$destination/versions"
