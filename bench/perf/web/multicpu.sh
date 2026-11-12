#!/bin/sh
# Multi-CPU comparison of the Manuscript, C and hyper servers with the C load generator.
# usage: multicpu.sh <ms-server> <c-server> <hyper-server> [seconds]
# Each server is `server <port> <data-dir> <threads>`. Build them with
#   (cd bench/perf/web/ms && ms build -o /tmp/ws_ms); cc -O2 -pthread -o /tmp/ws_c bench/perf/web/c/server.c
#   (cd bench/perf/web/rust && cargo build --release); cc -O2 -o /tmp/loadc bench/perf/web/load/loadc.c -lpthread
# Needs four CPUs. Rows: server on 1 CPU, on 2 CPUs (load on the other two), and on all four
# with the load generator sharing them.
set -e
ms=$1 c=$2 hy=$3 secs=${4:-4}
mkdir -p /tmp/wd
run() { # name binary server-cpus load-cpus path
	n=$(echo "$3" | tr ',' '\n' | wc -l)
	l=$(echo "$4" | tr ',' '\n' | wc -l)
	port=$((20000 + $$ % 20000))
	taskset -c "$3" "$2" "$port" /tmp/wd "$n" >/dev/null 2>&1 &
	pid=$!
	sleep 1
	out=$(taskset -c "$4" /tmp/loadc "$port" 128 "$secs" "$5" "$l")
	kill -9 "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
	echo "$1 server-cpus=$3 load-cpus=$4 $5 $out"
}
for round in 1 2; do
	for path in /health /user/42; do
		for cfg in "0 1,2,3" "0,1 2,3" "0,1,2,3 0,1,2,3"; do
			set -- $cfg "$ms" "$c" "$hy"
			sc=$1 lc=$2
			run manuscript "$3" "$sc" "$lc" "$path"
			run c "$4" "$sc" "$lc" "$path"
			run hyper "$5" "$sc" "$lc" "$path"
		done
	done
done
