# Linux HTTP implementation evidence

These measurements describe a working tree based on
`0385da26a0bfcd3c891f332ba6883ed7c8372038`, not a released version. The host is Linux
x86_64 on an Intel Xeon Platinum 8573C with a four-core cgroup quota. Server and
load generator share that quota and a shared runner. Raw records include binary
hashes, workload configuration, CPU allocation, latency, errors and resources.
They demonstrate execution and recovery behavior; they are not portable capacity
or dedicated-runner latency guarantees.

## Correctness and application checks

[verification.json](verification.json) records the final repository gate:
930 workspace tests passed, including 268 network tests, plus lint, doc tests,
documentation, book and distribution checks. Five ignored entrypoints are child
process helpers exercised by their parent tests. All 21 HTTP fixture files passed
in Debug and Release, with 95 tests in each profile. The full 268-fixture Release
suite and 747 executing conformance cases passed after the allocator correction;
1508 conformance check cases also passed. Windows native cross-compilation passed;
Windows and macOS runtime execution remains unavailable in this environment.

The final serial run followed two investigated failures: a pre-existing one-second
stdin-concurrency timing assertion under competing tests, and a cancellation
fixture that could expire before reaching the intended producer. The revised
fixture requires headers and a nonzero producer chunk before pausing reads. It
still requires four committed, truncated responses per route and cycle, retries
only bounded complete precommit timeouts, and includes every attempt in memory
and descriptor recovery measurements. Both Debug and Release profiles passed.

[production-example.json](production-example.json) covers authentication, typed
JSON, validation, SSE, WebSocket echo, health, observations and multiple member
identities in both execution modes. The static build example also completed.
[reference-contract.json](reference-contract.json) records eight equivalent HTTP
cases plus 64 concurrent requests against Node 24.19.0, Express 5.1.0, Go 1.25.1,
Next 16.0.10 / React 19.2.3 and Manuscript. All passed. This is the specified common
application contract, not exhaustive framework equivalence or JavaScript/React
source compatibility.

## Whole-handler CPU execution

[persistent-cpu.json](persistent-cpu.json) uses the same CPU handler, 64 persistent
connections, a one-second warmup and eight-second measurement per configuration.
Each row is a paired one-/four-member comparison in one round. No errors occurred.

| Mode | Round | 1 member req/s | 4 members req/s | Ratio | Server cores at 4 members |
| --- | --- | ---: | ---: | ---: | ---: |
| Workers | 1 | 618 | 1370 | 2.22 | 3.06 |
| Workers | 2 | 1105 | 3305 | 2.99 | 3.37 |
| Processes | 1 | 1101 | 3342 | 3.03 | 3.36 |
| Processes | 2 | 750 | 2917 | 3.89 | 3.31 |

The four-member cases execute handlers on multiple cores and exceed the paired
single-member throughput. The variation across rounds shows why
these short shared-runner samples must not be treated as a universal scaling
factor. The client consumes part of the same four-core quota. Established HTTP/1
connections and HTTP/2 streams remain on their owning member; group TLS/affinity
regressions cover this explicitly.

## Deployment and connection churn

The final [connection-churn.json](connection-churn.json) includes 54 measurements:
two rounds of baseline/local, 1/2/4-member workers/processes, and a four-backend Go
proxy, each serving cheap, CPU and delayed handlers. It records 89 client
`IncompleteReadError`s, three 504 responses and one proxy 502 response. One first-round four-process CPU
sample returned only 27 responses/second with 21 client errors; the second round
returned 1,404/second without errors. The anomaly is retained and not attributed
to a specific cause. This run does not establish a throughput or latency SLO.

The persistent-client measurement also includes two four-backend proxy cases:
1,910 and 1,251 requests/second, versus 3,342 and 2,917 for built-in process groups
in the same rounds. Workers returned 1,370 and 3,305. All ten persistent CPU cases
had zero errors. These sequential shared-runner observations are not a universal
ranking; earlier measurements remain in `persistent-cpu-before-proxy-comparison.json`.

