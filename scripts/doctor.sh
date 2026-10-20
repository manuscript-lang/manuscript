#!/bin/sh
# Report prerequisites without downloading or changing the checkout.
set -u
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
failed=0
for command in make curl tar git; do
    if command -v "$command" >/dev/null 2>&1; then
        printf 'OK      %s\n' "$command"
    else
        printf 'MISSING %s\n' "$command"
        failed=1
    fi
done
if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    printf 'OK      SHA-256 utility\n'
else
    printf 'MISSING SHA-256 utility\n'; failed=1
fi
expected_node=$(cat "$repository/.node-version")
if command -v node >/dev/null 2>&1 && [ "$(node --version)" = "v$expected_node" ]; then
    printf 'OK      Node %s\n' "$expected_node"
else
    printf 'MISSING Node %s (install the version in .node-version)\n' "$expected_node"; failed=1
fi
if command -v cargo >/dev/null 2>&1; then printf 'OK      cargo\n';
else printf 'MISSING cargo (install rustup; rust-toolchain.toml pins the toolchain)\n'; failed=1; fi
if command -v cargo-nextest >/dev/null 2>&1 || cargo nextest --version >/dev/null 2>&1; then printf 'OK      cargo-nextest\n';
else printf 'MISSING cargo-nextest (cargo install cargo-nextest --locked)\n'; failed=1; fi
for command in actionlint shellcheck; do
    if [ -x "$repository/.tools/$command" ]; then printf 'OK      %s\n' "$command";
    else printf 'MISSING %s (run make setup)\n' "$command"; failed=1; fi
done
if ! cmp -s "$repository/scripts/devtools.env" "$repository/.tools/versions"; then
    printf 'MISSING current lint tool pins (run make setup)\n'; failed=1
fi
hugo_tool=${HUGO:-hugo}
hugo_output=$("$hugo_tool" version 2>/dev/null || true)
hugo_version=$(printf '%s\n' "$hugo_output" | awk '{print $2}' | sed 's/^v//;s/[-+].*//')
if printf '%s\n' "$hugo_output" | grep -q 'extended' &&
    awk -v version="$hugo_version" 'BEGIN { split(version, a, "."); exit !(a[1] > 0 || a[2] > 146 || a[2] == 146 && a[3] >= 7) }'; then
    printf '%s\n' "$hugo_output"
else
    printf 'MISSING Hugo Extended 0.146.7 or newer (book checks)\n'; failed=1
fi
if command -v cc >/dev/null 2>&1; then printf 'OK      C compiler (linking generated programs)\n';
else printf 'MISSING C compiler (linking generated programs)\n'; failed=1; fi
exit "$failed"
