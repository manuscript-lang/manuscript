#!/bin/sh
# Install checkout-local lint tools; downloads are confined to explicit setup.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=scripts/devtools.env
. "$repository/scripts/devtools.env"
destination="$repository/.tools"
mkdir -p "$destination"
if [ -f "$destination/versions" ] && cmp -s "$repository/scripts/devtools.env" "$destination/versions" &&
    [ -x "$destination/actionlint" ] && [ -x "$destination/shellcheck" ]; then
    exit 0
fi
case $(uname -s) in Linux) target_os=linux ;; Darwin) target_os=darwin ;; *) echo 'Developer lint setup requires Linux or macOS.' >&2; exit 1 ;; esac
case $(uname -m) in x86_64|amd64) shellcheck_arch=x86_64; actionlint_arch=amd64 ;; aarch64|arm64) shellcheck_arch=aarch64; actionlint_arch=arm64 ;; *) echo 'Unsupported lint tool architecture.' >&2; exit 1 ;; esac
staging=$(mktemp -d "$destination/.download-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM

# download URL ARCHIVE: fetch into the staging directory and verify the pinned SHA-256.
download() {
    url=$1
    archive=$2
    expected=$(awk -v name="$archive" '$2 == name {print $1}' "$repository/scripts/devtools.sha256")
    test -n "$expected"
    curl --fail --location --retry 3 --output "$staging/$archive" "$url"
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$staging/$archive" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "$staging/$archive" | awk '{print $1}')
    fi
    if [ "$actual" != "$expected" ]; then echo "$archive checksum mismatch." >&2; exit 1; fi
}

archive="actionlint_${ACTIONLINT_VERSION#v}_${target_os}_${actionlint_arch}.tar.gz"
download "https://github.com/rhysd/actionlint/releases/download/$ACTIONLINT_VERSION/$archive" "$archive"
tar -xzf "$staging/$archive" -C "$staging" actionlint
mv "$staging/actionlint" "$destination/actionlint"

archive="shellcheck-$SHELLCHECK_VERSION.$target_os.$shellcheck_arch.tar.xz"
download "https://github.com/koalaman/shellcheck/releases/download/$SHELLCHECK_VERSION/$archive" "$archive"
tar -xJf "$staging/$archive" -C "$staging"
mv "$staging/shellcheck-$SHELLCHECK_VERSION/shellcheck" "$destination/shellcheck"
cp "$repository/scripts/devtools.env" "$destination/versions"
