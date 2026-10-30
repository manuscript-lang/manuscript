#!/bin/sh
# usage: run.sh [seconds]; serves the same endpoints from Manuscript and Go and measures each:
# throughput and p99 per endpoint, RSS, threads, system calls while idle and per request,
# /health with 10,000 idle keep-alive connections, and a file-and-DNS handler.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}; GO=${GO:-go}; SECS=${1:-5}
SERVER_CPUS=${SERVER_CPUS:-0,1}; LOAD_CPUS=${LOAD_CPUS:-2,3}
case "$SECS" in ''|*[!0-9]*|0) echo 'seconds must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
W=$(mktemp -d)
trap 'pkill -f "^$W/" 2>/dev/null; rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/go" "$HERE/ms" "$HERE/load" "$W/"
mkdir "$W/rust" && cp "$HERE/rust/Cargo.toml" "$HERE/rust/Cargo.lock" "$W/rust/" && cp -r "$HERE/rust/src" "$W/rust/"
mkdir "$W/data"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -trimpath -o server .)
(cd "$W/load" && CGO_ENABLED=0 "$GO" build -trimpath -o load .)
if command -v cargo >/dev/null; then (cd "$W/rust" && cargo build --release --locked -q >&2 && cp target/release/web-bench-rust server); NAMES="ms go rust"; else NAMES="ms go"; fi
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o server >&2)
ulimit -n 20000 2>/dev/null || echo 'note: open-file limit below 20000; the idle-connection row may fail' >&2
if ! command -v taskset >/dev/null || [ "$(nproc)" -lt 4 ]; then
  echo 'note: fewer than 4 CPUs or no taskset; server and load share CPUs' >&2
  SERVER_CPUS=; LOAD_CPUS=
fi
# on <cpus> <command...>: replaces the calling (sub)shell with the command, pinned when cpus is set.
on() { cpus=$1; shift; if [ -n "$cpus" ]; then exec taskset -c "$cpus" "$@"; fi; exec "$@"; }
load() { (on "$LOAD_CPUS" "$W/load/load" "$PORT" "$@"); }
# syscalls <pid> <seconds> <file>: total system calls of all threads while strace is attached.
syscalls() { timeout "$2" strace -f -c -p "$1" -o "$3" >/dev/null 2>&1 || true; awk '/total/ {n = $4} END {print n + 0}' "$3"; }

PORT=18090
for name in $NAMES; do
  extra=
  (on "$SERVER_CPUS" "$W/$name/server" "$PORT" "$W/data" $extra >/dev/null 2>&1) &
  i=0; until load 1 1 /health >/dev/null 2>&1; do i=$((i + 1)); [ $i -lt 50 ] || { echo "$name did not start" >&2; exit 1; }; sleep 0.1; done
  pid=$(pgrep -f "^$W/$name/server")
  for path in /health /user/42 '/top?n=10'; do
    for round in 1 2; do echo "$name $path $(load 64 "$SECS" "$path")"; done
  done
  if [ "$name" != rust ]; then
  for round in 1 2; do echo "$name io $(load 64 "$SECS" '/io?{c}')"; done
  load 32 "$SECS" '/io?{c}' > "$W/mixed" &
  sleep 0.2
  echo "$name health-during-io $(load 32 $((SECS - 1 > 0 ? SECS - 1 : 1)) /health)"
  wait $!
  echo "$name io-during-health $(cat "$W/mixed")"
  fi
  echo "$name threads $(ls /proc/$pid/task | wc -l) rss_kb $(ps -o rss= -p $pid)"
  if command -v strace >/dev/null; then
    echo "$name idle_syscalls_5s $(syscalls $pid 5 "$W/idle")"
    syscalls $pid 4 "$W/busy" > "$W/busy.n" &
    sleep 0.5
    reqs=$(load 64 2 /health | awk '{print $2 * 2}')
    wait $!
    echo "$name syscalls_per_request $(echo "scale=2; $(cat "$W/busy.n") / $reqs" | bc) (requests under strace $reqs)"
  fi
  (on "$LOAD_CPUS" "$W/load/load" idle "$PORT" 10000 > "$W/idle.out") &
  sleep 0.2; idlers=$(pgrep -f "^$W/load/load idle")
  i=0; until grep -q holding "$W/idle.out" || [ $i -ge 120 ]; do i=$((i + 1)); sleep 0.5; done
  echo "$name idle_connections $(cat "$W/idle.out") rss_kb $(ps -o rss= -p $pid)"
  echo "$name /health-with-10k-idle $(load 64 "$SECS" /health)"
  kill $idlers $pid; wait $idlers $pid 2>/dev/null || true
  PORT=$((PORT + 1))
done
