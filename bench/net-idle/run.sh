#!/bin/sh
# Builds bench/net-idle/server.c from the C runtime pieces and prints the bytes per idle connection, plain
# WebSocket and HTTP keep-alive, at 2000 and 8000 connections. Linux only. Raise the descriptor limit first
# (ulimit -n 20000). Usage (repository root): sh bench/net-idle/run.sh
set -eu
cd "$(dirname "$0")/../.."
libs=src/runtime/third_party/libs.sh
out=target/net-idle
mkdir -p "$out"
# shellcheck disable=SC2046
cc -std=gnu11 -O2 -Wall -Wextra -Iruntime/include -Iruntime/third_party/llhttp/include $(sh $libs cflags) \
    bench/net-idle/server.c src/runtime/sys/linux/net.c src/runtime/io/ring.c src/runtime/net/conn.c src/runtime/net/http1.c \
    src/runtime/net/ws.c src/runtime/net/tls.c $(sh $libs libs uv ssl crypto llhttp) -o "$out/server"
ulimit -n 20000 2>/dev/null || true
# shellcheck disable=SC2046
cc -std=gnu11 -O1 -Wall $(pkg-config --cflags openssl) bench/net-idle/tls_memory.c src/runtime/net/tls.c \
    $(pkg-config --libs openssl) -o "$out/tls_memory"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=localhost \
    -keyout "$out/key.pem" -out "$out/cert.pem" 2>/dev/null
# Each row: the client mode, then "tls" when the server and client speak TLS (a server given a certificate).
for mode in "ws" "http" "ws tls" "http tls"; do
    for count in 2000 8000; do
        port=$((20000 + count / 100))
        case "$mode" in *tls) certificate="$out/cert.pem $out/key.pem" ;; *) certificate= ;; esac
        # shellcheck disable=SC2086
        "$out/server" "$port" $((count + 10)) $certificate > "$out/ready" &
        server=$!
        while ! grep -q ready "$out/ready" 2>/dev/null; do sleep 0.1; done
        # shellcheck disable=SC2086
        python3 bench/net-idle/client.py "$port" "$server" "$count" $mode
        kill "$server"; wait "$server" 2>/dev/null || true
        rm -f "$out/ready"
    done
done
"$out/tls_memory" "$out/cert.pem" "$out/key.pem"
