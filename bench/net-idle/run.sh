#!/bin/sh
# Builds bench/net-idle/server.c from the C runtime pieces and prints the bytes per idle connection, plain
# WebSocket and HTTP keep-alive, at 2000 and 8000 connections. Linux only. Raise the descriptor limit first
# (ulimit -n 20000). Usage (repository root): sh bench/net-idle/run.sh
set -eu
cd "$(dirname "$0")/../.."
libs=runtime/third_party/libs.sh
out=target/net-idle
mkdir -p "$out"
# shellcheck disable=SC2046
cc -std=gnu11 -O2 -Wall -Wextra -Iruntime/include -Iruntime/third_party/llhttp/include $(sh $libs cflags) \
    bench/net-idle/server.c runtime/sys/linux/net.c runtime/io/ring.c runtime/net/conn.c runtime/net/http1.c \
    runtime/net/ws.c $(sh $libs libs uv crypto llhttp) -o "$out/server"
ulimit -n 20000 2>/dev/null || true
for mode in ws http; do
    for count in 2000 8000; do
        port=$((20000 + count / 100))
        "$out/server" "$port" $((count + 10)) > "$out/ready" &
        server=$!
        while ! grep -q ready "$out/ready" 2>/dev/null; do sleep 0.1; done
        python3 bench/net-idle/client.py "$port" "$server" "$count" "$mode"
        kill "$server"; wait "$server" 2>/dev/null || true
        rm -f "$out/ready"
    done
done
