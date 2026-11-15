#!/usr/bin/env bash
# Consumes packages/postgres the way a user would: as a git dependency, fetched into a cache, locked, then run.
# Needs a server (see start-postgres.sh) and the PG* variables it prints; MS is the ms binary.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ms=${MS:-$here/../../../../target/release/ms}
work=$(mktemp -d)
mkdir "$work/package" "$work/app"
# The package is the repository root of a throwaway git repository, as `[dependencies]` requires.
cp -r "$here/../../ms.toml" "$here/../../src" "$work/package/"
git -C "$work/package" init -q .
git -C "$work/package" add .
git -C "$work/package" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m package
git -C "$work/package" tag v1.0.0
path=$work/package
if command -v cygpath > /dev/null; then path=$(cygpath -m "$path"); fi
case "$path" in /*) url="file://$path#v1.0.0" ;; *) url="file:///$path#v1.0.0" ;; esac
cp -r "$here/ms.toml" "$here/src" "$work/app/"
sed -i.bak "s|PACKAGE_URL|$url|" "$work/app/ms.toml"
export MS_PACKAGE_CACHE="$work/cache"
cd "$work/app"
"$ms" fetch
out=$("$ms" run)
[ "$out" = "Value.Int(42)" ] || { echo "unexpected output: $out" >&2; exit 1; }
echo "consumer ok"
