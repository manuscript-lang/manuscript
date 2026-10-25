# HTTP implementation validation

Build `server.ms` with the checkout's native runtime and Release CLI. It runs the
same cheap, CPU, delayed and deadline handlers in local, worker or process mode.
`/stats` exposes each member's active requests/connections, tasks and small-block
heap usage. A sample includes its own request and connection. Large allocations
and native allocator capacity require the separate resident-memory observations.

```sh
ms build bench/http-server/server.ms -o /tmp/manuscript-http-bench-current
python3 bench/http-server/deadline_recovery.py /tmp/manuscript-http-bench-current
python3 bench/http-server/soak.py --server /tmp/manuscript-http-bench-current --mode workers --members 4 --duration 1800 --output /tmp/workers.json
python3 bench/http-server/soak.py --server /tmp/manuscript-http-bench-current --mode processes --members 4 --duration 1800 --output /tmp/processes.json
```

The Linux recovery harness alternates overload, idle, ordinary traffic and idle.
It offers at least 96 concurrent slow requests per member against the fixture's
64-request per-member cap using 100 ms handlers; recovery uses 16 clients.
The scaling comparison retains its separate 20 ms delayed route.
It records response codes, errors, p50/p99, throughput, member distribution,
process-tree RSS, descriptors, threads and per-member snapshots. Connection
acceptance can be uneven; a member index identifies execution, not round-robin
balancing. Run performance measurements without competing builds and record CPU
quota/affinity. A shared runner is evidence about correctness and recovery, not a
portable throughput promise.

`production_check.py` exercises the runnable service in both group modes, including
authentication, JSON errors, SSE, WebSockets, health and member distribution.
`reference/check.py` executes eight common HTTP cases and 64 concurrent requests
against pinned Node, Express, Go, Next and Manuscript applications. This is a
specified common contract, not exhaustive framework equivalence. Install the
reference lockfile with `npm ci --ignore-scripts`, compile `reference/go.go`, and
build Next with its pinned CLI before running it. The proposal records scope,
additional Manuscript regressions and unsupported protocol/framework features.

`baseline.ms` targets archived commit
`0385da26a0bfcd3c891f332ba6883ed7c8372038`; build it using that checkout's compiler
and runtime. It intentionally uses the old buffered-server signature. The baseline
was reconstructed after implementation and is not a preselected performance target.
Run the two-round comparison after all compilation/test jobs have finished:

```sh
python3 bench/http-server/scaling.py --baseline /tmp/manuscript-http-baseline --server /tmp/manuscript-http-bench-current --members 4 --seconds 5 --output /tmp/http-scaling.json
```

This measures connection churn for cheap, CPU and delayed routes, including
per-process/per-thread CPU, member distribution and p50/p99. Four members is N on
the current four-core CPU quota. The load generator shares that quota; results do
not establish dedicated-runner capacity or performance against a reverse proxy.

The Python connection-churn client can limit attainable CPU utilization. A separate
persistent-connection probe uses the same compiled CPU handler with a Go client:

```sh
go build -o /tmp/manuscript-http-cpu-client bench/http-server/cpu_client.go
python3 bench/http-server/cpu_scaling.py --server /tmp/manuscript-http-bench-current --client /tmp/manuscript-http-cpu-client --members 4 --output /tmp/http-cpu-scaling.json
```

It records two rounds of 1- and N-member worker/process execution, 64 persistent
connections, per-thread CPU, member distribution and errors. This is a separate
workload from the baseline/churn comparison; its numbers must not be mixed with
that comparison. The client still shares the machine's CPU quota.

Recorded Linux results and their limitations are kept in
[`results/2026-10-25-linux`](results/2026-10-25-linux/README.md). Binary hashes identify
the exact measured executables. Files named `before-cache-fix` preserve the earlier
measurements that led to the allocator correction; do not combine their timings
with a later run or treat them as evidence for the final binary.

For the independent-server comparison on Linux, build the Go proxy and pass it
to both measurement tools:

```sh
go build -o /tmp/manuscript-http-proxy bench/http-server/proxy_group.go
python3 bench/http-server/scaling.py --baseline /tmp/manuscript-http-baseline --server /tmp/manuscript-http-bench-final --proxy /tmp/manuscript-http-proxy --members 4 --output /tmp/http-scaling-proxy.json
python3 bench/http-server/cpu_scaling.py --server /tmp/manuscript-http-bench-final --client /tmp/manuscript-http-cpu-client --proxy /tmp/manuscript-http-proxy --members 4 --output /tmp/http-cpu-proxy.json
```

The proxy launches four independent local servers on the next four loopback
ports. It distributes requests round-robin and reuses upstream connections;
built-in groups distribute accepted connections and retain their affinity. Churn
closes frontend connections in both cases, but only the proxy pools backend
connections. This compares deployment topologies, not isolated listener overhead.
CPU and memory include the proxy and every backend. The persistent client records
`X-Benchmark-Upstream` counts. The Python churn probe omits proxy member counts
because each local server's response body identifies itself as member zero.
