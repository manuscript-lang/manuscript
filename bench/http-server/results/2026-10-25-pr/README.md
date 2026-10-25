# PR integration and performance follow-up

PR: [#1315](https://github.com/manuscript-lang/manuscript/pull/1315).

## Integration verification

The branch integrates main `97c5788bc`, including current scoped locks and
`with let`/`with var` syntax. [verification.json](verification.json) records
the commands, test partitions, corrections and limits. The workspace partitions
and four added regressions total 981 passing tests; the 30 native CLI integration
tests include Debug and Release interrupted-upload/response recovery with heap,
RSS and descriptor checks. All 118 MIR tests passed after the compiler fixes.
The exact repository conformance gate passed all 2,281 cases: 1,524 checks, 503
programs and 254 test fixtures; [conformance.json](conformance.json) retains the
summary and phase/tag counts.
All 21 HTTP fixtures passed in Debug and Release (95 tests per profile), plus
compression, String map, lock cancellation and mutable scope regressions.
Formatting, clippy, repository checks, API documentation, book generation and
Windows native cross-compilation passed. Native Windows/macOS execution remains
unavailable.

Integration fixed last-use placement of a pending child drop at block start and
duplicate cancellation release of explicitly scoped ownership through loop
parameters and mutable receiver slots. Independent review checked these changes.
The cancellation analysis still conservatively excludes taken values and owned
results derived from protected arguments; this is not complete reclamation for
arbitrary cancelled user code. The TLS affinity test now consumes each response
fully before requiring reuse of its connection.

## Fresh integrated measurement

[persistent-cpu-integrated.json](persistent-cpu-integrated.json) measures Release
commit `b661bccb97e70baea5146aea06bca5cf1e7e1584` with freshly built Go client and
proxy tools. All 137,901 measured responses returned 200, with zero client errors.
There were no competing builds or tests. Both worker and process groups served
all four member identities, and the rebuilt client correctly counted all four
proxy backends through the upstream identity header.

| Execution | Round | One member req/s | Four members req/s | Ratio | Four-member CPU cores |
| --- | --- | ---: | ---: | ---: | ---: |
| Workers | 1 | 797 | 2,624 | 3.29 | 3.32 |
| Workers | 2 | 705 | 1,282 | 1.82 | 3.58 |
| Processes | 1 | 827 | 3,285 | 3.97 | 3.50 |
| Processes | 2 | 619 | 2,845 | 4.60 | 3.41 |

Four-worker throughput varied from 2,624 to 1,282 req/s between rounds despite
using 3.32–3.58 CPU cores. Four-process throughput was 3,285 and 2,845 req/s, using
3.50 and 3.41 cores. The independent-server proxy produced 1,990 and 2,135 req/s.
The process ratio above four reflects variable single-member/shared-host
measurements; it is not evidence of superlinear scaling. These results establish
whole-handler multicore execution and successful responses under this short
workload, not a universal speedup or production SLO.

The workload is `/cpu` with 100,000 integer iterations per request, 64 persistent
connections, a one-second warmup and an eight-second load window per configuration.
Each configuration runs sequentially in two rounds. Raw records retain p50/p99
latency, request status and error counts, member distribution, per-thread CPU,
RSS and descriptor samples, and binary hashes. Server and client share a four-core
cgroup quota on an Intel Xeon Platinum 8573C Linux host.

Reproduce from the measured commit:

```sh
ms build bench/http-server/server.ms --build-type Release -o /tmp/http-server
go build -o /tmp/http-client bench/http-server/cpu_client.go
go build -o /tmp/http-proxy bench/http-server/proxy_group.go
python3 bench/http-server/cpu_scaling.py --server /tmp/http-server --client /tmp/http-client --proxy /tmp/http-proxy --members 4 --output /tmp/http-cpu.json
```

Next, repeat connection churn and sustained recovery on the integrated binary,
then run isolated server/client hosts with preselected throughput, latency and
resource thresholds. Earlier churn failures remain in the original evidence;
this successful persistent-connection run does not supersede those failures.

## Initial measurement before integration

`persistent-cpu-pre-integration.json` records a fresh two-round probe of the frozen
implementation binary associated with commit `32d3d5a05`. It predates integration
with main `97c5788bc`; its measurements do not validate the integrated executable.
The server hash matches the original validation report. The four-core quota is
shared with the client, and no builds competed with this measurement.

All 129,253 measured responses returned 200, with zero client errors.

| Execution | Round | One member req/s | Four members req/s | Ratio | Four-member CPU cores |
| --- | --- | ---: | ---: | ---: | ---: |
| Workers | 1 | 813 | 1,826 | 2.25 | 3.23 |
| Workers | 2 | 938 | 2,173 | 2.32 | 3.36 |
| Processes | 1 | 507 | 2,260 | 4.46 | 3.18 |
| Processes | 2 | 954 | 3,183 | 3.34 | 3.39 |

The independent-server proxy returned 1,773 and 1,618 req/s. Its member-distribution
counts are invalid: the cached Go client used for this probe predates support for
the upstream identity header. Raw data and hashes are retained and annotated;
rebuild the client before further measurements. The high process ratio and the
spread in single-member results indicate variability, not superlinear scaling.

The fresh integrated run above supersedes this probe for the current executable,
while retaining the earlier numbers and instrumentation limitation for comparison.
