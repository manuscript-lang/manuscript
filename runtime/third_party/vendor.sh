#!/bin/sh
# Replaces runtime/third_party/<name> with the release pinned in c-libs.lock: downloads the tarball, checks its SHA-256,
# unpacks it and deletes what the build does not use (tests, fuzzers, demos, CI files). Usage: vendor.sh [name...] (all by default).
# Bumping a library: change its row in c-libs.lock, run this, build with build.sh, commit the folder.
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
# Folders that nothing in the build reads (checked by building every target). docs stay where a build file configures them.
trim() {
    case "$1" in
    openssl) drop="test demos .github" ;;
    curl) drop="tests .github" ;;
    libuv) drop="test docs .github" ;;
    nghttp2) drop="tests .github" ;;
    pcre2) drop="testdata .github" ;;
    zlib) drop="test contrib doc .github amiga msdos os400 qnx watcom win32" ;;
    esac
    for d in $drop; do rm -rf "${2:?}/$d"; done
    # OpenSSL's Configure reads doc/**/build.info; the manuals themselves are not built (no-docs).
    # Test keys and certificates (apps/*.pem, fuzz/*.c) trip secret scanning and are not built either.
    [ "$1" != nghttp2 ] || find "$2/integration-tests" -name '*.key' -delete
    # curl's CMake adds docs/examples unconditionally and the examples include test keys: leave an empty project.
    if [ "$1" = curl ]; then
        rm -rf "$2/docs/examples"
        mkdir -p "$2/docs/examples"
        echo '# curl examples are not built here (vendor.sh).' > "$2/docs/examples/CMakeLists.txt"
    fi
    if [ "$1" = openssl ]; then
        find "$2/doc" "$2/fuzz" -type f ! -name build.info -delete
        rm -f "$2"/apps/*.pem
    fi
}
names=${*:-$(awk '$1 !~ /^#/ && NF {print $1}' "$here/c-libs.lock")}
for name in $names; do
    read -r _ version url hash <<LOCK
$(awk -v n="$name" '$1==n' "$here/c-libs.lock")
LOCK
    archive=$work/$(basename "$url")
    curl --fail --location --retry 3 -sS -o "$archive" "$url"
    [ "$(sha "$archive")" = "$hash" ] || { echo "vendor.sh: checksum mismatch for $url" >&2; exit 1; }
    rm -rf "${here:?}/$name"
    mkdir -p "$here/$name"
    tar -xf "$archive" -C "$here/$name" --strip-components=1
    trim "$name" "$here/$name"
    echo "$name $version"
done
