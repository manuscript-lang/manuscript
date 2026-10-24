#!/bin/sh
# Downloads the standard JSON corpora into bench/perf/json/data (not committed).
set -e
cd "$(dirname "$0")"
mkdir -p data
for f in twitter canada citm_catalog; do
    [ -s "data/$f.json" ] || curl -sSfL -o "data/$f.json" \
        "https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/$f.json"
done
# Small messages: the shape worker threads and RPC exchange.
[ -s data/small.json ] || cat > data/small.json <<'JSON'
{"id":12345,"type":"request","method":"tasks.spawn","params":{"name":"worker-7","args":["--fast","--verbose"],"timeout":1.5,"retry":true,"env":null},"tags":["a","b","c"],"user":{"id":99,"name":"Ada Lovelace","email":"ada@example.com"}}
JSON
