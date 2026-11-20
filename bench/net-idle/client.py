"""Opens N idle connections to bench/net-idle/server.c and reports the server's memory per connection.

Usage: client.py <port> <server pid> <connections> <ws|http>
First checks one connection works (an HTTP hello, or a WebSocket echo), then opens the rest and leaves them idle.
"""
import base64, os, socket, struct, sys, time

port, pid, count, mode = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
GET = b"GET / HTTP/1.1\r\nHost: x\r\n\r\n"
UPGRADE = (b"GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
           b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")


def status(key):
    for line in open(f"/proc/{pid}/status"):
        if line.startswith(key):
            return int(line.split()[1])
    raise SystemExit(f"no {key} for pid {pid}")


def connect():
    sock = socket.create_connection(("127.0.0.1", port))
    sock.sendall(UPGRADE if mode == "ws" else GET)
    reply = sock.recv(1024)
    want = b"101" if mode == "ws" else b"hello"
    assert want in reply, reply
    if mode == "ws":
        assert b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in reply, reply  # the RFC 6455 sample accept value
    return sock


def echo_check(sock):
    if mode != "ws":
        return
    mask = b"\x01\x02\x03\x04"
    text = b"ping me"
    frame = bytes([0x81, 0x80 | len(text)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(text))
    sock.sendall(frame)
    got = sock.recv(64)
    assert got == bytes([0x81, len(text)]) + text, got


first = connect()
echo_check(first)
time.sleep(1)
rss0, pte0 = status("VmRSS:"), status("VmPTE:")
socks = [connect() for _ in range(count)]
time.sleep(3)
rss1, pte1 = status("VmRSS:"), status("VmPTE:")
print(f"{mode} n={count}: {(rss1 - rss0) * 1024 / count:.0f} B rss + {(pte1 - pte0) * 1024 / count:.0f} B page table per idle connection")
