# HTTP tail latency

Compares p50 to max latency of the same HTTP server written in Manuscript, Node and Go.

- `server.ms`, `server.js`, `server.go`: build a JSON body of 64 items (4096 for `/big`) and reply. `/slow` first burns about 5 ms of CPU.
- `load.go`: open loop load generator. It sends on a fixed schedule over keep-alive connections and measures from the scheduled send time, so a stall is charged to every request it delayed. Requests to `/slow` and `/big` are left out of the numbers.

```
go build -o /tmp/load load.go && go build -o /tmp/goserver server.go
ms build server.ms -o /tmp/msserver
/tmp/msserver &  node server.js 8082 &  /tmp/goserver 8083 &
/tmp/load -addr 127.0.0.1:8081 -rate 2000 -conns 64 -slow 20 -dur 15s
/tmp/load -addr 127.0.0.1:8081 -rate 0 -conns 64 -dur 8s    # closed loop: requests per second
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

## Results, 2026-11-16, connection stealing, same 4 vCPU Linux VM

"Before" is `main` at 688af5b7; "now" is 7d462817 with [connection stealing](../../proposals/http-connection-stealing.md). Servers alternated in one session, two rounds of 15 to 20 s per scenario, ranges shown; the machine is shared, so compare rows of this table only with each other.

| Scenario | Server | p50 | p99 | p99.9 |
| --- | --- | --- | --- | --- |
| 5% of requests burn 5 ms CPU, 2000 req/s | Manuscript before | 0.75 to 0.84 ms | 5.8 to 6.2 ms | 9.1 to 18.7 ms |
| | Manuscript now | 0.63 ms | **3.2 ms** | 5.5 to 5.7 ms |
| | Go | 0.65 ms | 2.9 to 3.2 ms | 5.7 ms |
| | Node | 2.5 ms | 10.8 to 15.9 ms | 16.7 to 28.4 ms |
| Fast handlers, 4000 req/s, 64 conns | Manuscript before | 0.67 ms | 1.8 ms | 6.0 to 6.8 ms |
| | Manuscript now | 0.67 ms | 1.5 to 1.9 ms | 3.9 to 11.3 ms |
| | Go | 0.66 ms | 1.7 to 1.8 ms | 5.2 to 6.5 ms |
| | Node | 0.68 ms | 1.9 to 2.2 ms | 6.0 to 7.5 ms |
| 1 in 20 responses is 120 KB, 2000 req/s | Manuscript before | 0.63 ms | 1.9 to 2.0 ms | 5.8 to 6.5 ms |
| | Manuscript now | 0.62 ms | 1.6 to 2.5 ms | 3.8 to 14.2 ms |
| | Go | 0.65 ms | 1.5 to 2.0 ms | 3.3 to 5.8 ms |
| 1000 conns, 6000 req/s | Manuscript before | 0.63 ms | 1.6 to 2.0 ms | 4.1 to 6.5 ms |
| | Manuscript now | 0.63 ms | 1.7 ms | 4.2 to 4.7 ms |
| | Go | 0.50 to 0.54 ms | 1.8 to 2.5 ms | 3.9 to 5.7 ms |

| Cost, fast handlers | CPU for 88,000 requests at 4000 req/s | Peak memory | Closed loop, 64 conns |
| --- | --- | --- | --- |
| Manuscript before | 5.2 to 5.8 s | 7.5 MB | 118k to 121k req/s |
| Manuscript now | 5.4 to 6.0 s | 6.4 MB | 112k to 113k req/s |
| Go | 9.6 to 10.1 s | 14.5 MB | 53k to 56k req/s |
| Node | 6.0 s | 69 MB | 24k req/s |

Findings: with a computing handler in the mix the p99 falls from the handler time to Go's level, and the p50 falls below Go's. Fast-handler latency, CPU and memory are unchanged within the noise of this machine. Closed loop on a machine the load generator shares is 2 to 6% lower (repeated fresh starts: 117k to 132k against 131k to 134k): a thread the operating system sets aside for a millisecond looks like a computing handler, so the watcher looks often (about 6% of one core) and idle threads take connections that needed no help.
