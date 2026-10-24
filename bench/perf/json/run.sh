#!/bin/sh
# Compares @std/json against Node (V8) on standard documents.
# Usage: MS=target/release/ms sh bench/perf/json/run.sh   (NAMES="twitter canada" to select documents)
set -e
cd "$(dirname "$0")/../../.."
MS=${MS:-target/release/ms}
NAMES=${NAMES:-"small twitter canada citm_catalog"}
sh bench/perf/json/fetch.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
node bench/perf/json/node.js $NAMES > "$tmp/node.tsv"
"$MS" run bench/perf/json/ms.toml -- $NAMES > "$tmp/ms.tsv"
echo "node $(node --version), $(git rev-parse --short HEAD), $(uname -sm)"
python3 - "$tmp/node.tsv" "$tmp/ms.tsv" <<'PY'
import sys
def load(p):
    rows = (l.split("\t") for l in open(p).read().split("\n") if l.count("\t") == 3)
    return {(r[0], r[1]): (int(r[2]), int(r[3])) for r in rows}
n, m = load(sys.argv[1]), load(sys.argv[2])
print(f"{'doc':<14}{'op':<11}{'node MB/s':>10}{'ms MB/s':>10}{'ms speed':>10}")
for k in n:
    if k in m:
        nb = n[k][1] / n[k][0] * 1e3
        mb = m[k][1] / m[k][0] * 1e3
        print(f"{k[0]:<14}{k[1]:<11}{nb:>10.0f}{mb:>10.0f}{n[k][0] / m[k][0]:>9.2f}x")
PY
