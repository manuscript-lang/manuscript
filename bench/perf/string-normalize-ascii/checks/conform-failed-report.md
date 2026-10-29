# Conformance report

Binary: `/workspace/manuscript-normalize-stream/target/debug/ms`

## Overall

| | total | pass | fail | expected fail | unrecorded | rate |
|---|---:|---:|---:|---:|---:|---:|

| all | 2393 | 1608 | 785 | 0 | 0 | 67.2% |

## By phase

| | total | pass | fail | expected fail | unrecorded | rate |
|---|---:|---:|---:|---:|---:|---:|

| check | 1603 | 1603 | 0 | 0 | 0 | 100.0% |
| run | 531 | 4 | 527 | 0 | 0 | 0.8% |
| test | 259 | 1 | 258 | 0 | 0 | 0.4% |

## By tag

| | total | pass | fail | expected fail | unrecorded | rate |
|---|---:|---:|---:|---:|---:|---:|

| alternatives | 78 | 53 | 25 | 0 | 0 | 67.9% |
| closures | 403 | 165 | 238 | 0 | 0 | 40.9% |
| control-flow | 840 | 354 | 486 | 0 | 0 | 42.1% |
| decimal | 20 | 9 | 11 | 0 | 0 | 45.0% |
| destructuring | 1 | 0 | 1 | 0 | 0 | 0.0% |
| diagnostics | 1591 | 1591 | 0 | 0 | 0 | 100.0% |
| faults | 271 | 73 | 198 | 0 | 0 | 26.9% |
| functions | 316 | 79 | 237 | 0 | 0 | 25.0% |
| fuzz | 650 | 250 | 400 | 0 | 0 | 38.5% |
| generics | 216 | 164 | 52 | 0 | 0 | 75.9% |
| interfaces | 204 | 145 | 59 | 0 | 0 | 71.1% |
| interpolation | 602 | 179 | 423 | 0 | 0 | 29.7% |
| lexer | 11 | 10 | 1 | 0 | 0 | 90.9% |
| lists | 631 | 209 | 422 | 0 | 0 | 33.1% |
| maps | 73 | 47 | 26 | 0 | 0 | 64.4% |
| match | 164 | 104 | 60 | 0 | 0 | 63.4% |
| modules | 466 | 233 | 233 | 0 | 0 | 50.0% |
| mutation | 149 | 65 | 84 | 0 | 0 | 43.6% |
| numbers | 663 | 236 | 427 | 0 | 0 | 35.6% |
| optional | 222 | 128 | 94 | 0 | 0 | 57.7% |
| parser | 3 | 3 | 0 | 0 | 0 | 100.0% |
| perf | 7 | 0 | 7 | 0 | 0 | 0.0% |
| projects | 6 | 1 | 5 | 0 | 0 | 16.7% |
| records | 353 | 242 | 111 | 0 | 0 | 68.6% |
| scope-cleanup | 69 | 27 | 42 | 0 | 0 | 39.1% |
| sets | 36 | 26 | 10 | 0 | 0 | 72.2% |
| stdlib-archive | 4 | 1 | 3 | 0 | 0 | 25.0% |
| stdlib-bigint | 7 | 1 | 6 | 0 | 0 | 14.3% |
| stdlib-binary | 2 | 0 | 2 | 0 | 0 | 0.0% |
| stdlib-bits | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-bitset | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-bytes | 37 | 17 | 20 | 0 | 0 | 45.9% |
| stdlib-channels | 5 | 1 | 4 | 0 | 0 | 20.0% |
| stdlib-cleanup | 15 | 10 | 5 | 0 | 0 | 66.7% |
| stdlib-collections | 66 | 45 | 21 | 0 | 0 | 68.2% |
| stdlib-compress | 8 | 5 | 3 | 0 | 0 | 62.5% |
| stdlib-crypto | 7 | 4 | 3 | 0 | 0 | 57.1% |
| stdlib-csv | 5 | 4 | 1 | 0 | 0 | 80.0% |
| stdlib-decimal | 13 | 2 | 11 | 0 | 0 | 15.4% |
| stdlib-deque | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-encoding | 8 | 6 | 2 | 0 | 0 | 75.0% |
| stdlib-errors | 48 | 18 | 30 | 0 | 0 | 37.5% |
| stdlib-faults | 35 | 10 | 25 | 0 | 0 | 28.6% |
| stdlib-fs | 20 | 12 | 8 | 0 | 0 | 60.0% |
| stdlib-html | 3 | 1 | 2 | 0 | 0 | 33.3% |
| stdlib-http | 19 | 12 | 7 | 0 | 0 | 63.2% |
| stdlib-io | 453 | 23 | 430 | 0 | 0 | 5.1% |
| stdlib-json | 17 | 8 | 9 | 0 | 0 | 47.1% |
| stdlib-jsonstream | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-log | 3 | 2 | 1 | 0 | 0 | 66.7% |
| stdlib-math | 8 | 1 | 7 | 0 | 0 | 12.5% |
| stdlib-net | 21 | 11 | 10 | 0 | 0 | 52.4% |
| stdlib-numbers | 4 | 0 | 4 | 0 | 0 | 0.0% |
| stdlib-optional | 1 | 1 | 0 | 0 | 0 | 100.0% |
| stdlib-path | 2 | 1 | 1 | 0 | 0 | 50.0% |
| stdlib-process | 22 | 14 | 8 | 0 | 0 | 63.6% |
| stdlib-processes | 5 | 2 | 3 | 0 | 0 | 40.0% |
| stdlib-property | 2 | 0 | 2 | 0 | 0 | 0.0% |
| stdlib-queue | 2 | 2 | 0 | 0 | 0 | 100.0% |
| stdlib-queues | 15 | 8 | 7 | 0 | 0 | 53.3% |
| stdlib-random | 3 | 1 | 2 | 0 | 0 | 33.3% |
| stdlib-regex | 2 | 0 | 2 | 0 | 0 | 0.0% |
| stdlib-semver | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-shared | 6 | 1 | 5 | 0 | 0 | 16.7% |
| stdlib-sorted | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-sse | 3 | 0 | 3 | 0 | 0 | 0.0% |
| stdlib-streams | 3 | 1 | 2 | 0 | 0 | 33.3% |
| stdlib-string | 12 | 5 | 7 | 0 | 0 | 41.7% |
| stdlib-system | 5 | 2 | 3 | 0 | 0 | 40.0% |
| stdlib-tasks | 23 | 4 | 19 | 0 | 0 | 17.4% |
| stdlib-terminal | 1 | 0 | 1 | 0 | 0 | 0.0% |
| stdlib-testing | 236 | 23 | 213 | 0 | 0 | 9.7% |
| stdlib-time | 18 | 10 | 8 | 0 | 0 | 55.6% |
| stdlib-tls | 4 | 4 | 0 | 0 | 0 | 100.0% |
| stdlib-toml | 5 | 3 | 2 | 0 | 0 | 60.0% |
| stdlib-url | 3 | 0 | 3 | 0 | 0 | 0.0% |
| stdlib-websocket | 2 | 2 | 0 | 0 | 0 | 100.0% |
| stdlib-workers | 5 | 3 | 2 | 0 | 0 | 60.0% |
| stdlib-yaml | 2 | 1 | 1 | 0 | 0 | 50.0% |
| stdlib-| | 1 | 1 | 0 | 0 | 0 | 100.0% |
| strings | 728 | 304 | 424 | 0 | 0 | 41.8% |
| testing | 301 | 39 | 262 | 0 | 0 | 13.0% |
| tier-core | 1938 | 1427 | 511 | 0 | 0 | 73.6% |
| tier-io | 96 | 42 | 54 | 0 | 0 | 43.8% |
| tier-stdlib | 356 | 139 | 217 | 0 | 0 | 39.0% |
| try-result | 371 | 158 | 213 | 0 | 0 | 42.6% |
| types | 296 | 285 | 11 | 0 | 0 | 96.3% |

