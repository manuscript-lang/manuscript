#!/bin/sh
# usage: fetch.sh [seconds]; Manuscript's fetch and Go's net/http client against one Go file server,
# for a tiny body and an 8 MiB body, with 1 and 8 connections. Server on SERVER_CPUS (default 0,1),
# clients on LOAD_CPUS (default 2,3).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}; GO=${GO:-go}; SECS=${1:-3}
SERVER_CPUS=${SERVER_CPUS:-0,1}; LOAD_CPUS=${LOAD_CPUS:-2,3}
MS=$(command -v "$MS"); GO=$(command -v "$GO")
W=$(mktemp -d)
trap 'pkill -f "^$W/" 2>/dev/null; rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/fetch/go" "$HERE/fetch/ms" "$W/"
mkdir "$W/data"
printf 'ok\n' > "$W/data/small"
head -c 8388608 /dev/urandom > "$W/data/big"
yes "the quick brown fox jumps over the lazy dog 0123456789" | head -c 8388608 > "$W/data/text"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -trimpath -o fetch .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o fetch >&2)
if ! command -v taskset >/dev/null || [ "$(nproc)" -lt 4 ]; then SERVER_CPUS=; LOAD_CPUS=; fi
on() { cpus=$1; shift; if [ -n "$cpus" ]; then exec taskset -c "$cpus" "$@"; fi; exec "$@"; }
(on "$SERVER_CPUS" "$W/go/fetch" serve 18950 "$W/data" >/dev/null 2>&1) &
sleep 1
for file in small big; do
  for conns in 1 8 64; do
    [ "$file" = big ] && [ "$conns" = 64 ] && continue
    url=http://127.0.0.1:18950/$file
    echo "$file connections=$conns go $( (on "$LOAD_CPUS" "$W/go/fetch" get "$url" $conns "$SECS") )"
    echo "$file connections=$conns ms $( (on "$LOAD_CPUS" "$W/ms/fetch" "$url" $conns "$SECS") )"
    if [ "$conns" = 8 ]; then
      echo "$file connections=$conns ms threads=2 $( (on "$LOAD_CPUS" "$W/ms/fetch" "$url" $conns "$SECS" 2) )"
    fi
  done
done
# Framings of the same 8 MiB: chunked (random) and gzip (compressible text), one connection.
for path in chunked/big gzip/text; do
  url=http://127.0.0.1:18950/$path
  echo "$path connections=1 go $( (on "$LOAD_CPUS" "$W/go/fetch" get "$url" 1 "$SECS") )"
  echo "$path connections=1 ms $( (on "$LOAD_CPUS" "$W/ms/fetch" "$url" 1 "$SECS") )"
done
