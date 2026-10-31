#!/bin/sh
# Usage: bench/compile-time/run.sh [packages files fns]  (default 40 25 10 ≈ 122k ms lines)
# Generates the same program in Manuscript and Go and times each build.
set -e
here=$(cd "$(dirname "$0")" && pwd)
P=${1:-40}; F=${2:-25}; K=${3:-10}
out=${OUT:-$(mktemp -d)}
MS=${MS:-ms}
python3 "$here/gen.py" "$P" "$F" "$K" "$out"
printf '[project]\nname = "big"\nsource = "./src"\nentry = "./src/main.ms"\n' > "$out/ms/ms.toml"
t() { s=$(date +%s.%N); "$@" >/dev/null; e=$(date +%s.%N); echo "$(echo "$e - $s" | bc) s"; }
echo "go cold:   $(cd "$out/go" && go clean -cache && t go build -o ../gobin .)"
echo "ms check:  $(cd "$out/ms" && t $MS check ms.toml)"
echo "ms emit:   $(cd "$out/ms" && t $MS emit ms.toml)"
echo "ms debug:  $(cd "$out/ms" && rm -rf .ms-cache && t $MS build ms.toml -o ../msbin_d --build-type Debug)"
echo "ms clif:   $(cd "$out/ms" && rm -rf .ms-cache && MS_BACKEND=cranelift t $MS build ms.toml -o ../msbin_c)"
[ -n "$SKIP_LLVM" ] || echo "ms release: $(cd "$out/ms" && rm -rf .ms-cache && t $MS build ms.toml -o ../msbin)"