The proxy uses request-level round-robin and upstream connection pooling;
built-in groups use connection affinity. Churn closes frontend connections in
both deployments, but only the proxy pools backend connections. CPU and RSS
include the proxy and all backends. Python churn omits proxy member counts because
local backend bodies all identify member zero; the persistent client uses the
proxy's upstream-identity header. [proxy-deployment.json](proxy-deployment.json)
checks all four upstreams and complete five-process cleanup. The baseline was
reconstructed after implementation, not measured against a preselected target.

## Resource recovery

The [process soak](processes-soak.json), run without competing builds, completed 30 minutes after the
allocator and response-commitment corrections. A [worker follow-up](workers-recovery.json)
completed three minutes; the earlier worker run already covered 30 minutes.
[resource-summary.json](resource-summary.json) summarizes the raw observations.

| Mode | Duration | Idle RSS range, KiB | Idle descriptors | Recovery 200 responses | Recovery client errors |
| --- | ---: | ---: | ---: | ---: | ---: |
| Processes, 4 members | 1800 s | 14,088–16,288 | 71 | 863,154 | 46 |
| Workers, 4 members | 180 s | 5,820–5,948 | 51 | 52,958 | 31 |

Process idle RSS fell from 15,956 to 14,176 KiB rather than continuing to grow.
Worker idle RSS started at 5,828 and ended at 5,820 KiB. Process member small-heap
samples stayed within 17,552–18,320 bytes; worker members stayed at 5,072 bytes.
Every observed member sample had four tasks and one active request/connection
(the sample itself). Each group exited with the expected SIGTERM status 143;
none of its sampled process IDs survived shutdown.

Overload intentionally exceeds the 64-request cap per member. The process run
returned 289,708 overload 503s and 12 overload 504s, alongside 624,714 overload
200s; it also recorded 3,472 client errors under overload. Workers returned
31,437 overload 503s and 59,355 overload 200s, with 325 client errors. These errors
are retained, not counted as successful responses.

Recovery was not error-free. A passive 50 ms scheduling monitor started after the
first nine process recovery failures. All 37 later process failures and 24 of 31
worker failures overlapped gaps above 250 ms; the largest observed gap was about
six seconds. [runner-delays.json](runner-delays.json) preserves this correlation.
The fixture has one-second header/idle limits and a two-second request deadline.
Scheduling delays are relevant evidence, but do not establish the cause of every
error. The result establishes bounded resource recovery on this runner, not a
request-reliability or latency SLO.

[deadline-recovery.json](deadline-recovery.json) separately exercises 96 abandoned
worker requests and checks recovery of per-member heap, admissions, connections
and process descriptors. The short [processes-cache-diagnostic.json](processes-cache-diagnostic.json)
completed three minutes with no client errors and idle descriptors fixed at 71;
aggregate idle RSS varied from 14,724 to 15,240 KiB. It precedes the final response
commitment/HEAD changes and is diagnostic evidence, not the final long soak.

## Earlier measurements and acceptance limits

Files ending `before-cache-fix` preserve earlier paired 30-minute worker/process
soaks and CPU measurements. Worker RSS stayed near 5.9 MiB, while process RSS grew
from about 15.8 to 24.2 MiB. Profiling found retained allocator bins, and a separate
failing regression proved that eligible zeroed large allocations bypassed cached
blocks. The correction reuses/zeros matching blocks and rounds cold allocations
to their cache class. This establishes the allocator defect; the earlier RSS
correlation alone does not identify every allocating call site.

[allocator-cache-inspection.json](allocator-cache-inspection.json) retains only
layout-verified cache samples. [runner-delays-before-cache-fix.json](runner-delays-before-cache-fix.json)
records scheduling gaps; one coincided with a recovery failure, which is not proof
that every earlier error came from the runner. Earlier overload and recovery
errors remain in the raw records.

The baseline was reconstructed retrospectively from the archived commit. No
numeric dedicated-runner target was selected before implementation. The proxy
comparison is now executed; macOS/Windows runtime execution is unavailable here. Dedicated-runner and platform release acceptance
checks remain open; shared-runner measurements and cross-compilation do not
replace them.