## Failing fixtures (785)

### `bench/agent-templates-ms` (run, projects, tier-core, try-result)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/language-calls` (run, control-flow, faults, modules, mutation, stdlib-collections, stdlib-faults, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/language-life` (run, control-flow, faults, lists, modules, mutation, stdlib-collections, stdlib-faults, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/language-list` (run, control-flow, faults, modules, mutation, stdlib-collections, stdlib-faults, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/language-numeric` (run, control-flow, faults, modules, mutation, stdlib-collections, stdlib-faults, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/lists-program` (run, closures, control-flow, faults, lists, modules, mutation, records, stdlib-collections, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `bench/lists-repro-cleared-tail` (run, control-flow, faults, modules, mutation, stdlib-faults, tier-stdlib)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `docs/contributing-compiler-conformance-semantic-tests-1` (test, control-flow, faults, modules, stdlib-faults, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "contributing-compiler-conformance-semantic-tests-1.ms::checked decrement"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-basics-numbers-and-booleans-4` (test, decimal, interpolation, modules, stdlib-decimal, stdlib-numbers, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-basics-numbers-and-booleans-4.ms::decimal amounts"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-basics-text-and-bytes-3` (test, closures, generics, interpolation, strings, testing, tier-core)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-basics-text-and-bytes-3.ms::string conversion"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-basics-text-and-bytes-4` (test, control-flow, faults, modules, optional, stdlib-bytes, stdlib-faults, strings, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-basics-text-and-bytes-4.ms::explicit byte conversion"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-control-flow-loops-2` (test, control-flow, faults, interpolation, modules, mutation, stdlib-collections, stdlib-faults, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-control-flow-loops-2.ms::sum indexes"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-control-flow-loops-3` (test, control-flow, faults, modules, mutation, stdlib-faults, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-control-flow-loops-3.ms::five iterations"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-control-flow-loops-4` (test, control-flow, modules, mutation, stdlib-collections, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-control-flow-loops-4.ms::sum even indexes"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-types-collections-5` (test, control-flow, faults, lists, maps, modules, mutation, optional, stdlib-faults, strings, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-types-collections-5.ms::dynamic mutable data and explicit copies"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-types-records-8` (test, alternatives, control-flow, faults, match, modules, records, stdlib-faults, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-types-records-8.ms::recursive expression"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/core-language-types-records-9` (test, control-flow, faults, modules, optional, records, stdlib-faults, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "core-language-types-records-9.ms::recursive links"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/developer-tooling-builds-build-levels-1` (run, functions, tier-core)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `docs/learn-best-practices-1` (test, interpolation, modules, records, stdlib-json, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-best-practices-1.ms::configuration defaults"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "learn-best-practices-1.ms::configuration rejects a wrong type"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-common-tasks-1` (run, control-flow, modules, stdlib-io, tier-core, try-result)

