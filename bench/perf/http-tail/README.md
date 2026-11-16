# HTTP tail latency

Compares p50 to max latency of the same HTTP server written in Manuscript, Node and Go.

- `server.ms`, `server.js`, `server.go`: build a JSON body of 64 items (4096 for `/big`) and reply. `/slow` first burns about 5 ms of CPU.
- `load.go`: open loop load generator. It sends on a fixed schedule over keep-alive connections and measures from the scheduled send time, so a stall is charged to every request it delayed. Requests to `/slow` and `/big` are left out of the numbers.

```
go build -o /tmp/load load.go && go build -o /tmp/goserver server.go
ms build server.ms -o /tmp/msserver
/tmp/msserver &  node server.js 8082 &  /tmp/goserver 8083 &
/tmp/load -addr 127.0.0.1:8081 -rate 2000 -conns 64 -slow 20 -dur 15s
```

## Results, 2026-11-15, 4 vCPU Linux VM, load generator on the same machine

| Scenario | Server | p50 | p99 | p99.9 | p99.99 |
| --- | --- | --- | --- | --- | --- |
| Fast handlers, 4000 req/s, 64 conns (30 s, 3 runs) | Manuscript | 0.66 ms | 1.44 ms | 3.3 to 4.9 ms | 6 to 10 ms |
| | Go | 0.65 ms | 1.50 ms | 3.2 to 4.7 ms | 7 to 12 ms |
| Same, 1000 conns, 6000 req/s | Manuscript | 0.62 ms | 1.46 ms | 4.1 ms | 11.3 ms |
| | Go / Node | 0.58 / 0.59 ms | 1.58 / 1.83 ms | 3.7 / 4.5 ms | 8.8 / 6.9 ms |
| 5% of requests burn 5 ms CPU (every 20th), 2000 req/s | Manuscript | 0.72 ms | **5.12 ms** | 6.6 ms | 12.8 ms |
| | Go | 0.62 ms | 1.45 ms | 3.6 ms | 5.4 ms |
| | Node | 1.77 ms | 8.45 ms | 10.6 ms | 13.1 ms |
| 1 in 20 responses is 120 KB, 2000 req/s | Manuscript | 0.60 ms | 1.46 ms | 3.9 ms | 7.9 ms |
| | Go | 0.63 ms | 1.41 ms | 2.0 ms | 3.5 ms |

Findings: with fast handlers Manuscript matches Go and Node. A request that burns CPU delays every other request on the same worker thread (a connection stays on one worker, and a handler is not preempted), so the p99 rises to the handler time. Go moves goroutines between threads and does not show it.
