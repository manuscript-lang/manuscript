#!/bin/sh
# Baselines for the C rewrite targets (proposals/c-runtime.md, plan section 1a). Linux only.
# Usage: MS=./target/release/ms sh bench/perf/c-targets/run.sh [stage] [measure ...]
# Prints "key value" lines; paste them into a dated section of README.md. Measures:
#   build   cold build of the runtime (only meaningful on a clean target/)
#   hello   hello-world binary size and start-up (min of 25 runs)
#   tasks   resident memory per parked task (100k tasks)
#   ws      resident memory per idle websocket connection (slope between 2k and 10k)
#   tls     resident memory per idle TLS connection (slope between 1k and 5k)
#   web     HTTP requests per second (bench/tools/web_bench.ms)
#   suite   whole programs against C: -O2 and checked (bounds + overflow trapping)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
MS=${MS:-$root/target/release/ms}
stage=${1:-now}
[ $# -gt 0 ] && shift
want=${*:-hello tasks ws tls web suite}
work=${BENCH_OUTPUT:-$(mktemp -d)}
mkdir -p "$work"
want_it() { case " $want " in *" $1 "*) return 0 ;; esac; return 1; }
say() { echo "$stage $*"; }
rss_kb() { awk '/^VmRSS/{print $2}' "/proc/$1/status"; }
pte_kb() { awk '/^VmPTE/{print $2}' "/proc/$1/status"; }
now() { date +%s%N; }

if want_it build; then
  s=$(now); (cd "$root" && cmake -P cmake/BuildRuntime.cmake >/dev/null 2>&1); e=$(now)
  say "runtime_build_seconds $(( (e - s) / 1000000000 ))"
fi

if want_it hello; then
  printf 'fn main() Void:\n\tprint("hello")\n' >"$work/hello.ms"
  "$MS" build "$work/hello.ms" -o "$work/hello" >/dev/null
  say "hello_bytes $(stat -c %s "$work/hello")"
  best=999999999; i=0
  while [ $i -lt 25 ]; do
    s=$(now); "$work/hello" >/dev/null; e=$(now)
    t=$(( (e - s) / 1000 )); [ $t -lt $best ] && best=$t; i=$((i + 1))
  done
  say "hello_start_us $best"
fi

if want_it tasks; then
  "$MS" run "$root/bench/perf/tasks/main.ms" -- 100000 sleep | sed "s/^/$stage tasks_100k_sleep /"
fi

# Server in $work/server, client in $work/client; hold N connections and read the server's RSS.
idle() { # idle <mode> <low> <high> [server args]
  mode=$1; low=$2; high=$3; shift 3
  "$MS" build "$here/server" -o "$work/server_bin" >/dev/null
  (cd "$here/client" && go build -o "$work/client_bin" main.go)
  port=$((20000 + $$ % 20000))
  "$work/server_bin" $port $mode "$@" & srv=$!
  sleep 1
  base=$(rss_kb $srv)
  "$work/client_bin" $mode $port $low >"$work/c1.out" & c1=$!
  while ! grep -q holding "$work/c1.out"; do sleep 0.5; done
  sleep 3; r_low=$(rss_kb $srv); p_low=$(pte_kb $srv)
  "$work/client_bin" $mode $port $((high - low)) >"$work/c2.out" & c2=$!
  while ! grep -q holding "$work/c2.out"; do sleep 0.5; done
  sleep 3; r_high=$(rss_kb $srv); p_high=$(pte_kb $srv)
  say "${mode}_idle base_kb $base held $(cut -d' ' -f2 "$work/c1.out") + $(cut -d' ' -f2 "$work/c2.out")"
  awk -v m=$mode -v s=$stage -v lo=$low -v hi=$high -v a=$r_low -v b=$r_high -v pa=$p_low -v pb=$p_high \
    'BEGIN{printf "%s %s_idle_bytes_per_conn %.0f (rss) %.0f (page tables)\n", s, m, (b-a)*1024/(hi-lo), (pb-pa)*1024/(hi-lo)}'
  kill $c1 $c2 $srv 2>/dev/null || true; wait 2>/dev/null || true
}
want_it ws && idle ws 2000 10000
if want_it tls; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=localhost \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  idle tls 1000 5000 "$work/cert.pem" "$work/key.pem"
fi

if want_it web; then
  "$MS" run "$root/bench/tools/web_bench.ms" -- run 5 | sed "s/^/$stage web /"
fi

if want_it suite; then
  progs=$(ls "$root"/bench/perf/suite/*/main.c | sed 's|.*/suite/||; s|/main.c||' | tr '\n' ' ')
  for flags in "-O2" "-O2 -fsanitize=bounds,signed-integer-overflow -fsanitize-trap=all"; do
    echo "$stage suite C flags: $flags"
    CFLAGS="$flags" MS="$MS" sh "$root/bench/perf/suite/run.sh" 5 $progs |
      awk -v s="$stage" 'NR==1{print s, "suite", $0; next} {r=($6>0)?sprintf("%.2fx",$2/$6):"-"; print s, "suite", $0, "ms/c", r}'
  done
fi