```diff
- exit_code: 0
- stdout:1| Hello, Manuscript!
- stdout:2| 
- stderr: ""
+ exit_code: 1
+ stdout: ""
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `docs/learn-common-tasks-5` (run, control-flow, interpolation, modules, stdlib-io, tier-core, try-result)

```diff
- exit_code: 0
- stderr: ""
+ exit_code: 1
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `docs/learn-testing-1` (test, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-testing-1.ms::addition"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "learn-testing-1.ms::zero is unchanged"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-testing-2` (test, modules, optional, stdlib-json, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-testing-2.ms::typed JSON and Optional payloads"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-testing-3` (test, control-flow, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-testing-3.ms::increments"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "learn-testing-3.ms::starts fresh"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-1` (run, control-flow, modules, stdlib-io, tier-core)

```diff
- exit_code: 0
- stdout:1| Hello, Manuscript!
- stdout:2| 
- stderr: ""
+ exit_code: 1
+ stdout: ""
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `docs/learn-tour-13` (test, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-13.ms::pipe flow"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-14` (test, control-flow, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-14.ms::counter behavior"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-15` (test, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-15.ms::own methods"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-2` (test, interpolation, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-2.ms::unread message count"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-5` (test, control-flow, modules, mutation, stdlib-collections, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-5.ms::count five iterations"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `docs/learn-tour-8` (test, alternatives, interpolation, match, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "learn-tour-8.ms::publish a help page"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/binding-groups` (test, closures, destructuring, interpolation, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "binding-groups.ms::a constant group declares each constant"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "binding-groups.ms::a var group declares mutable locals"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/boolean-optimization` (test, closures, control-flow, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "boolean-optimization.ms::boolean optimization preserves source evaluation order"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "boolean-optimization.ms::bindings read only by a folded-away operand still compile"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/bound-native-calls-omit-none-defaults` (test, control-flow, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "bound-native-calls-omit-none-defaults.ms::omitted none defaults"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/bounded-int-arithmetic` (test, closures, control-flow, generics, lists, match, modules, mutation, optional, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "bounded-int-arithmetic.ms::bounded scalar sums preserve values"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "bounded-int-arithmetic.ms::intermediate carry updates still fault"
- report.tests[1].status: "passed"
- ... 46 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/call-depth` (test, closures, control-flow, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "call-depth.ms::runaway recursion is a fault"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "call-depth.ms::runaway method recursion faults like function recursion"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/callback-probe-reuse` (test, closures, control-flow, faults, generics, interfaces, lists, modules, optional, records, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "callback-probe-reuse.ms::callback inference retains captures and contextual metadata"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "callback-probe-reuse.ms::later returns repair incomplete and convertible evidence"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-01` (test, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-01.ms::named multiline call"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-02` (test, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-02.ms::grouping and short circuit"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-03` (test, interpolation, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-03.ms::nominal record and nested binding"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-04` (test, lists, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-04.ms::list binding"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-05` (test, closures, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-05.ms::function label compatibility"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-07` (test, alternatives, match, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-07.ms::alternative result"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-08` (test, control-flow, lists, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-08.ms::iteration control"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-09` (test, generics, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-09.ms::generic argument inference"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-09-2` (test, generics, optional, testing, tier-core)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-09-2.ms::result context infers function arguments"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-10` (test, control-flow, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-10.ms::explicit contract conversion"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-10a` (test, control-flow, faults, generics, interfaces, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-10a.ms::generic implementations"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-11` (test, lists, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-11.ms::recursive immutable collection"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-12` (test, control-flow, maps, modules, mutation, sets, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-12.ms::map entry type"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-13` (test, interpolation, modules, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-13.ms::text source forms"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-14` (test, alternatives, control-flow, faults, interfaces, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-14.ms::unchanged propagated error"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-15` (test, closures, decimal, modules, optional, records, stdlib-decimal, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-15.ms::derived value equality"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-16` (test, faults, generics, lists, modules, optional, records, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-16.ms::data constructor context"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "cl-16.ms::nested constructor arguments receive inferred context"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cl-18` (test, closures, control-flow, lists, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cl-18.ms::function suite boundaries"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/cleanup-dispatch` (test, control-flow, generics, interfaces, lists, modules, records, stdlib-cleanup, stdlib-testing, testing, tier-stdlib, try-result, scope-cleanup)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "cleanup-dispatch.ms::cleanup uses the selected contract"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/closed-local-int-map` (test, closures, control-flow, faults, lists, maps, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "closed-local-int-map.ms::closed maps preserve lookup replacement and absence"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "closed-local-int-map.ms::closed map arguments retain written evaluation order"
- report.tests[1].status: "passed"
- ... 46 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/closed-record-int-bounds` (test, closures, control-flow, interfaces, lists, modules, mutation, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "closed-record-int-bounds.ms::closed cell updates preserve each operation"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "closed-record-int-bounds.ms::closed cells retain prefix overflow"
- report.tests[1].status: "passed"
- ... 46 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/closures` (test, closures, control-flow, generics, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "closures.ms::closures borrow the variable and shadowing"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/closures-snapshot` (test, closures, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "closures-snapshot.ms::closures read the variable they borrow"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/collection-call-order` (test, faults, match, modules, mutation, optional, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "collection-call-order.ms::receiver before index"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/collection-prelude` (test, alternatives, control-flow, faults, lists, maps, match, modules, mutation, numbers, optional, records, stdlib-collections, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "collection-prelude.ms::issue 187 programs need no collection imports"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "collection-prelude.ms::map add retains clones and insertion order"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/comparable` (test, control-flow, decimal, generics, interfaces, lists, match, modules, optional, records, stdlib-decimal, stdlib-math, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "comparable.ms::max and min over built-in types"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "comparable.ms::float order puts NaN above every value"
- report.tests[1].status: "passed"
- ... 46 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/compound-assignment` (test, control-flow, lists, modules, mutation, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "compound-assignment.ms::compound assignment on bindings"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "compound-assignment.ms::right side groups as one operand"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/constants` (test, alternatives, control-flow, interpolation, lists, match, modules, mutation, optional, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "constants.ms::constants stand for their initializers"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "constants.ms::each use starts from a fresh collection"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/contextual-callbacks` (test, closures, control-flow, faults, generics, interfaces, lists, modules, optional, records, stdlib-errors, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "contextual-callbacks.ms::contextual callbacks and inline returns"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/contextual-generics` (test, closures, control-flow, faults, generics, interfaces, lists, modules, optional, records, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "contextual-generics.ms::expected generic results preserve behavior and call order"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/counter-lends-string-key` (run, maps, strings, tier-io)

```diff
- exit_code: 0
- stdout:1| 3 3 2 1
- stdout:2| 
- stderr: ""
+ exit_code: 1
+ stdout: ""
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `e2e/accept/counter-steps-keep-overflow-faults` (test, closures, control-flow, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "counter-steps-keep-overflow-faults.ms::counts reach the extreme without a fault"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "counter-steps-keep-overflow-faults.ms::reassigned counter still faults"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/data-1` (test, control-flow, faults, lists, maps, modules, optional, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "data-1.ms::dynamic mutable data and explicit copies"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/data-2` (test, modules, optional, stdlib-bytes, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "data-2.ms::explicit byte conversion"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/default-type-arguments` (test, generics, lists, modules, optional, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "default-type-arguments.ms::omitted trailing type arguments use their defaults"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "default-type-arguments.ms::constructors fall back to defaults"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/derived-hash` (test, alternatives, control-flow, decimal, generics, modules, optional, records, stdlib-decimal, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "derived-hash.ms::derived hashes agree for equal values and are stable"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/direct-calls-fill-omitted-defaults` (test, control-flow, interpolation, match, modules, optional, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "direct-calls-fill-omitted-defaults.ms::omitted defaults"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/direct-collection-conversions` (test, closures, control-flow, faults, generics, interfaces, lists, maps, match, modules, mutation, optional, records, sets, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "direct-collection-conversions.ms::direct append preserves checked argument conversions"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "direct-collection-conversions.ms::direct keyed calls preserve optional keys and values"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/direct-members` (test, control-flow, faults, generics, interfaces, lists, maps, match, modules, optional, records, sets, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "direct-members.ms::list members match generic dispatch"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "direct-members.ms::map and set members"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/direct-method-semantics` (test, alternatives, control-flow, interfaces, lists, match, modules, records, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "direct-method-semantics.ms::direct methods"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/direct-methods` (test, alternatives, control-flow, faults, interfaces, lists, match, modules, mutation, optional, records, stdlib-errors, stdlib-testing, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "direct-methods.ms::method calls on concrete receivers"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "direct-methods.ms::one call site sees different receiver types"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/field-and-index-update` (run, lists, maps, mutation, records, tier-core)

```diff
- exit_code: 0
- stdout:1| 1 2 20002 20000
- stdout:2| 3 3 1 2
- stdout:3| 1 0
- stdout:4| 
- stderr: ""
+ exit_code: 1
+ stdout: ""
+ stderr:1| linking failed (exit status: 1); the linker output follows. A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error:
+ stderr:2| lld: error: /workspace/.cache/ms/native/aacc5e1b2f92ad0b-58635352/libms_native.a: Archive::children failed: truncated or malformed archive (terminator characters in archive member "\377\377"
+ stderr:3| 
```

### `e2e/accept/field-defaults` (test, closures, control-flow, faults, generics, interfaces, lists, modules, optional, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "field-defaults.ms::record defaults and explicit overrides"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "field-defaults.ms::supplied fields precede defaults in field order"
- report.tests[1].status: "passed"
- ... 41 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/function-impl` (test, closures, control-flow, generics, interfaces, interpolation, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "function-impl.ms::implementation variables inside function signatures"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/generic-instances` (test, control-flow, generics, modules, mutation, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "generic-instances.ms::parametric generics keep each instantiation's values"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "generic-instances.ms::instances copy non-scalar arguments"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/generic-record-instantiations-keep-semantics` (test, generics, lists, modules, optional, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "generic-record-instantiations-keep-semantics.ms::generic records"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/generic-specialization` (test, control-flow, generics, modules, mutation, stdlib-collections, stdlib-testing, testing, tier-stdlib, try-result, scope-cleanup)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "generic-specialization.ms::static specializations are reused across calls"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "generic-specialization.ms::recursive generics with static arguments"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/go-name-collisions` (test, alternatives, control-flow, generics, interfaces, interpolation, match, modules, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "go-name-collisions.ms::field names that differ only in underscores stay distinct"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "go-name-collisions.ms::operation names that differ only in underscores stay distinct"
- report.tests[1].status: "passed"
- ... 51 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/hash-algorithm-method-values` (test, records, stdlib-crypto, stdlib-testing, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "hash-algorithm-method-values.ms::stored HashAlgorithm operations match direct calls"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/host-accessors` (test, match, modules, stdlib-io, stdlib-net, stdlib-process, stdlib-random, stdlib-system, stdlib-testing, stdlib-time, testing, tier-io, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "host-accessors.ms::host accessors work in callbacks"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "host-accessors.ms::closing a standard stream leaves the process stream open"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/if-let` (test, control-flow, interpolation, lists, modules, mutation, optional, stdlib-errors, stdlib-testing, strings, testing, tier-stdlib, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "if-let.ms::if let unwraps a present optional"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "if-let.ms::if let takes else when absent and keeps falsy payloads"
- report.tests[1].status: "passed"
- ... 36 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/imports` (test, lists, maps, modules, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "imports.ms::grouped imports"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/inference-call-order` (test, closures, control-flow, faults, generics, interfaces, lists, modules, optional, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "inference-call-order.ms::reused inference preserves evaluation and argument conversions"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/inherent-methods` (test, alternatives, control-flow, faults, generics, interfaces, match, modules, records, stdlib-faults, strings, testing, tier-stdlib)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "inherent-methods.ms::inherent methods"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/inline-functions` (test, closures, generics, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "inline-functions.ms::inline callbacks survive contextual rechecking"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/inline-suites` (test, closures, control-flow, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "inline-suites.ms::inline functions and branches"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "inline-suites.ms::inline test"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/inlined-list-callbacks-keep-semantics` (test, closures, control-flow, faults, interpolation, lists, modules, mutation, numbers, optional, records, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "inlined-list-callbacks-keep-semantics.ms::inlined callbacks"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/int-identities` (test, control-flow, lists, modules, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "int-identities.ms::identities keep boundaries"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "int-identities.ms::identities keep operand effects"
- report.tests[1].status: "passed"
- ... 31 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/int-keyed-map-calls-keep-semantics` (test, control-flow, faults, maps, match, modules, mutation, optional, stdlib-testing, strings, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "int-keyed-map-calls-keep-semantics.ms::int map"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/int-literal-divisors-keep-semantics` (test, control-flow, modules, mutation, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "int-literal-divisors-keep-semantics.ms::literal divisors"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/interface-generics` (test, control-flow, faults, generics, interfaces, modules, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "interface-generics.ms::parameters and bounds belong to interfaces and types"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/interface-method-calls-cache-each-receiver-type` (test, control-flow, interfaces, lists, modules, mutation, records, stdlib-testing, testing, tier-core, try-result)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "interface-method-calls-cache-each-receiver-type.ms::three receiver types alternate at one site"
- report.tests[0].status: "passed"
- report.summary.available: 1
- report.summary.selected: 1
- report.summary.passed: 1
- ... 26 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

### `e2e/accept/interface-view-callables` (test, closures, control-flow, generics, interfaces, match, modules, mutation, optional, records, stdlib-testing, strings, testing, tier-core, try-result, scope-cleanup)

```diff
- exit_code: 0
- report.repeat: 1
- report.tests[0].index: 0
- report.tests[0].name: "interface-view-callables.ms::nested view receiver prepares once and calls later"
- report.tests[0].status: "passed"
- report.tests[1].index: 1
- report.tests[1].name: "interface-view-callables.ms::constructor arguments retain written order and capture snapshots"
- report.tests[1].status: "passed"
- ... 46 more
+ exit_code: 1
+ report.tests: []
+ report.summary.available: 0
+ report.summary.selected: 0
+ report.summary.passed: 0
+ report.completed: false
+ report.exit_code: 1
+ report.reason: "build_error"
+ ... 34 more
```

... 685 more not shown

